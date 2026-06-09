import CoreSpotlight
import Foundation

enum CoreSpotlightAppEntityProvider {
    static func search(
        source: SearchSource,
        context: ProviderSearchContext,
        entityType: String,
        contentTypes: [String],
        bundleIdentifiers: [String],
        allowMail: Bool = false
    ) -> [SearchResultRecord] {
        let queryText = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else {
            return []
        }

        let filters = contentTypes.map { "contentType == \(literal($0))" }
            + bundleIdentifiers.flatMap { bundleID in
                [
                    "bundleID == \(literal(bundleID))",
                    "_kMDItemBundleID == \(literal(bundleID))"
                ]
            }
        guard !filters.isEmpty else {
            return []
        }

        let textPredicates = [
            "title == \(literal("*\(queryText)*"))",
            "displayName == \(literal("*\(queryText)*"))",
            "textContent == \(literal("*\(queryText)*"))",
            "kMDItemDisplayName == \(literal("*\(queryText)*"))",
            "_kMDItemSnippet == \(literal("*\(queryText)*"))"
        ]
        let queryString = "(\(filters.joined(separator: " || "))) && (\(textPredicates.joined(separator: " || ")))"
        let queryContext = CSSearchQueryContext()
        queryContext.fetchAttributes = [
            "title",
            "displayName",
            "contentType",
            "bundleID",
            "_kMDItemBundleID",
            "domainIdentifier",
            "url",
            "textContent",
            "_kMDItemSnippet",
            "kMDItemDisplayName",
            "kMDItemURL",
            "kMDItemContentCreationDate",
            "kMDItemContentModificationDate"
        ]
        if allowMail {
            queryContext.sourceOptions = .allowMail
        }

        let query = CSSearchQuery(queryString: queryString, queryContext: queryContext)
        let semaphore = DispatchSemaphore(value: 0)
        let accumulator = CoreSpotlightResultAccumulator()
        query.foundItemsHandler = { items in
            accumulator.items.append(contentsOf: items)
        }
        query.completionHandler = { error in
            accumulator.error = error
            semaphore.signal()
        }
        query.start()
        _ = semaphore.wait(timeout: .now() + 2)
        query.cancel()

        guard accumulator.error == nil else {
            return []
        }

        var seen: Set<String> = []
        return accumulator.items.compactMap { item in
            guard seen.insert(item.uniqueIdentifier).inserted else {
                return nil
            }
            return record(from: item, source: source, entityType: entityType)
        }.prefixArray(context.limit)
    }

    private static func record(from item: CSSearchableItem, source: SearchSource, entityType: String) -> SearchResultRecord {
        let attributes = item.attributeSet
        let title = attributes.title
            ?? attributes.displayName
            ?? stringAttribute("kMDItemDisplayName", from: attributes)
            ?? item.uniqueIdentifier
        let url = attributes.url?.absoluteString ?? stringAttribute("kMDItemURL", from: attributes)
        let bundleID = stringAttribute("bundleID", from: attributes) ?? stringAttribute("_kMDItemBundleID", from: attributes)
        let snippet = stringAttribute("_kMDItemSnippet", from: attributes)
        return SearchResultRecord(
            id: SearchUtilities.stableID([source.rawValue, item.uniqueIdentifier]),
            source: source.rawValue,
            entityType: entityType,
            title: title,
            subtitle: snippet ?? bundleID ?? item.domainIdentifier,
            url: url,
            contentType: attributes.contentType,
            createdAt: dateAttribute("kMDItemContentCreationDate", from: attributes),
            modifiedAt: dateAttribute("kMDItemContentModificationDate", from: attributes),
            metadata: [
                "coreSpotlightIdentifier": .string(item.uniqueIdentifier),
                "domainIdentifier": item.domainIdentifier.map(JSONValue.string) ?? .null,
                "bundleIdentifier": bundleID.map(JSONValue.string) ?? .null,
                "matchReason": .string("core-spotlight-app-entity")
            ]
        )
    }

    private static func stringAttribute(_ name: String, from attributes: CSSearchableItemAttributeSet) -> String? {
        attributes.value(forKey: name) as? String
    }

    private static func dateAttribute(_ name: String, from attributes: CSSearchableItemAttributeSet) -> Date? {
        attributes.value(forKey: name) as? Date
    }

    private static func literal(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

private final class CoreSpotlightResultAccumulator: @unchecked Sendable {
    var items: [CSSearchableItem] = []
    var error: Error?
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
