import Compression
import Foundation

struct NotesSQLiteProvider: SearchProvider {
    let source: SearchSource = .notes
    let notesDBPath: String?

    init(notesDBPath: String? = nil) {
        self.notesDBPath = notesDBPath
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }

        if notesDBPath == nil {
            let coreSpotlightResults = CoreSpotlightAppEntityProvider.search(
                source: .notes,
                context: context,
                entityType: "note",
                contentTypes: ["com.apple.notes.note", "public.audio-transcript"],
                bundleIdentifiers: ["com.apple.Notes"]
            )
            if !coreSpotlightResults.isEmpty {
                return coreSpotlightResults
            }
        }

        let paths = notesDBPath.map { [$0] } ?? notesStoreCandidates().map(\.path)
        var authorizationDeniedPath: String?
        var lastError: Error?
        for path in paths {
            do {
                let db = try SQLiteDatabase(path: path)
                if try tableExists("notes", in: db) {
                    return try searchFixtureShape(context, db: db)
                }
                if try tableExists("ZICCLOUDSYNCINGOBJECT", in: db) {
                    return try searchAppleNotesShape(context, db: db)
                }
                lastError = ProviderError.unavailable("Notes schema is not recognized")
            } catch {
                lastError = error
                if ProtectedStore.isSQLiteAuthorizationDenied(error) {
                    authorizationDeniedPath = path
                }
            }
        }

        if let authorizationDeniedPath {
            throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Notes", path: authorizationDeniedPath))
        }

        if notesDBPath == nil,
           let unreadable = notesStoreCandidates().first(where: { ProtectedStore.isUnreadableExistingPath($0.deletingLastPathComponent()) }) {
            throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Notes", path: unreadable.deletingLastPathComponent().path))
        }

        throw ProviderError.unavailable(lastError?.localizedDescription ?? "Notes database is not available")
    }

    private func searchFixtureShape(_ context: ProviderSearchContext, db: SQLiteDatabase) throws -> [SearchResultRecord] {
        let rows = try db.rows(
            """
            SELECT id, title, body, modified_at
            FROM notes
            WHERE lower(coalesce(title, '') || ' ' || coalesce(body, '')) LIKE lower(?)
            ORDER BY CASE WHEN lower(coalesce(title, '')) LIKE lower(?) THEN 0 ELSE 1 END,
                     modified_at DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .text("%\(context.query)%"), .int(Int64(context.limit))]
        )

        return rows.compactMap { row in
            guard let id = row["id"]?.int64 else { return nil }
            return noteRecord(
                id: String(id),
                title: row["title"]?.string ?? "Note",
                snippet: row["body"]?.string,
                modifiedAt: row["modified_at"]?.double,
                query: context.query
            )
        }
    }

    private func searchAppleNotesShape(_ context: ProviderSearchContext, db: SQLiteDatabase) throws -> [SearchResultRecord] {
        let columns = try columnNames(table: "ZICCLOUDSYNCINGOBJECT", in: db)
        let titleColumn = firstExisting(["ZTITLE1", "ZTITLE", "ZNAME"], in: columns)
        let bodyColumn = firstExisting(["ZSNIPPET", "ZPLAINTEXT", "ZSUMMARY"], in: columns)
        let modifiedColumn = firstExisting(["ZMODIFICATIONDATE1", "ZMODIFICATIONDATE", "ZLASTEDITEDDATE"], in: columns)
        let noteDataJoin = try noteDataJoin(objectColumns: columns, db: db)
        guard let titleColumn else {
            throw ProviderError.unavailable("Notes title column is not recognized")
        }

        let bodyExpression = bodyColumn.map { "o.\($0)" } ?? noteDataJoin?.textExpression
        let shouldScanBlob = bodyExpression == nil && noteDataJoin?.blobExpression != nil
        let haystackExpressions = ["o.\(titleColumn)", bodyExpression].compactMap { $0 }
        let haystack = haystackExpressions.map { "coalesce(CAST(\($0) AS TEXT), '')" }.joined(separator: " || ' ' || ")
        let scanLimit = min(max(context.limit * 20, 1000), 5000)
        let rows = try db.rows(
            """
            SELECT o.Z_PK,
                   o.\(titleColumn) AS title,
                   \(bodyExpression ?? "NULL") AS body,
                   \(noteDataJoin?.blobExpression ?? "NULL") AS body_blob,
                   \(modifiedColumn.map { "o.\($0)" } ?? "NULL") AS modified_at
            FROM ZICCLOUDSYNCINGOBJECT o
            \(noteDataJoin?.joinSQL ?? "")
            WHERE \(shouldScanBlob ? "1 = 1" : "lower(\(haystack)) LIKE lower(?)")
            ORDER BY CASE WHEN lower(coalesce(CAST(o.\(titleColumn) AS TEXT), '')) LIKE lower(?) THEN 0 ELSE 1 END,
                     \(modifiedColumn.map { "o.\($0)" } ?? "o.Z_PK") DESC
            LIMIT ?
            """,
            bindings: shouldScanBlob
                ? [.text("%\(context.query)%"), .int(Int64(scanLimit))]
                : [.text("%\(context.query)%"), .text("%\(context.query)%"), .int(Int64(context.limit))]
        )

        let records = rows.compactMap { row -> SearchResultRecord? in
            guard let id = row["Z_PK"]?.int64 else { return nil }
            let body = row["body"]?.textValue ?? textFromNoteBlob(row["body_blob"]?.data)
            if shouldScanBlob,
               !SearchUtilities.contains(row["title"]?.textValue, context.query),
               !SearchUtilities.contains(body, context.query) {
                return nil
            }
            return noteRecord(
                id: String(id),
                title: row["title"]?.textValue ?? "Note",
                snippet: body.map(trimSnippet),
                modifiedAt: row["modified_at"]?.double,
                query: context.query
            )
        }
        return Array(records.sorted { lhs, rhs in
            let lhsRank = lhs.metadata["matchReason"] == .string("title") ? 0 : 1
            let rhsRank = rhs.metadata["matchReason"] == .string("title") ? 0 : 1
            if lhsRank == rhsRank {
                return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
            return lhsRank < rhsRank
        }.prefix(context.limit))
    }

    private func noteRecord(id: String, title: String, snippet: String?, modifiedAt: Double?, query: String) -> SearchResultRecord {
        let matchReason = SearchUtilities.contains(title, query) ? "title" : "body"
        return SearchResultRecord(
            id: SearchUtilities.stableID([SearchSource.notes.rawValue, id]),
            source: SearchSource.notes.rawValue,
            entityType: "note",
            title: title,
            subtitle: snippet,
            modifiedAt: SearchUtilities.macAbsoluteDate(modifiedAt),
            metadata: [
                "noteID": .string(id),
                "matchReason": .string(matchReason)
            ]
        )
    }

    private func notesStoreCandidates() -> [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.apple.Notes/Data/Library/Notes/NotesV7.storedata")
        ]
    }

    private func tableExists(_ name: String, in db: SQLiteDatabase) throws -> Bool {
        try !db.rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", bindings: [.text(name)]).isEmpty
    }

    private func columnNames(table: String, in db: SQLiteDatabase) throws -> Set<String> {
        Set(try db.rows("PRAGMA table_info(\(table))").compactMap { $0["name"]?.string })
    }

    private func firstExisting(_ candidates: [String], in columns: Set<String>) -> String? {
        candidates.first { columns.contains($0) }
    }

    private func noteDataJoin(objectColumns: Set<String>, db: SQLiteDatabase) throws -> NoteDataJoin? {
        guard try tableExists("ZICNOTEDATA", in: db) else {
            return nil
        }
        let columns = try columnNames(table: "ZICNOTEDATA", in: db)
        let joinSQL: String?
        if columns.contains("ZNOTE") {
            joinSQL = "LEFT JOIN ZICNOTEDATA nd ON nd.ZNOTE = o.Z_PK"
        } else if objectColumns.contains("ZNOTEDATA") {
            joinSQL = "LEFT JOIN ZICNOTEDATA nd ON nd.Z_PK = o.ZNOTEDATA"
        } else {
            joinSQL = nil
        }
        guard let joinSQL else {
            return nil
        }

        let textColumn = firstExisting(["ZPLAINTEXT", "ZSNIPPET", "ZSUMMARY"], in: columns)
        let blobColumn = firstExisting(["ZDATA", "ZHTMLDATA"], in: columns)
        return NoteDataJoin(
            joinSQL: joinSQL,
            textExpression: textColumn.map { "nd.\($0)" },
            blobExpression: blobColumn.map { "nd.\($0)" }
        )
    }

    private func textFromNoteBlob(_ data: Data?) -> String? {
        guard let data else { return nil }
        for candidate in [data, decompressed(data, algorithm: COMPRESSION_ZLIB), decompressed(data, algorithm: COMPRESSION_LZFSE)].compactMap({ $0 }) {
            if let text = String(data: candidate, encoding: .utf8), !text.isEmpty {
                return text
            }
            if let text = String(data: candidate, encoding: .utf16LittleEndian), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func decompressed(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return nil }
        let destinationCapacity = max(data.count * 20, 64 * 1024)
        return data.withUnsafeBytes { sourcePointer in
            guard let sourceBase = sourcePointer.baseAddress else { return nil }
            var destination = Data(count: destinationCapacity)
            let decodedCount = destination.withUnsafeMutableBytes { destinationPointer in
                guard let destinationBase = destinationPointer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase.assumingMemoryBound(to: UInt8.self),
                    destinationCapacity,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    algorithm
                )
            }
            guard decodedCount > 0 else { return nil }
            destination.count = decodedCount
            return destination
        }
    }

    private func trimSnippet(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\u{0}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 240 {
            return normalized
        }
        return String(normalized.prefix(240))
    }
}

private struct NoteDataJoin {
    let joinSQL: String
    let textExpression: String?
    let blobExpression: String?
}
