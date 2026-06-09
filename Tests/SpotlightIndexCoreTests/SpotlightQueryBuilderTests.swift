import XCTest
@testable import SpotlightIndexCore

final class SpotlightQueryBuilderTests: XCTestCase {
    func testBuildSanitizesUserQueryBeforeAddingPredicateSyntax() throws {
        let request = SearchRequest(
            query: "Codex' || kMDItemFSName == '*' || '",
            types: ["application"],
            onlyIn: ["/Applications"],
            limit: 999
        )

        let built = try SpotlightQueryBuilder.build(from: request)

        XCTAssertFalse(built.expression.contains("== '*'"))
        XCTAssertFalse(built.expression.contains("Codex'"))
        XCTAssertTrue(built.expression.contains("Codex kMDItemFSName"))
        XCTAssertTrue(built.expression.contains("kMDItemContentType == 'com.apple.application-bundle'"))
        XCTAssertEqual(built.scopes, ["/Applications"])
        XCTAssertEqual(built.limit, 500)
    }

    func testRejectsUnsupportedType() {
        let request = SearchRequest(query: "Codex", types: ["mail"])
        XCTAssertThrowsError(try SpotlightQueryBuilder.build(from: request)) { error in
            XCTAssertEqual(error as? SpotlightQueryError, .unsupportedType("mail"))
        }
    }

    func testRejectsRelativeScope() {
        let request = SearchRequest(query: "", onlyIn: ["Documents"])
        XCTAssertThrowsError(try SpotlightQueryBuilder.build(from: request)) { error in
            XCTAssertEqual(error as? SpotlightQueryError, .invalidScope("Documents"))
        }
    }

    func testEmptyQueryUsesTypePredicateWhenTypeIsProvided() throws {
        let built = try SpotlightQueryBuilder.build(from: SearchRequest(query: "", types: ["application"], limit: 0))
        XCTAssertEqual(built.expression, "(kMDItemContentType == 'com.apple.application-bundle')")
        XCTAssertEqual(built.limit, 1)
    }
}
