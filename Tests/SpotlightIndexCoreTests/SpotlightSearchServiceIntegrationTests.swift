import Foundation
import XCTest
@testable import SpotlightIndexCore

final class SpotlightSearchServiceIntegrationTests: XCTestCase {
    func testSearchApplicationsReturnsApplicationMetadata() throws {
        guard FileManager.default.fileExists(atPath: "/Applications") else {
            throw XCTSkip("/Applications is not available")
        }

        let service = SpotlightSearchService()
        let response = try service.search(SearchRequest(query: "", types: ["application"], onlyIn: ["/Applications"], limit: 25))

        guard !response.results.isEmpty else {
            throw XCTSkip("Spotlight returned no application results from /Applications")
        }

        XCTAssertLessThanOrEqual(response.results.count, 25)
        XCTAssertTrue(response.results.contains { $0.contentType == "com.apple.application-bundle" })

        let recordWithBundleID = response.results.first(where: { $0.metadata[SpotlightAttributes.bundleIdentifier] != nil })
        XCTAssertNotNil(recordWithBundleID?.title)
        XCTAssertNotNil(recordWithBundleID?.metadata[SpotlightAttributes.version])
    }

    func testItemReturnsMetadataForKnownFile() throws {
        let service = SpotlightSearchService()
        let response = try service.item(at: #filePath)

        XCTAssertEqual(response.item.path, #filePath)
        XCTAssertNotNil(response.item.displayName)
        XCTAssertNotNil(response.item.contentType)
        XCTAssertEqual(response.item.metadata[SpotlightAttributes.authors], .null)
    }
}
