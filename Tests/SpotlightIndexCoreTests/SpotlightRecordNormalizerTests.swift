import XCTest
@testable import SpotlightIndexCore

final class SpotlightRecordNormalizerTests: XCTestCase {
    func testNormalizesKnownAttributesAndKeepsRawMetadata() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let reader = MockMetadataReader(
            path: "/Applications/Codex.app",
            values: [
                SpotlightAttributes.displayName: "Codex",
                SpotlightAttributes.contentType: "com.apple.application-bundle",
                SpotlightAttributes.kind: "Application",
                SpotlightAttributes.bundleIdentifier: "com.openai.codex",
                SpotlightAttributes.createdAt: createdAt,
                SpotlightAttributes.modifiedAt: modifiedAt,
                SpotlightAttributes.authors: ["OpenAI"],
                SpotlightAttributes.sizeBytes: NSNumber(value: 1234),
                SpotlightAttributes.version: "1.2.3"
            ]
        )

        let record = SpotlightRecordNormalizer.normalize(reader)

        XCTAssertEqual(record.path, "/Applications/Codex.app")
        XCTAssertEqual(record.displayName, "Codex")
        XCTAssertEqual(record.contentType, "com.apple.application-bundle")
        XCTAssertEqual(record.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(record.createdAt, createdAt)
        XCTAssertEqual(record.modifiedAt, modifiedAt)
        XCTAssertEqual(record.authors, ["OpenAI"])
        XCTAssertEqual(record.sizeBytes, 1234)
        XCTAssertEqual(record.metadata[SpotlightAttributes.version], .string("1.2.3"))
        XCTAssertNil(record.metadata["kMDItemTextContent"])
        XCTAssertEqual(record.id, SpotlightRecordNormalizer.stableID(path: record.path, contentType: record.contentType))
    }
}
