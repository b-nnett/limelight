import Contacts
import EventKit
import Foundation

struct LocalCalendarProvider: SearchProvider {
    let source: SearchSource = .calendar
    let calendarDBPath: String

    init(calendarDBPath: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Calendars/Calendar.sqlitedb").path) {
        self.calendarDBPath = calendarDBPath
    }

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }
        let frameworkResults = try frameworkEventResults(context)
        if !frameworkResults.isEmpty {
            return frameworkResults
        }

        if FileManager.default.fileExists(atPath: calendarDBPath) {
            let sqliteResults = try sqliteEventResults(context)
            if !sqliteResults.isEmpty {
                return sqliteResults
            }
        }

        let birthdayResults = try contactBirthdayResults(context)
        if !birthdayResults.isEmpty {
            return birthdayResults
        }

        guard FileManager.default.fileExists(atPath: calendarDBPath) else {
            throw ProviderError.unavailable("Calendar database is not available")
        }
        return []
    }

    private func sqliteEventResults(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        let db = try SQLiteDatabase(path: calendarDBPath)
        guard try tableExists("events", in: db) else {
            throw ProviderError.unavailable("Calendar events table is not available")
        }
        let rows = try db.rows(
            """
            SELECT id, title, notes, location, start_date, end_date, calendar_title
            FROM events
            WHERE lower(coalesce(title, '') || ' ' || coalesce(notes, '') || ' ' || coalesce(location, '')) LIKE lower(?)
            ORDER BY start_date DESC
            LIMIT ?
            """,
            bindings: [.text("%\(context.query)%"), .int(Int64(context.limit))]
        )
        return rows.compactMap { row in
            guard let id = row["id"]?.int64 else { return nil }
            return SearchResultRecord(
                id: SearchUtilities.stableID([SearchSource.calendar.rawValue, String(id)]),
                source: SearchSource.calendar.rawValue,
                entityType: "calendar-event",
                title: row["title"]?.string ?? "Calendar event",
                subtitle: row["calendar_title"]?.string ?? row["location"]?.string,
                startAt: SearchUtilities.macAbsoluteDate(row["start_date"]?.double),
                endAt: SearchUtilities.macAbsoluteDate(row["end_date"]?.double),
                metadata: [
                    "eventID": .number(Double(id)),
                    "location": row["location"].map(JSONValue.convert) ?? .null,
                    "notes": row["notes"].map(JSONValue.convert) ?? .null
                ]
            )
        }
    }

    private func frameworkEventResults(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard Self.canReadEvents(status) else {
            return []
        }

        let store = EKEventStore()
        let start = Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date.distantPast
        let end = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date.distantFuture
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let needle = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.events(matching: predicate)
            .filter { event in
                needle.isEmpty
                    || SearchUtilities.contains(event.title, needle)
                    || SearchUtilities.contains(event.notes, needle)
                    || SearchUtilities.contains(event.location, needle)
            }
            .prefix(context.limit)
            .map { event in
                SearchResultRecord(
                    id: SearchUtilities.stableID([SearchSource.calendar.rawValue, event.eventIdentifier ?? event.title]),
                    source: SearchSource.calendar.rawValue,
                    entityType: "calendar-event",
                    title: event.title,
                    subtitle: event.calendar.title,
                    startAt: event.startDate,
                    endAt: event.endDate,
                    metadata: [
                        "eventIdentifier": event.eventIdentifier.map(JSONValue.string) ?? .null,
                        "location": event.location.map(JSONValue.string) ?? .null,
                        "calendar": .string(event.calendar.title)
                    ]
                )
            }
    }

    private func contactBirthdayResults(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            return []
        }

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        let needle = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var records: [SearchResultRecord] = []

        try store.enumerateContacts(with: request) { contact, stop in
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            guard (needle.isEmpty || SearchUtilities.contains(name, needle)), let birthday = contact.birthday else {
                return
            }

            records.append(SearchResultRecord(
                id: SearchUtilities.stableID([SearchSource.calendar.rawValue, "birthday", contact.identifier]),
                source: SearchSource.calendar.rawValue,
                entityType: "birthday",
                title: "\(name) birthday",
                subtitle: "Contacts birthday",
                startAt: birthdayDate(birthday),
                metadata: [
                    "contactIdentifier": .string(contact.identifier),
                    "month": birthday.month.map { .number(Double($0)) } ?? .null,
                    "day": birthday.day.map { .number(Double($0)) } ?? .null,
                    "year": birthday.year.map { .number(Double($0)) } ?? .null,
                    "matchReason": .string("contacts-birthday")
                ]
            ))

            if records.count >= context.limit {
                stop.pointee = true
            }
        }

        return records
    }

    private static func canReadEvents(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .writeOnly
        }
        return status.rawValue == 3
    }

    private func birthdayDate(_ components: DateComponents) -> Date? {
        var normalized = components
        if normalized.year == nil {
            normalized.year = Calendar.current.component(.year, from: Date())
        }
        return Calendar.current.date(from: normalized)
    }

    private func tableExists(_ name: String, in db: SQLiteDatabase) throws -> Bool {
        try !db.rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", bindings: [.text(name)]).isEmpty
    }
}
