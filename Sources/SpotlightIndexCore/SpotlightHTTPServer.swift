import Foundation
import Network

public final class SpotlightHTTPServer: @unchecked Sendable {
    public typealias SearchObserver = @Sendable (SearchRequest, SearchResponse, SearchAuditContext) -> Void

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let service: SpotlightSearchService
    private let onSearch: SearchObserver?
    private let authToken: String?
    private let queue = DispatchQueue(label: "spotlight-index.http")
    private var listener: NWListener?

    public init(
        host: String = "127.0.0.1",
        port: UInt16 = 8765,
        service: SpotlightSearchService = SpotlightSearchService(),
        onSearch: SearchObserver? = nil,
        authToken: String? = nil
    ) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 8765
        self.service = service
        self.onSearch = onSearch
        self.authToken = authToken?.isEmpty == false ? authToken : nil
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = nil
        listener.newConnectionHandler = { [service, onSearch, authToken] connection in
            HTTPConnectionHandler(connection: connection, service: service, onSearch: onSearch, authToken: authToken).start()
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}

private final class HTTPConnectionHandler: @unchecked Sendable {
    private let connection: NWConnection
    private let service: SpotlightSearchService
    private let onSearch: SpotlightHTTPServer.SearchObserver?
    private let authToken: String?
    private var buffer = Data()
    private var retainSelf: HTTPConnectionHandler?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(connection: NWConnection, service: SpotlightSearchService, onSearch: SpotlightHTTPServer.SearchObserver?, authToken: String?) {
        self.connection = connection
        self.service = service
        self.onSearch = onSearch
        self.authToken = authToken
    }

    func start() {
        retainSelf = self
        connection.start(queue: DispatchQueue(label: "spotlight-index.connection"))
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let data {
                self.buffer.append(data)
            }

            if let request = HTTPRequest(data: self.buffer) {
                self.handle(request)
            } else if isComplete || error != nil {
                self.send(status: 400, body: ErrorResponse(error: "malformed HTTP request"))
            } else {
                self.receive()
            }
        }
    }

    private func handle(_ request: HTTPRequest) {
        guard isAuthorized(request) else {
            send(status: 401, body: ErrorResponse(error: "unauthorized"))
            return
        }

        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                send(status: 200, body: service.health())
            case ("GET", "/v1/schema"):
                send(status: 200, body: service.schema())
            case ("GET", "/v1/providers"):
                send(status: 200, body: service.providerReadiness())
            case ("GET", "/v1/capabilities"):
                send(status: 200, body: service.capabilities())
            case ("POST", "/v1/permissions/request"):
                let permissionRequest = try JSONDecoder().decode(PermissionRequest.self, from: request.body)
                send(status: 200, body: try service.requestPermissions(permissionRequest))
            case ("POST", "/v1/deep-search"):
                let deepSearchRequest = try JSONDecoder().decode(DeepSearchRequest.self, from: request.body)
                send(status: 200, body: try service.deepSearch(deepSearchRequest))
            case ("POST", "/v1/ocr"):
                let ocrRequest = try JSONDecoder().decode(OCRRequest.self, from: request.body)
                send(status: 200, body: try service.ocr(ocrRequest))
            case ("POST", "/v1/extract"):
                let extractRequest = try JSONDecoder().decode(ExtractRequest.self, from: request.body)
                send(status: 200, body: try service.extract(extractRequest))
            case ("POST", "/v1/open"):
                let openRequest = try JSONDecoder().decode(OpenItemRequest.self, from: request.body)
                send(status: 200, body: try service.open(openRequest))
            case ("GET", "/v1/item"):
                if let path = request.queryItems["path"], !path.isEmpty {
                    send(status: 200, body: try service.item(at: path))
                } else if let source = request.queryItems["source"], !source.isEmpty,
                          let id = request.queryItems["id"], !id.isEmpty {
                    send(status: 200, body: try service.item(source: source, id: id))
                } else {
                    send(status: 400, body: ErrorResponse(error: "missing required query parameter: path or source and id"))
                }
            case ("GET", "/v1/photos/thumbnail"):
                guard let uuid = request.queryItems["id"] ?? request.queryItems["uuid"], !uuid.isEmpty else {
                    send(status: 400, body: ErrorResponse(error: "missing required query parameter: id"))
                    return
                }
                let file = try service.photoThumbnail(uuid: uuid)
                sendFile(path: file.path, contentType: file.contentType)
            case ("POST", "/v1/search"):
                let searchRequest = try JSONDecoder().decode(SearchRequest.self, from: request.body)
                let response = try service.search(searchRequest)
                onSearch?(searchRequest, response, SearchAuditContext(request: request))
                send(status: 200, body: response)
            default:
                send(status: 404, body: ErrorResponse(error: "not found"))
            }
        } catch {
            send(status: 400, body: ErrorResponse(error: error.localizedDescription))
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let authToken else {
            return true
        }
        if request.method == "GET" && request.path == "/health" {
            return true
        }
        return request.headers["authorization"] == "Bearer \(authToken)"
    }

    private func send<T: Encodable>(status: Int, body: T) {
        let responseBody: Data
        do {
            responseBody = try encoder.encode(body)
        } catch {
            responseBody = Data("{\"error\":\"failed to encode response\"}".utf8)
        }

        let reason = HTTPStatus.reasonPhrase(for: status)
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(responseBody.count)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(responseBody)

        connection.send(content: response, completion: .contentProcessed { [connection] _ in
            connection.cancel()
            self.retainSelf = nil
        })
    }

    private func sendFile(path: String, contentType: String) {
        do {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
            let header = """
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Content-Length: \(fileData.count)\r
            Cache-Control: private, max-age=300\r
            Connection: close\r
            \r

            """
            var response = Data(header.utf8)
            response.append(fileData)
            connection.send(content: response, completion: .contentProcessed { [connection] _ in
                connection.cancel()
                self.retainSelf = nil
            })
        } catch {
            send(status: 404, body: ErrorResponse(error: "thumbnail file is not readable"))
        }
    }
}

public struct SearchAuditContext: Equatable, Sendable {
    public let originatorApp: String
    public let userAgent: String?

    fileprivate init(request: HTTPRequest) {
        let explicitOrigin = request.headers["x-limelight-origin"] ?? request.headers["x-originator-app"]
        let userAgent = request.headers["user-agent"]
        self.originatorApp = explicitOrigin?.isEmpty == false ? explicitOrigin! : (userAgent?.isEmpty == false ? userAgent! : "Unknown local client")
        self.userAgent = userAgent
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let rawTarget = requestParts[1]
        let components = URLComponents(string: "http://127.0.0.1\(rawTarget)")
        self.method = requestParts[0]
        self.path = components?.path ?? rawTarget
        self.queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else {
                return nil
            }
            return (item.name, value)
        })
        self.headers = headers
        self.body = Data(data[bodyStart..<(bodyStart + contentLength)])
    }
}

private enum HTTPStatus {
    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200:
            "OK"
        case 400:
            "Bad Request"
        case 404:
            "Not Found"
        case 401:
            "Unauthorized"
        default:
            "Internal Server Error"
        }
    }
}
