import Foundation

struct MailSQLiteProvider: SearchProvider, ItemProvider {
    let source: SearchSource = .mail
    let envelopeDBPath: String?
    private static let envelopeIndexPaths = MailEnvelopeIndexPaths()
    private static let pathIndex = MailEmlxPathIndex()

    init(envelopeDBPath: String? = nil) {
        self.envelopeDBPath = envelopeDBPath
    }

    static func warmPathIndexInBackground() {
        envelopeIndexPaths.warmInBackground()
        pathIndex.warmInBackground()
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }

        if envelopeDBPath == nil {
            let coreSpotlightResults = CoreSpotlightAppEntityProvider.search(
                source: .mail,
                context: context,
                entityType: "email",
                contentTypes: ["public.email-message", "com.apple.mail.emlx", "com.apple.mail.email"],
                bundleIdentifiers: ["com.apple.mail"],
                allowMail: true
            )
            if !coreSpotlightResults.isEmpty {
                return coreSpotlightResults
            }
        }

        let paths = envelopeDBPath.map { [$0] } ?? findEnvelopeIndexes()
        guard !paths.isEmpty else {
            let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
            if ProtectedStore.isUnreadableExistingPath(mailURL) {
                throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Mail", path: mailURL.path))
            }
            throw ProviderError.unavailable("Mail envelope index is not available")
        }

        var authorizationDeniedPath: String?
        var lastError: Error?
        for path in paths {
            do {
                let db = try SQLiteDatabase(path: path)
                guard try tableExists("messages", in: db) else {
                    continue
                }
                return try searchMessages(context, db: db)
            } catch {
                lastError = error
                if ProtectedStore.isSQLiteAuthorizationDenied(error) {
                    authorizationDeniedPath = path
                }
            }
        }

        if let authorizationDeniedPath {
            throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Mail", path: authorizationDeniedPath))
        }
        throw ProviderError.unavailable(lastError?.localizedDescription ?? "Mail messages table is not available")
    }

    func item(id: String) throws -> ItemRecord {
        let rowID = try rowID(from: id)
        let paths = envelopeDBPath.map { [$0] } ?? findEnvelopeIndexes()
        guard !paths.isEmpty else {
            throw ProviderError.unavailable("Mail envelope index is not available")
        }

        var lastError: Error?
        for path in paths {
            do {
                let db = try SQLiteDatabase(path: path)
                guard try tableExists("messages", in: db) else {
                    continue
                }
                if let item = try mailItem(rowID: rowID, db: db) {
                    return item
                }
            } catch {
                lastError = error
            }
        }

        throw ProviderError.unavailable(lastError?.localizedDescription ?? "Mail item is not available")
    }

    private func searchMessages(_ context: ProviderSearchContext, db: SQLiteDatabase) throws -> [SearchResultRecord] {
        let messageColumns = try columnNames(table: "messages", in: db)
        let subjectTableColumns = try tableExists("subjects", in: db) ? columnNames(table: "subjects", in: db) : []
        let addressTableColumns = try tableExists("addresses", in: db) ? columnNames(table: "addresses", in: db) : []
        let mailboxTableColumns = try tableExists("mailboxes", in: db) ? columnNames(table: "mailboxes", in: db) : []
        let subjectJoin = messageColumns.contains("subject")
            && subjectTableColumns.contains("subject")
        let senderJoin = messageColumns.contains("sender")
            && (!addressTableColumns.isEmpty)
            && (addressTableColumns.contains("address") || addressTableColumns.contains("comment"))
        let mailboxJoin = messageColumns.contains("mailbox")
            && (!mailboxTableColumns.isEmpty)

        let subjectExpr = subjectExpression(messageColumns: messageColumns, hasSubjectJoin: subjectJoin)
        let senderExpr = senderExpression(messageColumns: messageColumns, addressColumns: addressTableColumns, hasSenderJoin: senderJoin)
        let recipientsExpr = optionalColumnExpression(firstExisting(["recipients", "to", "cc"], in: messageColumns), tableAlias: "m")
        let snippetExpr = optionalColumnExpression(firstExisting(["snippet", "summary"], in: messageColumns), tableAlias: "m")
        let dateExpr = optionalColumnExpression(firstExisting(["date_sent", "date_received", "date_last_viewed"], in: messageColumns), tableAlias: "m")
        let messageIDExpr = optionalColumnExpression(firstExisting(["message_id", "global_message_id", "rfc822_message_id"], in: messageColumns), tableAlias: "m")
        let pathExpr = optionalColumnExpression(firstExisting(["path", "filename", "url"], in: messageColumns), tableAlias: "m")
        let flagsExpr = optionalColumnExpression(firstExisting(["flags", "read", "flagged"], in: messageColumns), tableAlias: "m")
        let mailboxExpr = mailboxExpression(messageColumns: messageColumns, mailboxColumns: mailboxTableColumns, hasMailboxJoin: mailboxJoin)

        let haystackExpressions = [subjectExpr, senderExpr, recipientsExpr, snippetExpr].compactMap { $0 }
        guard !haystackExpressions.isEmpty else {
            throw ProviderError.unavailable("Mail messages schema is not recognized")
        }
        let haystackSQL = haystackExpressions.map { "coalesce(CAST(\($0) AS TEXT), '')" }.joined(separator: " || ' ' || ")
        let searchPredicate = mailSearchPredicate(haystackSQL: haystackSQL, query: context.query)

        var joins: [String] = []
        if subjectJoin {
            joins.append("LEFT JOIN subjects s ON s.ROWID = m.subject")
        }
        if senderJoin {
            joins.append("LEFT JOIN addresses a ON a.ROWID = m.sender")
        }
        if mailboxJoin {
            joins.append("LEFT JOIN mailboxes mb ON mb.ROWID = m.mailbox")
        }

        let rows = try db.rows(
            """
            SELECT m.rowid AS rowid,
                   \(subjectExpr ?? "NULL") AS subject,
                   \(senderExpr ?? "NULL") AS sender,
                   \(recipientsExpr ?? "NULL") AS recipients,
                   \(dateExpr ?? "NULL") AS date_sent,
                   \(snippetExpr ?? "NULL") AS snippet,
                   \(messageIDExpr ?? "NULL") AS message_id,
                   \(pathExpr ?? "NULL") AS message_path,
                   \(flagsExpr ?? "NULL") AS flags,
                   \(mailboxExpr ?? "NULL") AS mailbox
            FROM messages m
            \(joins.joined(separator: "\n"))
            WHERE \(searchPredicate.sql)
            ORDER BY \(dateExpr ?? "m.rowid") DESC
            LIMIT ?
            """,
            bindings: searchPredicate.bindings + [.int(Int64(context.limit))]
        )
        return rows.compactMap(messageRecord)
    }

    private func messageRecord(row: [String: SQLiteValue]) -> SearchResultRecord? {
        guard let rowID = row["rowid"]?.int64 else { return nil }
        let sender = row["sender"]?.textValue
        let messageID = row["message_id"]?.textValue
        return SearchResultRecord(
            id: mailItemID(rowID),
            source: SearchSource.mail.rawValue,
            entityType: "email",
            title: row["subject"]?.textValue ?? "Email",
            subtitle: sender,
            path: row["message_path"]?.textValue,
            url: messageURL(messageID: messageID),
            createdAt: mailDate(row["date_sent"]?.double),
            authors: sender.map { [$0] },
            metadata: [
                "rowid": .number(Double(rowID)),
                "itemID": .string(mailItemID(rowID)),
                "messageID": messageID.map(JSONValue.string) ?? .null,
                "mailbox": jsonValue(row["mailbox"]),
                "flags": jsonValue(row["flags"]),
                "recipients": jsonValue(row["recipients"]),
                "snippet": jsonValue(row["snippet"])
            ]
        )
    }

    private func jsonValue(_ value: SQLiteValue?) -> JSONValue {
        guard let value else {
            return .null
        }

        switch value {
        case .text(let text):
            return .string(text)
        case .int(let number):
            return .number(Double(number))
        case .double(let number):
            return .number(number)
        case .blob(let data):
            return .string(data.base64EncodedString())
        case .null:
            return .null
        }
    }

    private func mailItem(rowID: Int64, db: SQLiteDatabase) throws -> ItemRecord? {
        let messageColumns = try columnNames(table: "messages", in: db)
        let subjectTableColumns = try tableExists("subjects", in: db) ? columnNames(table: "subjects", in: db) : []
        let addressTableColumns = try tableExists("addresses", in: db) ? columnNames(table: "addresses", in: db) : []
        let mailboxTableColumns = try tableExists("mailboxes", in: db) ? columnNames(table: "mailboxes", in: db) : []
        let subjectJoin = messageColumns.contains("subject") && subjectTableColumns.contains("subject")
        let senderJoin = messageColumns.contains("sender")
            && (!addressTableColumns.isEmpty)
            && (addressTableColumns.contains("address") || addressTableColumns.contains("comment"))
        let mailboxJoin = messageColumns.contains("mailbox") && !mailboxTableColumns.isEmpty

        let subjectExpr = subjectExpression(messageColumns: messageColumns, hasSubjectJoin: subjectJoin)
        let senderExpr = senderExpression(messageColumns: messageColumns, addressColumns: addressTableColumns, hasSenderJoin: senderJoin)
        let recipientsExpr = optionalColumnExpression(firstExisting(["recipients", "to", "cc"], in: messageColumns), tableAlias: "m")
        let snippetExpr = optionalColumnExpression(firstExisting(["snippet", "summary"], in: messageColumns), tableAlias: "m")
        let dateExpr = optionalColumnExpression(firstExisting(["date_sent", "date_received", "date_last_viewed"], in: messageColumns), tableAlias: "m")
        let messageIDExpr = optionalColumnExpression(firstExisting(["message_id", "global_message_id", "rfc822_message_id"], in: messageColumns), tableAlias: "m")
        let pathExpr = optionalColumnExpression(firstExisting(["path", "filename", "url"], in: messageColumns), tableAlias: "m")
        let flagsExpr = optionalColumnExpression(firstExisting(["flags", "read", "flagged"], in: messageColumns), tableAlias: "m")
        let mailboxExpr = mailboxExpression(messageColumns: messageColumns, mailboxColumns: mailboxTableColumns, hasMailboxJoin: mailboxJoin)

        var joins: [String] = []
        if subjectJoin {
            joins.append("LEFT JOIN subjects s ON s.ROWID = m.subject")
        }
        if senderJoin {
            joins.append("LEFT JOIN addresses a ON a.ROWID = m.sender")
        }
        if mailboxJoin {
            joins.append("LEFT JOIN mailboxes mb ON mb.ROWID = m.mailbox")
        }

        let rows = try db.rows(
            """
            SELECT m.rowid AS rowid,
                   \(subjectExpr ?? "NULL") AS subject,
                   \(senderExpr ?? "NULL") AS sender,
                   \(recipientsExpr ?? "NULL") AS recipients,
                   \(dateExpr ?? "NULL") AS date_sent,
                   \(snippetExpr ?? "NULL") AS snippet,
                   \(messageIDExpr ?? "NULL") AS message_id,
                   \(pathExpr ?? "NULL") AS message_path,
                   \(flagsExpr ?? "NULL") AS flags,
                   \(mailboxExpr ?? "NULL") AS mailbox
            FROM messages m
            \(joins.joined(separator: "\n"))
            WHERE m.rowid = ?
            LIMIT 1
            """,
            bindings: [.int(rowID)]
        )
        guard let row = rows.first else {
            return nil
        }

        let sender = row["sender"]?.textValue
        let messageID = row["message_id"]?.textValue
        let messagePath = row["message_path"]?.textValue
        let bodyText = mailBodyText(path: messagePath, messageID: messageID, rowID: rowID)
        let bodyExcerpt = bodyText.map { clipped($0, maxLength: 1_200) }
        var metadata: [String: JSONValue] = [
            "rowid": .number(Double(rowID)),
            "itemID": .string(mailItemID(rowID)),
            "messageID": messageID.map(JSONValue.string) ?? .null,
            "mailbox": jsonValue(row["mailbox"]),
            "flags": jsonValue(row["flags"]),
            "recipients": jsonValue(row["recipients"]),
            "snippet": jsonValue(row["snippet"]),
            "bodyExcerpt": bodyExcerpt.map(JSONValue.string) ?? .null
        ]
        if let bodyText {
            metadata["bodyText"] = .string(clipped(bodyText, maxLength: 8_000))
        }

        return ItemRecord(
            id: mailItemID(rowID),
            source: SearchSource.mail.rawValue,
            entityType: "email",
            title: row["subject"]?.textValue ?? "Email",
            subtitle: sender,
            path: messagePath,
            url: messageURL(messageID: messageID),
            createdAt: mailDate(row["date_sent"]?.double),
            authors: sender.map { [$0] },
            metadata: metadata
        )
    }

    private func subjectExpression(messageColumns: Set<String>, hasSubjectJoin: Bool) -> String? {
        if hasSubjectJoin {
            return "coalesce(s.subject, m.subject)"
        }
        return optionalColumnExpression(firstExisting(["subject", "subject_prefix"], in: messageColumns), tableAlias: "m")
    }

    private func senderExpression(messageColumns: Set<String>, addressColumns: Set<String>, hasSenderJoin: Bool) -> String? {
        if hasSenderJoin {
            let addressPieces = ["address", "comment"]
                .filter { addressColumns.contains($0) }
                .map { "a.\($0)" }
            return "coalesce(\((addressPieces + ["m.sender"]).joined(separator: ", ")))"
        }
        return optionalColumnExpression(firstExisting(["sender", "from"], in: messageColumns), tableAlias: "m")
    }

    private func mailboxExpression(messageColumns: Set<String>, mailboxColumns: Set<String>, hasMailboxJoin: Bool) -> String? {
        if hasMailboxJoin {
            let mailboxPieces = ["name", "displayName", "url"]
                .filter { mailboxColumns.contains($0) }
                .map { "mb.\($0)" }
            if !mailboxPieces.isEmpty {
                return "coalesce(\((mailboxPieces + ["m.mailbox"]).joined(separator: ", ")))"
            }
        }
        return optionalColumnExpression(firstExisting(["mailbox", "mailbox_name", "account"], in: messageColumns), tableAlias: "m")
    }

    private func messageURL(messageID: String?) -> String? {
        guard let messageID, !messageID.isEmpty else {
            return nil
        }
        let wrapped = messageID.hasPrefix("<") ? messageID : "<\(messageID)>"
        let encoded = wrapped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wrapped
        return "message://\(encoded)"
    }

    private func mailItemID(_ rowID: Int64) -> String {
        "mail:\(rowID)"
    }

    private func rowID(from id: String) throws -> Int64 {
        let raw = id.hasPrefix("mail:") ? String(id.dropFirst("mail:".count)) : id
        guard let rowID = Int64(raw) else {
            throw SpotlightSearchError.invalidItemID(id)
        }
        return rowID
    }

    private func mailDate(_ value: Double?) -> Date? {
        guard let value else {
            return nil
        }
        let referenceDate = SearchUtilities.macAbsoluteDate(value)
        if let referenceDate, referenceDate > Date().addingTimeInterval(366 * 24 * 60 * 60) {
            return Date(timeIntervalSince1970: value)
        }
        return referenceDate
    }

    private func mailBodyText(path: String?, messageID: String?, rowID: Int64) -> String? {
        for url in messageFileCandidates(path: path, messageID: messageID, rowID: rowID) {
            if let text = parseEmlx(url) {
                return text
            }
        }
        return nil
    }

    private func messageFileCandidates(path: String?, messageID: String?, rowID: Int64) -> [URL] {
        var candidates: [URL] = []
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            candidates.append(url)
            if !path.hasPrefix("/") {
                candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail").appendingPathComponent(path))
            }
        }

        let names = [messageID, String(rowID)]
            .compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) }
            .filter { !$0.isEmpty }
            .flatMap { value in value.hasSuffix(".emlx") ? [value] : ["\(value).emlx"] }
        guard !names.isEmpty else {
            return deduped(candidates)
        }

        candidates.append(contentsOf: Self.pathIndex.urls(named: names))
        if !candidates.isEmpty {
            return deduped(candidates)
        }

        candidates.append(contentsOf: spotlightMessageFileCandidates(names: names))
        if !candidates.isEmpty {
            Self.pathIndex.record(candidates)
            return deduped(candidates)
        }

        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        guard let enumerator = FileManager.default.enumerator(at: mailURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return deduped(candidates)
        }

        let wanted = Set(names)
        for case let url as URL in enumerator where wanted.contains(url.lastPathComponent) {
            candidates.append(url)
        }
        Self.pathIndex.record(candidates)
        return deduped(candidates)
    }

    private func spotlightMessageFileCandidates(names: [String]) -> [URL] {
        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        var candidates: [URL] = []
        for name in names {
            let query = "kMDItemFSName == \"\(name.replacingOccurrences(of: "\"", with: "\\\""))\""
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-onlyin", mailURL.path, query]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                continue
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            candidates.append(contentsOf: output
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            )
        }
        return candidates
    }

    private func deduped(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.path).inserted }
    }

    private func parseEmlx(_ url: URL) -> String? {
        guard FileManager.default.isReadableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: 256_000)) ?? Data()
        guard !data.isEmpty else {
            return nil
        }
        var raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard raw?.isEmpty == false else {
            return nil
        }
        if let firstLineEnd = raw?.firstIndex(of: "\n"),
           raw?[..<firstLineEnd].trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy(\.isNumber) == true {
            raw = String(raw![raw!.index(after: firstLineEnd)...])
        }
        let normalized = raw?.replacingOccurrences(of: "\r\n", with: "\n") ?? ""
        let body = normalized.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        let decoded = decodeQuotedPrintable(body.isEmpty ? normalized : body)
        return clipped(stripMarkup(decoded), maxLength: 20_000)
    }

    private func decodeQuotedPrintable(_ text: String) -> String {
        var bytes: [UInt8] = []
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "=" {
                if index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 2
                    continue
                }
                if index + 2 < scalars.count,
                   let high = hexValue(scalars[index + 1]),
                   let low = hexValue(scalars[index + 2]) {
                    bytes.append(UInt8(high * 16 + low))
                    index += 3
                    continue
                }
            }
            bytes.append(contentsOf: String(scalar).utf8)
            index += 1
        }
        return String(data: Data(bytes), encoding: .utf8) ?? text
    }

    private func hexValue(_ scalar: UnicodeScalar) -> Int? {
        Int(String(scalar), radix: 16)
    }

    private func stripMarkup(_ text: String) -> String {
        let invisibleCharacters = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2060}\u{FEFF}")
        return text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("--")
                    && !trimmed.localizedCaseInsensitiveContains("Content-Transfer-Encoding:")
                    && !trimmed.localizedCaseInsensitiveContains("Content-Type:")
                    && !trimmed.localizedCaseInsensitiveContains("Mime-Version:")
            }
            .joined(separator: " ")
            .components(separatedBy: invisibleCharacters)
            .joined()
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clipped(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    private func optionalColumnExpression(_ column: String?, tableAlias: String) -> String? {
        column.map { "\(tableAlias).\($0)" }
    }

    private func findEnvelopeIndexes() -> [String] {
        Self.envelopeIndexPaths.paths()
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

    private func mailSearchPredicate(haystackSQL: String, query: String) -> (sql: String, bindings: [SQLiteBinding]) {
        let loweredHaystack = "lower(\(haystackSQL))"
        let compactHaystack = compactSQL(loweredHaystack)
        var clauses = [
            "\(loweredHaystack) LIKE lower(?)",
            "\(compactHaystack) LIKE lower(?)"
        ]
        var bindings: [SQLiteBinding] = [
            .text("%\(query)%"),
            .text("%\(compactSearchToken(query))%")
        ]

        let tokens = searchTokens(query)
        if tokens.count > 1 {
            let tokenClauses = tokens.map { _ in
                "(\(loweredHaystack) LIKE lower(?) OR \(compactHaystack) LIKE lower(?))"
            }
            clauses.append("(\(tokenClauses.joined(separator: " AND ")))")
            for token in tokens {
                bindings.append(.text("%\(token)%"))
                bindings.append(.text("%\(compactSearchToken(token))%"))
            }
        }

        return ("(\(clauses.joined(separator: " OR ")))", bindings)
    }

    private func searchTokens(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func compactSearchToken(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func compactSQL(_ expression: String) -> String {
        [" ", ".", "-", "_", "@", "+", ":", "/", "\\"].reduce(expression) { partial, character in
            "replace(\(partial), '\(character)', '')"
        }
    }
}

private final class MailEnvelopeIndexPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedPaths: [String]?
    private var isWarming = false

    func warmInBackground() {
        lock.lock()
        guard cachedPaths == nil, !isWarming else {
            lock.unlock()
            return
        }
        isWarming = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let paths = Self.discover()
            self?.lock.lock()
            self?.cachedPaths = paths
            self?.isWarming = false
            self?.lock.unlock()
        }
    }

    func paths() -> [String] {
        lock.lock()
        if let cachedPaths {
            lock.unlock()
            return cachedPaths
        }
        if !isWarming {
            isWarming = true
        }
        lock.unlock()

        let discovered = Self.discover()

        lock.lock()
        cachedPaths = discovered
        isWarming = false
        lock.unlock()
        return discovered
    }

    private static func discover() -> [String] {
        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        guard let enumerator = FileManager.default.enumerator(at: mailURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("Envelope Index") {
            paths.append(url.path)
        }
        return paths.sorted()
    }
}

private final class MailEmlxPathIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var pathsByFilename: [String: [URL]] = [:]
    private var isWarmed = false
    private var isWarming = false

    func warmInBackground() {
        lock.lock()
        guard !isWarmed, !isWarming else {
            lock.unlock()
            return
        }
        isWarming = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.rebuild()
        }
    }

    func urls(named names: [String]) -> [URL] {
        lock.lock()
        let urls = names.flatMap { pathsByFilename[$0] ?? [] }
        lock.unlock()
        return urls
    }

    func record(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        lock.lock()
        for url in urls where url.pathExtension == "emlx" {
            pathsByFilename[url.lastPathComponent, default: []].append(url)
        }
        for (key, value) in pathsByFilename {
            var seen: Set<String> = []
            pathsByFilename[key] = value.filter { seen.insert($0.path).inserted }
        }
        lock.unlock()
    }

    private func rebuild() {
        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        var output: [String: [URL]] = [:]
        if let enumerator = FileManager.default.enumerator(at: mailURL, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator where url.pathExtension == "emlx" {
                output[url.lastPathComponent, default: []].append(url)
            }
        }

        lock.lock()
        pathsByFilename = output
        isWarmed = true
        isWarming = false
        lock.unlock()
    }
}
