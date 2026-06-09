import Foundation

struct MessagesSQLiteProvider: SearchProvider {
    let source: SearchSource = .messages
    let chatDBPath: String

    static let defaultChatDBPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")
        .path

    init(chatDBPath: String = MessagesSQLiteProvider.defaultChatDBPath) {
        self.chatDBPath = chatDBPath
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }

        guard FileManager.default.fileExists(atPath: chatDBPath) else {
            let messagesURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages")
            if ProtectedStore.isUnreadableExistingPath(messagesURL) {
                throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Messages", path: messagesURL.path))
            }
            throw ProviderError.unavailable("Messages database is not available")
        }

        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase(path: chatDBPath)
        } catch {
            if ProtectedStore.isSQLiteAuthorizationDenied(error) {
                throw ProviderError.unavailable(ProtectedStore.privacyMessage(source: "Messages", path: chatDBPath))
            }
            throw error
        }

        guard try tableExists("message", in: db) else {
            throw ProviderError.unavailable("Messages message table is not available")
        }

        return try searchMessages(context, db: db)
    }

    private func searchMessages(_ context: ProviderSearchContext, db: SQLiteDatabase) throws -> [SearchResultRecord] {
        let messageColumns = try columnNames(table: "message", in: db)
        let handleColumns = try tableExists("handle", in: db) ? columnNames(table: "handle", in: db) : []
        let hasHandleJoin = messageColumns.contains("handle_id") && !handleColumns.isEmpty
        let hasChatTables = try tableExists("chat", in: db) && tableExists("chat_message_join", in: db)

        let textExpr = optionalColumnExpression(firstExisting(["text", "body"], in: messageColumns), tableAlias: "m")
        let attributedBodyExpr = optionalColumnExpression(firstExisting(["attributedBody", "attributed_body"], in: messageColumns), tableAlias: "m")
        let dateExpr = optionalColumnExpression(firstExisting(["date", "date_read", "date_delivered"], in: messageColumns), tableAlias: "m")
        let guidExpr = optionalColumnExpression(firstExisting(["guid"], in: messageColumns), tableAlias: "m")
        let serviceExpr = optionalColumnExpression(firstExisting(["service"], in: messageColumns), tableAlias: "m")
        let isFromMeExpr = optionalColumnExpression(firstExisting(["is_from_me"], in: messageColumns), tableAlias: "m")
        let handleExpr = handleExpression(handleColumns: handleColumns, hasHandleJoin: hasHandleJoin)
        let chatExpr = chatExpression(hasChatTables: hasChatTables)

        let haystackExpressions = [textExpr, handleExpr, chatExpr, serviceExpr].compactMap { $0 }
        guard !haystackExpressions.isEmpty else {
            throw ProviderError.unavailable("Messages schema is not recognized")
        }

        let joins = hasHandleJoin ? "LEFT JOIN handle h ON h.ROWID = m.handle_id" : ""
        let rows = try db.rows(
            """
            SELECT m.ROWID AS rowid,
                   \(guidExpr ?? "NULL") AS guid,
                   \(textExpr ?? "NULL") AS text,
                   \(attributedBodyExpr ?? "NULL") AS attributed_body,
                   \(dateExpr ?? "NULL") AS message_date,
                   \(serviceExpr ?? "NULL") AS service,
                   \(isFromMeExpr ?? "NULL") AS is_from_me,
                   \(handleExpr ?? "NULL") AS handle,
                   \(chatExpr ?? "NULL") AS chat
            FROM message m
            \(joins)
            WHERE lower(\(haystackExpressions.map { "coalesce(CAST(\($0) AS TEXT), '')" }.joined(separator: " || ' ' || "))) LIKE lower(?)
            ORDER BY \(dateExpr ?? "m.ROWID") DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .int(Int64(context.limit))]
        )

        return rows.compactMap { row in
            guard let rowID = row["rowid"]?.int64 else { return nil }
            let body = row["text"]?.textValue ?? decodeAttributedBody(row["attributed_body"]?.data)
            let snippet = body.map { clipped($0, maxLength: 180) }
            let handle = row["handle"]?.textValue
            let chat = row["chat"]?.textValue
            let isFromMe = row["is_from_me"]?.int64
            let counterpart = isFromMe == 1 ? chat ?? handle : handle ?? chat
            return SearchResultRecord(
                id: SearchUtilities.stableID([SearchSource.messages.rawValue, String(rowID)]),
                source: SearchSource.messages.rawValue,
                entityType: "message",
                title: snippet ?? "Message",
                subtitle: counterpart ?? row["service"]?.textValue,
                url: messageURL(guid: row["guid"]?.textValue),
                createdAt: messagesDate(row["message_date"]?.double),
                authors: counterpart.map { [$0] },
                metadata: [
                    "rowid": .number(Double(rowID)),
                    "guid": row["guid"]?.textValue.map(JSONValue.string) ?? .null,
                    "handle": handle.map(JSONValue.string) ?? .null,
                    "chat": chat.map(JSONValue.string) ?? .null,
                    "service": row["service"]?.textValue.map(JSONValue.string) ?? .null,
                    "isFromMe": isFromMe.map { .bool($0 == 1) } ?? .null,
                    "snippet": snippet.map(JSONValue.string) ?? .null
                ]
            )
        }
    }

    private func handleExpression(handleColumns: Set<String>, hasHandleJoin: Bool) -> String? {
        guard hasHandleJoin else {
            return nil
        }
        let handlePieces = ["id", "uncanonicalized_id", "country", "service"]
            .filter { handleColumns.contains($0) }
            .map { "h.\($0)" }
        guard !handlePieces.isEmpty else {
            return nil
        }
        return "coalesce(\(handlePieces.joined(separator: ", ")))"
    }

    private func chatExpression(hasChatTables: Bool) -> String? {
        guard hasChatTables else {
            return nil
        }
        return """
        (
            SELECT coalesce(c.display_name, c.chat_identifier)
            FROM chat_message_join cmj
            JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE cmj.message_id = m.ROWID
            LIMIT 1
        )
        """
    }

    private func messageURL(guid: String?) -> String? {
        guard let guid, !guid.isEmpty else {
            return nil
        }
        let encoded = guid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? guid
        return "imessage://\(encoded)"
    }

    private func messagesDate(_ value: Double?) -> Date? {
        guard var value else {
            return nil
        }
        if value > 10_000_000_000_000 {
            value /= 1_000_000_000
        }
        return SearchUtilities.macAbsoluteDate(value)
    }

    private func decodeAttributedBody(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        let classes: [AnyClass] = [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            NSString.self,
            NSMutableString.self,
            NSDictionary.self,
            NSMutableDictionary.self,
            NSArray.self,
            NSMutableArray.self,
            NSData.self,
            NSNumber.self,
            NSDate.self,
            NSURL.self,
            NSNull.self
        ]
        if let object = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) {
            if let attributed = object as? NSAttributedString, !attributed.string.isEmpty {
                return attributed.string
            }
            if let string = object as? String, !string.isEmpty {
                return string
            }
        }

        return String(data: data, encoding: .utf8)?
            .components(separatedBy: CharacterSet.controlCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .joined(separator: " ")
    }

    private func clipped(_ text: String, maxLength: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else {
            return collapsed
        }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }

    private func optionalColumnExpression(_ column: String?, tableAlias: String) -> String? {
        column.map { "\(tableAlias).\($0)" }
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
