import Foundation

struct MailSQLiteProvider: SearchProvider {
    let source: SearchSource = .mail
    let envelopeDBPath: String?

    init(envelopeDBPath: String? = nil) {
        self.envelopeDBPath = envelopeDBPath
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
            WHERE lower(\(haystackExpressions.map { "coalesce(CAST(\($0) AS TEXT), '')" }.joined(separator: " || ' ' || "))) LIKE lower(?)
            ORDER BY \(dateExpr ?? "m.rowid") DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .int(Int64(context.limit))]
        )
        return rows.compactMap { row in
            guard let rowID = row["rowid"]?.int64 else { return nil }
            let sender = row["sender"]?.textValue
            let messageID = row["message_id"]?.textValue
            return SearchResultRecord(
                id: SearchUtilities.stableID([SearchSource.mail.rawValue, String(rowID)]),
                source: SearchSource.mail.rawValue,
                entityType: "email",
                title: row["subject"]?.textValue ?? "Email",
                subtitle: sender,
                path: row["message_path"]?.textValue,
                url: messageURL(messageID: messageID),
                createdAt: SearchUtilities.macAbsoluteDate(row["date_sent"]?.double),
                authors: sender.map { [$0] },
                metadata: [
                    "rowid": .number(Double(rowID)),
                    "messageID": messageID.map(JSONValue.string) ?? .null,
                    "mailbox": jsonValue(row["mailbox"]),
                    "flags": jsonValue(row["flags"]),
                    "recipients": jsonValue(row["recipients"]),
                    "snippet": jsonValue(row["snippet"])
                ]
            )
        }
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

    private func optionalColumnExpression(_ column: String?, tableAlias: String) -> String? {
        column.map { "\(tableAlias).\($0)" }
    }

    private func findEnvelopeIndexes() -> [String] {
        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        guard let enumerator = FileManager.default.enumerator(at: mailURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasPrefix("Envelope Index") {
                paths.append(url.path)
            }
        }
        return paths.sorted()
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
}
