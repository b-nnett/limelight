import EventKit
import Foundation

struct LocalRemindersProvider: SearchProvider {
    let source: SearchSource = .reminders
    let remindersDBPath: String?

    init(remindersDBPath: String? = nil) {
        self.remindersDBPath = remindersDBPath
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }

        if let eventKitResults = try eventKitResults(context) {
            return eventKitResults
        }

        let paths = remindersDBPath.map { [$0] } ?? Self.discoverReminderDatabasePaths()
        guard !paths.isEmpty else {
            throw ProviderError.unavailable("Reminders database is not available")
        }

        var lastError: Error?
        for path in paths {
            do {
                let db = try SQLiteDatabase(path: path)
                guard try tableExists("reminders", in: db) else {
                    continue
                }
                return try searchSQLiteReminders(context, db: db)
            } catch {
                lastError = error
            }
        }
        throw ProviderError.unavailable(lastError?.localizedDescription ?? "Reminders table is not available")
    }

    private func searchSQLiteReminders(_ context: ProviderSearchContext, db: SQLiteDatabase) throws -> [SearchResultRecord] {
        let rows = try db.rows(
            """
            SELECT id, title, notes, due_date, completed
            FROM reminders
            WHERE lower(coalesce(title, '') || ' ' || coalesce(notes, '')) LIKE lower(?)
            ORDER BY due_date DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .int(Int64(context.limit))]
        )
        return rows.compactMap { row in
            guard let id = row["id"]?.int64 else { return nil }
            return SearchResultRecord(
                id: SearchUtilities.stableID([SearchSource.reminders.rawValue, String(id)]),
                source: SearchSource.reminders.rawValue,
                entityType: "reminder",
                title: row["title"]?.string ?? "Reminder",
                subtitle: row["notes"]?.string,
                endAt: SearchUtilities.macAbsoluteDate(row["due_date"]?.double),
                metadata: [
                    "reminderID": .number(Double(id)),
                    "completed": .bool((row["completed"]?.int64 ?? 0) != 0)
                ]
            )
        }
    }

    static func discoverReminderDatabasePaths() -> [String] {
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Reminders"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.reminders"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.apple.reminders/Data/Library/Reminders")
        ]

        var paths: [String] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                if ["sqlite", "db"].contains(ext) || name.contains("reminder") || name.hasPrefix("data-") {
                    paths.append(url.path)
                }
            }
        }
        return Array(Set(paths)).sorted()
    }

    private func tableExists(_ name: String, in db: SQLiteDatabase) throws -> Bool {
        try !db.rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", bindings: [.text(name)]).isEmpty
    }

    private func eventKitResults(_ context: ProviderSearchContext) throws -> [SearchResultRecord]? {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard Self.canReadReminders(status) else {
            return nil
        }

        let store = EKEventStore()
        let semaphore = DispatchSemaphore(value: 0)
        let result = RemindersFetchResult()
        store.fetchReminders(matching: store.predicateForReminders(in: nil)) { reminders in
            result.reminders = reminders ?? []
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)

        let needle = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.reminders
            .filter { reminder in
                needle.isEmpty || SearchUtilities.contains([reminder.title, reminder.notes].compactMap { $0 }.joined(separator: " "), needle)
            }
            .sorted { lhs, rhs in
                (Self.date(from: lhs.dueDateComponents) ?? .distantPast) > (Self.date(from: rhs.dueDateComponents) ?? .distantPast)
            }
            .prefix(context.limit)
            .map { reminder in
                SearchResultRecord(
                    id: SearchUtilities.stableID([SearchSource.reminders.rawValue, reminder.calendarItemIdentifier]),
                    source: SearchSource.reminders.rawValue,
                    entityType: "reminder",
                    title: reminder.title ?? "Reminder",
                    subtitle: reminder.notes,
                    endAt: Self.date(from: reminder.dueDateComponents),
                    metadata: [
                        "reminderID": .string(reminder.calendarItemIdentifier),
                        "calendar": .string(reminder.calendar.title),
                        "completed": .bool(reminder.isCompleted),
                        "matchReason": .string("eventkit")
                    ]
                )
            }
    }

    private static func canReadReminders(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status.rawValue == 3
    }

    private static func date(from components: DateComponents?) -> Date? {
        guard let components else {
            return nil
        }
        return Calendar.current.date(from: components)
    }
}

private final class RemindersFetchResult: @unchecked Sendable {
    var reminders: [EKReminder] = []
}
