import Foundation

struct SafariHistoryProvider: SearchProvider {
    let source: SearchSource = .safari
    let historyDBPath: String

    static let defaultHistoryDBPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/History.db").path

    init(historyDBPath: String = SafariHistoryProvider.defaultHistoryDBPath) {
        self.historyDBPath = historyDBPath
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }

        if historyDBPath == Self.defaultHistoryDBPath {
            let coreSpotlightResults = CoreSpotlightAppEntityProvider.search(
                source: .safari,
                context: context,
                entityType: "safari-history",
                contentTypes: ["com.apple.safari.history"],
                bundleIdentifiers: ["com.apple.Safari", "com.apple.bookmarks"]
            )
            if !coreSpotlightResults.isEmpty {
                return coreSpotlightResults
            }
        }

        guard FileManager.default.fileExists(atPath: historyDBPath) else {
            let safariURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
            if ProtectedStore.isUnreadableExistingPath(safariURL) {
                throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Safari", path: safariURL.path))
            }
            throw ProviderError.unavailable("Safari history database is not available")
        }
        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase(path: historyDBPath)
        } catch {
            if ProtectedStore.isSQLiteAuthorizationDenied(error) {
                throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Safari", path: historyDBPath))
            }
            throw error
        }

        let itemColumns = try columnNames(table: "history_items", in: db)
        let visitColumns = try columnNames(table: "history_visits", in: db)
        let itemTitle = itemColumns.contains("title") ? "hi.title" : nil
        let visitTitle = visitColumns.contains("title")
            ? "(SELECT hv2.title FROM history_visits hv2 WHERE hv2.history_item = hi.id AND hv2.title IS NOT NULL ORDER BY hv2.visit_time DESC LIMIT 1)"
            : nil
        let visitTitleHaystack = visitColumns.contains("title") ? "hv.title" : nil
        let titleColumns = [itemTitle, visitTitle].compactMap { $0 }
        let titleExpression: String
        if titleColumns.isEmpty {
            titleExpression = "NULL"
        } else if titleColumns.count == 1 {
            titleExpression = titleColumns[0]
        } else {
            titleExpression = "coalesce(\(titleColumns.joined(separator: ", ")))"
        }
        let haystack = [
            "hi.url",
            itemColumns.contains("domain_expansion") ? "hi.domain_expansion" : nil,
            itemTitle,
            visitTitleHaystack
        ].compactMap { $0 }
            .map { "coalesce(\($0), '')" }
            .joined(separator: " || ' ' || ")

        let rows = try db.rows(
            """
            SELECT hi.id,
                   hi.url,
                   \(titleExpression) AS title,
                   max(hv.visit_time) AS visit_time,
                   count(hv.id) AS visit_count
            FROM history_items hi
            LEFT JOIN history_visits hv ON hv.history_item = hi.id
            WHERE lower(\(haystack)) LIKE lower(?)
            GROUP BY hi.id
            ORDER BY visit_time DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .int(Int64(context.limit * 5))]
        )

        var seenCanonicalURLs: Set<String> = []
        var records: [SearchResultRecord] = []
        for row in rows {
            guard let id = row["id"]?.int64 else { continue }
            let url = row["url"]?.string
            if let url, !seenCanonicalURLs.insert(canonicalHistoryKey(url)).inserted {
                continue
            }
            records.append(SearchResultRecord(
                id: SearchUtilities.stableID([SearchSource.safari.rawValue, String(id)]),
                source: SearchSource.safari.rawValue,
                entityType: "safari-history",
                title: row["title"]?.string ?? url ?? "Safari history item",
                subtitle: url,
                url: url,
                modifiedAt: SearchUtilities.macAbsoluteDate(row["visit_time"]?.double),
                metadata: [
                    "historyID": .number(Double(id)),
                    "visitedAt": JSONValue.convert(SearchUtilities.macAbsoluteDate(row["visit_time"]?.double)),
                    "visitCount": .number(Double(row["visit_count"]?.int64 ?? 0))
                ]
            ))
            if records.count == context.limit {
                break
            }
        }
        return records
    }

    private func canonicalHistoryKey(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        components.fragment = nil
        let trackingPrefixes = ["utm_", "fbclid", "gclid", "msclkid", "ref", "qid", "crid", "sprefix", "ds"]
        let meaningfulQueryItems = (components.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return !trackingPrefixes.contains(where: { name == $0 || name.hasPrefix($0) })
        }
        components.queryItems = meaningfulQueryItems.isEmpty ? nil : meaningfulQueryItems.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return (lhs.value ?? "") < (rhs.value ?? "")
            }
            return lhs.name < rhs.name
        }

        let host = components.host?.lowercased()
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [
            host,
            path.isEmpty ? nil : path,
            components.query
        ].compactMap { $0 }.joined(separator: "/")
    }

    private func columnNames(table: String, in db: SQLiteDatabase) throws -> Set<String> {
        Set(try db.rows("PRAGMA table_info(\(table))").compactMap { $0["name"]?.string })
    }
}
