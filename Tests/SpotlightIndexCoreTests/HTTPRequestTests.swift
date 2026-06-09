import Foundation
import XCTest
@testable import SpotlightIndexCore

final class HTTPRequestTests: XCTestCase {
    func testParseRejectsNegativeContentLength() {
        let data = Data("""
        GET /health HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Length: -1\r
        \r

        """.utf8)

        guard case .badRequest = HTTPRequest.parse(data: data, maxHeaderBytes: 1024, maxBodyBytes: 1024) else {
            return XCTFail("expected bad request")
        }
    }

    func testParseHandlesDuplicateQueryKeysWithoutCrashing() throws {
        let data = Data("""
        GET /v1/item?id=first&id=second&source=notes HTTP/1.1\r
        Host: 127.0.0.1\r
        \r

        """.utf8)

        guard case .complete(let request) = HTTPRequest.parse(data: data, maxHeaderBytes: 1024, maxBodyBytes: 1024) else {
            return XCTFail("expected complete request")
        }

        XCTAssertEqual(request.path, "/v1/item")
        XCTAssertEqual(request.queryItems["id"], "second")
        XCTAssertEqual(request.queryItems["source"], "notes")
    }

    func testParseRejectsOversizedBodyFromContentLength() {
        let data = Data("""
        POST /v1/search HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Length: 1025\r
        \r

        """.utf8)

        guard case .payloadTooLarge = HTTPRequest.parse(data: data, maxHeaderBytes: 1024, maxBodyBytes: 1024) else {
            return XCTFail("expected payload too large")
        }
    }
}
