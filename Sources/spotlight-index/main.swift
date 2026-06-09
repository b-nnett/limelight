import Foundation
import SpotlightIndexCore

struct Arguments {
    var host = "127.0.0.1"
    var port: UInt16 = 8765
    var menuBar: Bool?
}

func parseArguments(_ values: [String]) -> Arguments {
    var arguments = Arguments()
    var iterator = values.dropFirst().makeIterator()

    while let value = iterator.next() {
        switch value {
        case "--host":
            if let host = iterator.next() {
                arguments.host = host
            }
        case "--port":
            if let portValue = iterator.next(), let port = UInt16(portValue) {
                arguments.port = port
            }
        case "--menu-bar":
            arguments.menuBar = true
        case "--no-menu-bar":
            arguments.menuBar = false
        default:
            break
        }
    }

    return arguments
}

#if canImport(AppKit)
let launchedFromAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
#else
let launchedFromAppBundle = false
#endif

func hostIsLoopback(_ host: String) -> Bool {
    let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "localhost"
        || normalized == "::1"
        || normalized == "[::1]"
        || normalized.hasPrefix("127.")
}

struct StartedHTTPServer {
    let server: SpotlightHTTPServer
    let port: UInt16
}

private struct EndpointRecord: Encodable {
    let baseURL: String
    let host: String
    let port: UInt16
    let updatedAt: Date
}

func endpointFileURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Limelight/endpoint.json")
}

func writeEndpointFile(host: String, port: UInt16) {
    let url = endpointFileURL()
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = EndpointRecord(
            baseURL: "http://\(host):\(port)",
            host: host,
            port: port,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: url, options: [.atomic])
    } catch {
        fputs("warning: failed to write Limelight endpoint file: \(error.localizedDescription)\n", stderr)
    }
}

func startSpotlightHTTPServer(
    host: String,
    preferredPort: UInt16,
    onSearch: SpotlightHTTPServer.SearchObserver? = nil
) throws -> StartedHTTPServer {
    var lastError: Error?

    for offset in 0..<10 {
        let candidate = Int(preferredPort) + offset
        guard candidate <= Int(UInt16.max) else {
            break
        }

        let port = UInt16(candidate)
        let server = SpotlightHTTPServer(host: host, port: port, onSearch: onSearch)
        do {
            try server.start()
            writeEndpointFile(host: host, port: port)
            if port != preferredPort {
                fputs("port \(preferredPort) was unavailable; Limelight listening on http://\(host):\(port)\n", stderr)
            }
            return StartedHTTPServer(server: server, port: port)
        } catch {
            lastError = error
        }
    }

    throw lastError ?? NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE), userInfo: [NSLocalizedDescriptionKey: "no available Limelight port"])
}

var arguments = parseArguments(CommandLine.arguments)

if !hostIsLoopback(arguments.host) {
    fputs("refusing to start Limelight server on non-loopback host \(arguments.host). Bind it to 127.0.0.1 or localhost.\n", stderr)
    exit(1)
}

#if canImport(AppKit)
if arguments.menuBar == true || (arguments.menuBar == nil && launchedFromAppBundle) {
    runMenuBarApp(arguments: arguments)
    exit(0)
}
#endif

do {
    let started = try startSpotlightHTTPServer(host: arguments.host, preferredPort: arguments.port)
    print("spotlight-index listening on http://\(arguments.host):\(started.port)")
    dispatchMain()
} catch {
    fputs("failed to start spotlight-index: \(error.localizedDescription)\n", stderr)
    exit(1)
}
