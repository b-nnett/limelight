import Compression
import Foundation
import zlib

struct NotesSQLiteProvider: ItemProvider {
    let source: SearchSource = .notes
    let notesDBPath: String?

    init(notesDBPath: String? = nil) {
        self.notesDBPath = notesDBPath
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }

        do {
            return try searchPrivateStore(context)
        } catch {
            guard notesDBPath == nil else {
                throw error
            }

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
            throw error
        }
    }

    func item(id: String) throws -> ItemRecord {
        try withReadableNotesDatabase { db, shape in
            switch shape {
            case .fixture:
                return try ItemRecord(result: loadFixtureShape(id: id, db: db))
            case .appleNotes:
                return try ItemRecord(result: loadAppleNotesShape(id: id, db: db))
            }
        }
    }

    private func searchPrivateStore(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        try withReadableNotesDatabase { db, shape in
            switch shape {
            case .fixture:
                return try searchFixtureShape(context, db: db)
            case .appleNotes:
                return try searchAppleNotesShape(context, db: db)
            }
        }
    }

    private func withReadableNotesDatabase<T>(_ operation: (SQLiteDatabase, NotesDatabaseShape) throws -> T) throws -> T {
        let paths = notesDBPath.map { [$0] } ?? notesStoreCandidates().map(\.path)
        var authorizationDeniedPath: String?
        var lastError: Error?

        for path in paths {
            do {
                let db = try SQLiteDatabase(path: path)
                if try tableExists("notes", in: db) {
                    return try operation(db, .fixture)
                }
                if try tableExists("ZICCLOUDSYNCINGOBJECT", in: db) {
                    return try operation(db, .appleNotes)
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
        let columns = try columnNames(table: "notes", in: db)
        guard columns.contains("id") else {
            throw ProviderError.unavailable("Notes fixture schema is missing id")
        }
        let titleColumn = firstExisting(["title", "name"], in: columns)
        let bodyColumn = firstExisting(["body", "text", "content"], in: columns)
        let modifiedColumn = firstExisting(["modified_at", "modified", "updated_at"], in: columns)
        let identifierColumn = firstExisting(["identifier", "uuid", "note_identifier"], in: columns)
        guard titleColumn != nil || bodyColumn != nil else {
            throw ProviderError.unavailable("Notes fixture schema is not recognized")
        }

        let haystackExpressions = [titleColumn, bodyColumn].compactMap { $0 }
        let haystack = haystackExpressions.map { "coalesce(CAST(\($0) AS TEXT), '')" }.joined(separator: " || ' ' || ")
        let titleExpression = titleColumn ?? "'Note'"
        let rows = try db.rows(
            """
            SELECT id,
                   \(titleExpression) AS title,
                   \(bodyColumn ?? "NULL") AS body,
                   \(modifiedColumn ?? "NULL") AS modified_at,
                   \(identifierColumn ?? "NULL") AS identifier
            FROM notes
            WHERE lower(\(haystack)) LIKE lower(?)
            ORDER BY CASE WHEN lower(coalesce(CAST(\(titleExpression) AS TEXT), '')) LIKE lower(?) THEN 0 ELSE 1 END,
                     \(modifiedColumn ?? "id") DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .text("%\(context.query)%"), .int(Int64(context.limit))]
        )

        return rows.compactMap { row in
            guard let id = row["id"]?.textValue else { return nil }
            let body = cleanNoteText(row["body"]?.textValue)
            return noteRecord(
                id: id,
                title: row["title"]?.textValue ?? "Note",
                body: body,
                modifiedAt: row["modified_at"]?.double,
                query: context.query,
                identifier: row["identifier"]?.textValue
            )
        }
    }

    private func loadFixtureShape(id requestedID: String, db: SQLiteDatabase) throws -> SearchResultRecord {
        let columns = try columnNames(table: "notes", in: db)
        guard let noteID = try resolveFixtureNoteID(requestedID, columns: columns, db: db) else {
            throw ProviderError.unavailable("Notes item was not found: \(requestedID)")
        }
        let titleColumn = firstExisting(["title", "name"], in: columns)
        let bodyColumn = firstExisting(["body", "text", "content"], in: columns)
        let modifiedColumn = firstExisting(["modified_at", "modified", "updated_at"], in: columns)
        let identifierColumn = firstExisting(["identifier", "uuid", "note_identifier"], in: columns)
        let rows = try db.rows(
            """
            SELECT id,
                   \(titleColumn ?? "'Note'") AS title,
                   \(bodyColumn ?? "NULL") AS body,
                   \(modifiedColumn ?? "NULL") AS modified_at,
                   \(identifierColumn ?? "NULL") AS identifier
            FROM notes
            WHERE CAST(id AS TEXT) = ?
            LIMIT 1
            """,
            bindings: [.text(noteID)]
        )
        guard let row = rows.first else {
            throw ProviderError.unavailable("Notes item was not found: \(requestedID)")
        }
        return noteRecord(
            id: noteID,
            title: row["title"]?.textValue ?? "Note",
            body: cleanNoteText(row["body"]?.textValue),
            modifiedAt: row["modified_at"]?.double,
            query: nil,
            identifier: row["identifier"]?.textValue,
            includeBody: true
        )
    }

    private func searchAppleNotesShape(_ context: ProviderSearchContext, db: SQLiteDatabase) throws -> [SearchResultRecord] {
        let columns = try columnNames(table: "ZICCLOUDSYNCINGOBJECT", in: db)
        let titleColumn = firstExisting(["ZTITLE1", "ZTITLE", "ZNAME"], in: columns)
        let bodyColumn = firstExisting(["ZSNIPPET", "ZPLAINTEXT", "ZSUMMARY"], in: columns)
        let modifiedColumn = firstExisting(["ZMODIFICATIONDATE1", "ZMODIFICATIONDATE", "ZLASTEDITEDDATE"], in: columns)
        let identifierColumn = firstExisting(["ZIDENTIFIER", "ZUNIQUEIDENTIFIER", "ZUUID"], in: columns)
        let noteDataJoin = try noteDataJoin(objectColumns: columns, db: db)
        guard let titleColumn else {
            throw ProviderError.unavailable("Notes title column is not recognized")
        }

        let bodyExpression = bodyExpression(objectExpression: bodyColumn.map { "o.\($0)" }, noteDataExpression: noteDataJoin?.textExpression)
        let shouldScanBlob = noteDataJoin?.blobExpression != nil
        let haystackExpressions = ["o.\(titleColumn)", bodyExpression].compactMap { $0 }
        let haystack = haystackExpressions.map { "coalesce(CAST(\($0) AS TEXT), '')" }.joined(separator: " || ' ' || ")
        let scanLimit = min(max(context.limit * 500, 5000), 20_000)
        let matchingRows = try db.rows(
            """
            SELECT o.Z_PK,
                   o.\(titleColumn) AS title,
                   \(bodyExpression ?? "NULL") AS body,
                   \(noteDataJoin?.blobExpression ?? "NULL") AS body_blob,
                   \(modifiedColumn.map { "o.\($0)" } ?? "NULL") AS modified_at,
                   \(identifierColumn.map { "o.\($0)" } ?? "NULL") AS identifier
            FROM ZICCLOUDSYNCINGOBJECT o
            \(noteDataJoin?.joinSQL ?? "")
            WHERE lower(\(haystack)) LIKE lower(?)
            ORDER BY CASE WHEN lower(coalesce(CAST(o.\(titleColumn) AS TEXT), '')) LIKE lower(?) THEN 0 ELSE 1 END,
                     \(modifiedColumn.map { "o.\($0)" } ?? "o.Z_PK") DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .text("%\(context.query)%"), .int(Int64(context.limit))]
        )
        let scannedRows = try shouldScanBlob ? db.rows(
            """
            SELECT o.Z_PK,
                   o.\(titleColumn) AS title,
                   \(bodyExpression ?? "NULL") AS body,
                   \(noteDataJoin?.blobExpression ?? "NULL") AS body_blob,
                   \(modifiedColumn.map { "o.\($0)" } ?? "NULL") AS modified_at,
                   \(identifierColumn.map { "o.\($0)" } ?? "NULL") AS identifier
            FROM ZICCLOUDSYNCINGOBJECT o
            \(noteDataJoin?.joinSQL ?? "")
            ORDER BY CASE WHEN lower(coalesce(CAST(o.\(titleColumn) AS TEXT), '')) LIKE lower(?) THEN 0 ELSE 1 END,
                     \(modifiedColumn.map { "o.\($0)" } ?? "o.Z_PK") DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .int(Int64(scanLimit))]
        ) : []
        let rows = uniqueRows(matchingRows + scannedRows, key: "Z_PK")

        let records = rows.compactMap { row -> SearchResultRecord? in
            guard let id = row["Z_PK"]?.int64 else { return nil }
            let body = preferredBodyText(row["body"]?.textValue, blob: row["body_blob"]?.data)
            if !SearchUtilities.contains(row["title"]?.textValue, context.query),
               !SearchUtilities.contains(body, context.query) {
                return nil
            }
            return noteRecord(
                id: String(id),
                title: row["title"]?.textValue ?? "Note",
                body: body,
                modifiedAt: row["modified_at"]?.double,
                query: context.query,
                identifier: row["identifier"]?.textValue
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

    private func uniqueRows(_ rows: [[String: SQLiteValue]], key: String) -> [[String: SQLiteValue]] {
        var seen: Set<String> = []
        return rows.filter { row in
            guard let value = row[key]?.textValue else {
                return true
            }
            return seen.insert(value).inserted
        }
    }

    private func loadAppleNotesShape(id requestedID: String, db: SQLiteDatabase) throws -> SearchResultRecord {
        let columns = try columnNames(table: "ZICCLOUDSYNCINGOBJECT", in: db)
        guard let primaryKey = try resolveAppleNotePrimaryKey(requestedID, columns: columns, db: db) else {
            throw ProviderError.unavailable("Notes item was not found: \(requestedID)")
        }
        let titleColumn = firstExisting(["ZTITLE1", "ZTITLE", "ZNAME"], in: columns)
        let bodyColumn = firstExisting(["ZSNIPPET", "ZPLAINTEXT", "ZSUMMARY"], in: columns)
        let modifiedColumn = firstExisting(["ZMODIFICATIONDATE1", "ZMODIFICATIONDATE", "ZLASTEDITEDDATE"], in: columns)
        let identifierColumn = firstExisting(["ZIDENTIFIER", "ZUNIQUEIDENTIFIER", "ZUUID"], in: columns)
        let noteDataJoin = try noteDataJoin(objectColumns: columns, db: db)
        guard let titleColumn else {
            throw ProviderError.unavailable("Notes title column is not recognized")
        }

        let bodyExpression = bodyExpression(objectExpression: bodyColumn.map { "o.\($0)" }, noteDataExpression: noteDataJoin?.textExpression)
        let rows = try db.rows(
            """
            SELECT o.Z_PK,
                   o.\(titleColumn) AS title,
                   \(bodyExpression ?? "NULL") AS body,
                   \(noteDataJoin?.blobExpression ?? "NULL") AS body_blob,
                   \(modifiedColumn.map { "o.\($0)" } ?? "NULL") AS modified_at,
                   \(identifierColumn.map { "o.\($0)" } ?? "NULL") AS identifier
            FROM ZICCLOUDSYNCINGOBJECT o
            \(noteDataJoin?.joinSQL ?? "")
            WHERE o.Z_PK = ?
            LIMIT 1
            """,
            bindings: [.int(primaryKey)]
        )
        guard let row = rows.first else {
            throw ProviderError.unavailable("Notes item was not found: \(requestedID)")
        }

        return noteRecord(
            id: String(primaryKey),
            title: row["title"]?.textValue ?? "Note",
            body: preferredBodyText(row["body"]?.textValue, blob: row["body_blob"]?.data),
            modifiedAt: row["modified_at"]?.double,
            query: nil,
            identifier: row["identifier"]?.textValue,
            includeBody: true
        )
    }

    private func noteRecord(
        id: String,
        title: String,
        body: String?,
        modifiedAt: Double?,
        query: String?,
        identifier: String?,
        includeBody: Bool = false
    ) -> SearchResultRecord {
        let openURL = noteURL(identifier: identifier)
        var metadata: [String: JSONValue] = [
            "noteID": .string(id)
        ]
        if let query {
            metadata["matchReason"] = .string(SearchUtilities.contains(title, query) ? "title" : "body")
        }
        if let identifier = normalizedIdentifier(identifier) {
            metadata["notesIdentifier"] = .string(identifier)
        }
        if let openURL {
            metadata["openURL"] = .string(openURL)
        }
        if includeBody {
            metadata["body"] = body.map(JSONValue.string) ?? .null
            metadata["bodyLength"] = .number(Double(body?.count ?? 0))
        }

        return SearchResultRecord(
            id: SearchUtilities.stableID([SearchSource.notes.rawValue, id]),
            source: SearchSource.notes.rawValue,
            entityType: "note",
            title: title,
            subtitle: body.map(trimSnippet),
            url: openURL,
            modifiedAt: SearchUtilities.macAbsoluteDate(modifiedAt),
            metadata: metadata
        )
    }

    private func bodyExpression(objectExpression: String?, noteDataExpression: String?) -> String? {
        switch (noteDataExpression, objectExpression) {
        case (.some(let noteDataExpression), .some(let objectExpression)):
            return "coalesce(\(noteDataExpression), \(objectExpression))"
        case (.some(let noteDataExpression), .none):
            return noteDataExpression
        case (.none, .some(let objectExpression)):
            return objectExpression
        case (.none, .none):
            return nil
        }
    }

    private func resolveFixtureNoteID(_ requestedID: String, columns: Set<String>, db: SQLiteDatabase) throws -> String? {
        let candidates = noteIDCandidates(from: requestedID)
        for candidate in candidates {
            if let row = try db.rows("SELECT id FROM notes WHERE CAST(id AS TEXT) = ? LIMIT 1", bindings: [.text(candidate)]).first {
                return row["id"]?.textValue
            }
        }

        if let identifierColumn = firstExisting(["identifier", "uuid", "note_identifier"], in: columns) {
            for candidate in candidates {
                if let row = try db.rows("SELECT id FROM notes WHERE \(identifierColumn) = ? LIMIT 1", bindings: [.text(candidate)]).first {
                    return row["id"]?.textValue
                }
            }
        }

        let rows = try db.rows("SELECT id FROM notes")
        return rows.compactMap { $0["id"]?.textValue }.first { stableNoteID($0) == requestedID }
    }

    private func resolveAppleNotePrimaryKey(_ requestedID: String, columns: Set<String>, db: SQLiteDatabase) throws -> Int64? {
        let candidates = noteIDCandidates(from: requestedID)
        for candidate in candidates {
            if let id = Int64(candidate),
               let row = try db.rows("SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ? LIMIT 1", bindings: [.int(id)]).first {
                return row["Z_PK"]?.int64
            }
        }

        if let identifierColumn = firstExisting(["ZIDENTIFIER", "ZUNIQUEIDENTIFIER", "ZUUID"], in: columns) {
            for candidate in candidates {
                if let row = try db.rows("SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE \(identifierColumn) = ? LIMIT 1", bindings: [.text(candidate)]).first {
                    return row["Z_PK"]?.int64
                }
            }
        }

        let rows = try db.rows("SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT")
        return rows.compactMap { $0["Z_PK"]?.int64 }.first { stableNoteID(String($0)) == requestedID }
    }

    private func noteIDCandidates(from requestedID: String) -> [String] {
        var candidates = [requestedID]
        if let identifier = noteIdentifier(from: requestedID), !candidates.contains(identifier) {
            candidates.append(identifier)
        }
        return candidates
    }

    private func stableNoteID(_ id: String) -> String {
        SearchUtilities.stableID([SearchSource.notes.rawValue, id])
    }

    private func noteIdentifier(from value: String) -> String? {
        guard let components = URLComponents(string: value) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "identifier" })?.value
    }

    private func noteURL(identifier: String?) -> String? {
        guard let identifier = normalizedIdentifier(identifier) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "notes"
        components.host = "showNote"
        components.queryItems = [URLQueryItem(name: "identifier", value: identifier)]
        return components.url?.absoluteString
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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

    private func preferredBodyText(_ text: String?, blob: Data?) -> String? {
        let cleanedText = cleanNoteText(text)
        guard let blobText = textFromNoteBlob(blob) else {
            return cleanedText
        }
        guard let cleanedText, !cleanedText.isEmpty else {
            return blobText
        }
        return blobText.count > cleanedText.count ? blobText : cleanedText
    }

    private func textFromNoteBlob(_ data: Data?) -> String? {
        guard let data else { return nil }
        let decodedCandidates = [
            gunzipped(data),
            decompressed(data, algorithm: COMPRESSION_ZLIB),
            decompressed(data, algorithm: COMPRESSION_LZFSE),
            decompressed(data, algorithm: COMPRESSION_LZ4),
            decompressed(data, algorithm: COMPRESSION_LZMA),
            data
        ].compactMap { $0 }

        for candidate in decodedCandidates {
            if let text = protobufText(from: candidate) {
                return text
            }
        }

        for candidate in decodedCandidates {
            for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
                if let text = decodedReadableText(candidate, encoding: encoding) {
                    return text
                }
            }
        }

        for candidate in decodedCandidates {
            if let text = printableText(from: candidate) {
                return text
            }
        }
        return nil
    }

    private func gunzipped(_ data: Data) -> Data? {
        guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else {
            return nil
        }

        var stream = z_stream()
        guard inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer {
            inflateEnd(&stream)
        }

        return data.withUnsafeBytes { sourcePointer -> Data? in
            guard let sourceBase = sourcePointer.bindMemory(to: Bytef.self).baseAddress else {
                return nil
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: sourceBase)
            stream.avail_in = uInt(data.count)

            var output = Data()
            let chunkSize = 64 * 1024
            var chunk = [UInt8](repeating: 0, count: chunkSize)

            while true {
                let status = chunk.withUnsafeMutableBufferPointer { chunkPointer -> Int32 in
                    stream.next_out = chunkPointer.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: chunk.prefix(produced))
                }

                if status == Z_STREAM_END {
                    return output
                }
                guard status == Z_OK else {
                    return nil
                }
                guard output.count <= 32 * 1024 * 1024 else {
                    return nil
                }
                if produced == 0, stream.avail_in == 0 {
                    return nil
                }
            }
        }
    }

    private func protobufText(from data: Data) -> String? {
        var strings: [String] = []
        collectProtobufStrings(data, depth: 0, strings: &strings)

        var seen: Set<String> = []
        let meaningful = strings.compactMap(cleanNoteText)
            .filter(isMeaningfulNoteText)
            .filter { seen.insert($0).inserted }

        guard !meaningful.isEmpty else {
            return nil
        }
        return cleanNoteText(meaningful.joined(separator: "\n"))
    }

    private func collectProtobufStrings(_ data: Data, depth: Int, strings: inout [String]) {
        guard depth <= 6, data.count >= 2, data.count <= 16 * 1024 * 1024 else {
            return
        }

        var index = 0
        var fields = 0
        while index < data.count, fields < 20_000 {
            guard let tag = readVarint(data, index: &index), tag != 0 else {
                return
            }
            fields += 1

            switch Int(tag & 0x7) {
            case 0:
                guard readVarint(data, index: &index) != nil else {
                    return
                }
            case 1:
                guard skip(8, in: data, index: &index) else {
                    return
                }
            case 2:
                guard let lengthValue = readVarint(data, index: &index),
                      lengthValue <= UInt64(Int.max) else {
                    return
                }
                let length = Int(lengthValue)
                guard length >= 0, index + length <= data.count else {
                    return
                }
                let segment = data[index..<(index + length)]
                if let text = decodedStringField(segment) {
                    strings.append(text)
                }
                if length >= 2, length <= 4 * 1024 * 1024 {
                    collectProtobufStrings(Data(segment), depth: depth + 1, strings: &strings)
                }
                index += length
            case 5:
                guard skip(4, in: data, index: &index) else {
                    return
                }
            default:
                return
            }
        }
    }

    private func readVarint(_ data: Data, index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.count, shift < 64 {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte < 0x80 {
                return result
            }
            shift += 7
        }
        return nil
    }

    private func skip(_ count: Int, in data: Data, index: inout Int) -> Bool {
        guard index + count <= data.count else {
            return false
        }
        index += count
        return true
    }

    private func decodedStringField(_ data: Data.SubSequence) -> String? {
        guard !data.isEmpty,
              let text = String(data: Data(data), encoding: .utf8),
              !hasDisallowedControls(text),
              readableRatio(text) >= 0.92,
              replacementRatio(text) < 0.01,
              let cleaned = cleanNoteText(text),
              isMeaningfulNoteText(cleaned) else {
            return nil
        }
        return cleaned
    }

    private func decompressed(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacities = [
            max(data.count * 20, 64 * 1024),
            max(data.count * 100, 1024 * 1024),
            16 * 1024 * 1024
        ]
        for destinationCapacity in capacities {
            if let decoded = data.withUnsafeBytes({ sourcePointer -> Data? in
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
            }) {
                return decoded
            }
        }
        return nil
    }

    private func decodedReadableText(_ data: Data, encoding: String.Encoding) -> String? {
        guard let text = String(data: data, encoding: encoding) else {
            return nil
        }
        let cleaned = cleanNoteText(text)
        guard let cleaned, readableRatio(text) >= 0.75 else {
            return nil
        }
        return cleaned
    }

    private func printableText(from data: Data) -> String? {
        let decoded = String(decoding: data, as: UTF8.self)
        guard replacementRatio(decoded) < 0.01 else {
            return nil
        }
        let sanitizedScalars = decoded.unicodeScalars.map { scalar -> Unicode.Scalar in
            isReadableScalar(scalar) ? scalar : "\n"
        }
        let sanitized = String(String.UnicodeScalarView(sanitizedScalars))
        let lines = sanitized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isMeaningfulNoteText)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func cleanNoteText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let cleanedScalars = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            if scalar == "\u{0}" {
                return " "
            }
            if isReadableScalar(scalar) {
                return scalar
            }
            return " "
        }
        let cleaned = String(String.UnicodeScalarView(cleanedScalars))
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func readableRatio(_ text: String) -> Double {
        guard !text.unicodeScalars.isEmpty else {
            return 0
        }
        let readable = text.unicodeScalars.filter(isReadableScalar).count
        return Double(readable) / Double(text.unicodeScalars.count)
    }

    private func replacementRatio(_ text: String) -> Double {
        guard !text.unicodeScalars.isEmpty else {
            return 0
        }
        let replacements = text.unicodeScalars.filter { $0.value == 0xfffd }.count
        return Double(replacements) / Double(text.unicodeScalars.count)
    }

    private func hasDisallowedControls(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n"
                && scalar != "\r"
                && scalar != "\t"
        }
    }

    private func isReadableScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\r" || scalar == "\t" {
            return true
        }
        return !CharacterSet.controlCharacters.contains(scalar)
    }

    private func containsAlphaNumeric(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private func isMeaningfulNoteText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, containsAlphaNumeric(trimmed) else {
            return false
        }
        if trimmed.range(of: #"^[A-Fa-f0-9-]{20,}$"#, options: .regularExpression) != nil {
            return false
        }
        return true
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

private enum NotesDatabaseShape {
    case fixture
    case appleNotes
}

private struct NoteDataJoin {
    let joinSQL: String
    let textExpression: String?
    let blobExpression: String?
}
