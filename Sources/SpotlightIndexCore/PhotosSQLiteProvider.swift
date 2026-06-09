import Foundation

struct PhotosSQLiteProvider: SearchProvider {
    let source: SearchSource = .photos
    let libraryURL: URL
    private let assetResolver: PhotosAssetResolver

    init(libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Photos Library.photoslibrary")) {
        self.libraryURL = libraryURL
        self.assetResolver = PhotosAssetResolver(libraryURL: libraryURL)
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty || context.types.contains("image") || context.types.contains("video") else {
            return []
        }
        let photosDBPath = libraryURL.appendingPathComponent("database/Photos.sqlite").path
        let searchDBPath = libraryURL.appendingPathComponent("database/search/leo.sqlite").path
        guard FileManager.default.fileExists(atPath: photosDBPath) else {
            throw ProviderError.unavailable("Photos library database is not available")
        }

        let photosDB = try SQLiteDatabase(path: photosDBPath)
        var results: [SearchResultRecord] = []
        var seen: Set<String> = []

        for record in try personResults(context, photosDB: photosDB) {
            if seen.insert(record.id).inserted {
                results.append(record)
            }
            if results.count == context.limit { return results }
        }

        if FileManager.default.fileExists(atPath: searchDBPath) {
            let searchDB = try SQLiteDatabase(path: searchDBPath)
            for record in try lexemeResults(context, photosDB: photosDB, searchDB: searchDB) {
                if seen.insert(record.id).inserted {
                    results.append(record)
                }
                if results.count == context.limit { return results }
            }
        }

        return results
    }

    private func personResults(_ context: ProviderSearchContext, photosDB: SQLiteDatabase) throws -> [SearchResultRecord] {
        let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let people = try photosDB.rows(
            """
            SELECT Z_PK, ZDISPLAYNAME, ZFULLNAME, ZPERSONUUID
            FROM ZPERSON
            WHERE lower(coalesce(ZDISPLAYNAME, '') || ' ' || coalesce(ZFULLNAME, '')) LIKE lower(?)
            LIMIT 10
            """,
            bindings: [.text("%\(query)%")]
        )

        var records: [SearchResultRecord] = []
        for person in people {
            guard let personPK = person["Z_PK"]?.int64 else { continue }
            let assets = try photosDB.rows(
                """
                SELECT a.ZUUID, a.ZFILENAME, a.ZUNIFORMTYPEIDENTIFIER, a.ZWIDTH, a.ZHEIGHT, a.ZDATECREATED
                FROM ZDETECTEDFACE f
                JOIN ZASSET a ON a.Z_PK = f.ZASSETFORFACE
                WHERE f.ZPERSONFORFACE = ?
                  AND coalesce(f.ZHIDDEN, 0) = 0
                  AND coalesce(f.ZISINTRASH, 0) = 0
                  AND coalesce(a.ZHIDDEN, 0) = 0
                  AND coalesce(a.ZTRASHEDSTATE, 0) = 0
                  AND coalesce(a.ZVISIBILITYSTATE, 0) = 0
                GROUP BY a.Z_PK
                ORDER BY a.ZDATECREATED DESC
                LIMIT ?
                """,
                bindings: [.int(personPK), .int(Int64(context.limit))]
            )

            let personName = person["ZDISPLAYNAME"]?.string ?? person["ZFULLNAME"]?.string ?? query
            records.append(contentsOf: assets.compactMap { assetRecord($0, matchReason: "person", subtitle: personName) })
        }
        return records
    }

    private func lexemeResults(_ context: ProviderSearchContext, photosDB: SQLiteDatabase, searchDB: SQLiteDatabase) throws -> [SearchResultRecord] {
        let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let lexemes = try searchDB.rows(
            """
            SELECT DISTINCT lexeme_id, category, content, identifier
            FROM lexicon
            WHERE lower(content) LIKE lower(?)
            LIMIT 50
            """,
            bindings: [.text("%\(query)%")]
        )
        let lexemeIDs = Set(lexemes.compactMap { $0["lexeme_id"]?.int64 }.map(Int.init))
        guard !lexemeIDs.isEmpty else { return [] }

        let items = try searchDB.rows("SELECT identifier, type, lexeme_ids FROM items WHERE type = 1")
        var assetUUIDs: [(String, String)] = []
        for item in items {
            guard let uuid = item["identifier"]?.string, let blob = item["lexeme_ids"]?.data else { continue }
            let ids = littleEndianUInt32Values(blob)
            if ids.contains(where: { lexemeIDs.contains($0) }) {
                assetUUIDs.append((uuid, "photos-search"))
            }
            if assetUUIDs.count >= context.limit * 3 {
                break
            }
        }

        var records: [SearchResultRecord] = []
        for (uuid, reason) in assetUUIDs {
            let rows = try photosDB.rows(
                """
                SELECT ZUUID, ZFILENAME, ZUNIFORMTYPEIDENTIFIER, ZWIDTH, ZHEIGHT, ZDATECREATED
                FROM ZASSET
                WHERE ZUUID = ?
                  AND coalesce(ZHIDDEN, 0) = 0
                  AND coalesce(ZTRASHEDSTATE, 0) = 0
                  AND coalesce(ZVISIBILITYSTATE, 0) = 0
                LIMIT 1
                """,
                bindings: [.text(uuid)]
            )
            if let row = rows.first, let record = assetRecord(row, matchReason: reason, subtitle: "Photos") {
                records.append(record)
            }
            if records.count == context.limit {
                break
            }
        }
        return records
    }

    private func assetRecord(_ row: [String: SQLiteValue], matchReason: String, subtitle: String) -> SearchResultRecord? {
        guard let uuid = row["ZUUID"]?.string else { return nil }
        let filename = row["ZFILENAME"]?.string ?? uuid
        let contentType = row["ZUNIFORMTYPEIDENTIFIER"]?.string
        let path = assetResolver.bestAssetPath(uuid: uuid, filename: filename)
        let mediaKind = assetResolver.mediaKind(contentType: contentType, filename: filename)
        return SearchResultRecord(
            id: SearchUtilities.stableID([SearchSource.photos.rawValue, uuid]),
            source: SearchSource.photos.rawValue,
            entityType: mediaKind == "video" ? "video" : "photo",
            title: filename,
            subtitle: subtitle,
            path: path,
            contentType: contentType,
            createdAt: SearchUtilities.macAbsoluteDate(row["ZDATECREATED"]?.double),
            metadata: [
                "uuid": .string(uuid),
                "matchReason": .string(matchReason),
                "mediaKind": .string(mediaKind),
                "width": row["ZWIDTH"]?.jsonValue ?? .null,
                "height": row["ZHEIGHT"]?.jsonValue ?? .null
            ]
        )
    }

    private func littleEndianUInt32Values(_ data: Data) -> [Int] {
        var values: [Int] = []
        guard data.count >= 4 else { return values }
        var offset = 0
        while offset + 3 < data.count {
            let b0 = UInt32(data[offset])
            let b1 = UInt32(data[offset + 1]) << 8
            let b2 = UInt32(data[offset + 2]) << 16
            let b3 = UInt32(data[offset + 3]) << 24
            values.append(Int(b0 | b1 | b2 | b3))
            offset += 4
        }
        return values
    }

}

private extension SQLiteValue {
    var jsonValue: JSONValue {
        switch self {
        case .text(let value):
            .string(value)
        case .int(let value):
            .number(Double(value))
        case .double(let value):
            .number(value)
        case .blob:
            .string("<blob>")
        case .null:
            .null
        }
    }
}
