import Contacts
import EventKit
import Foundation

enum ProviderReadinessDetector {
    static func records() -> [ProviderReadinessRecord] {
        SearchSource.allCases.map(record(for:))
    }

    private static func record(for source: SearchSource) -> ProviderReadinessRecord {
        switch source {
        case .files:
            fileRecord()
        case .photos:
            photosRecord()
        case .contacts:
            contactsRecord()
        case .calendar:
            calendarRecord()
        case .reminders:
            remindersRecord()
        case .notes:
            notesRecord()
        case .mail:
            mailRecord()
        case .messages:
            messagesRecord()
        case .safari:
            safariRecord()
        }
    }

    private static func fileRecord() -> ProviderReadinessRecord {
        let enabled = SpotlightSearchService.spotlightIndexingAppearsEnabled()
        return ProviderReadinessRecord(
            source: SearchSource.files.rawValue,
            status: enabled ? "ready" : "unavailable",
            summary: enabled ? "Spotlight file index appears enabled." : "Spotlight file index does not appear enabled.",
            setupHint: enabled ? nil : "Enable Spotlight indexing for the volume with mdutil, then retry.",
            checks: [
                ProviderReadinessCheck(
                    name: "spotlight-indexing",
                    status: enabled ? "ok" : "failed",
                    message: enabled ? "mdutil reports indexing enabled." : "mdutil did not report indexing enabled."
                )
            ]
        )
    }

    private static func photosRecord() -> ProviderReadinessRecord {
        let libraryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Photos Library.photoslibrary")
        let photosDB = libraryURL.appendingPathComponent("database/Photos.sqlite")
        let searchDB = libraryURL.appendingPathComponent("database/search/leo.sqlite")
        let checks = [
            pathCheck(name: "photos-database", url: photosDB),
            pathCheck(name: "photos-search-index", url: searchDB)
        ]
        let hasDB = FileManager.default.isReadableFile(atPath: photosDB.path)
        let hasSearch = FileManager.default.isReadableFile(atPath: searchDB.path)
        let status = hasDB ? "ready" : (ProtectedStore.isUnreadableExistingPath(libraryURL) ? "needs_permission" : "missing")
        let summary = hasDB && hasSearch
            ? "Photos library and semantic/person search indexes are readable."
            : hasDB ? "Photos library database is readable; semantic search index is missing or unreadable." : "Photos library database is not readable."
        return ProviderReadinessRecord(
            source: SearchSource.photos.rawValue,
            status: status,
            summary: summary,
            setupHint: status == "ready" ? nil : "Grant Photos/Full Disk Access to Limelight, or verify the default Photos library path.",
            checks: checks
        )
    }

    private static func contactsRecord() -> ProviderReadinessRecord {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let ready = status == .authorized
        return ProviderReadinessRecord(
            source: SearchSource.contacts.rawValue,
            status: ready ? "ready" : "needs_permission",
            summary: "Contacts permission is \(status).",
            setupHint: ready ? nil : "Grant Contacts access to Limelight.",
            checks: [
                ProviderReadinessCheck(name: "contacts-permission", status: ready ? "ok" : "needs_permission", message: "\(status)")
            ]
        )
    }

    private static func calendarRecord() -> ProviderReadinessRecord {
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        let calendarDB = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Calendars/Calendar.sqlitedb")
        let checks = [
            ProviderReadinessCheck(name: "eventkit-events", status: eventAccessStatus(eventStatus), message: "\(eventStatus)"),
            ProviderReadinessCheck(name: "contacts-birthday-fallback", status: contactsStatus == .authorized ? "ok" : "needs_permission", message: "\(contactsStatus)"),
            pathCheck(name: "calendar-private-store", url: calendarDB)
        ]
        let hasEventAccess = canReadEvents(eventStatus)
        let hasBirthdayFallback = contactsStatus == .authorized
        let status = hasEventAccess ? "ready" : (hasBirthdayFallback ? "partial" : "needs_permission")
        let summary = hasEventAccess
            ? "EventKit calendar access is available."
            : hasBirthdayFallback ? "Calendar events are not fully available, but Contacts birthday fallback is ready." : "Calendar access is not available."
        return ProviderReadinessRecord(
            source: SearchSource.calendar.rawValue,
            status: status,
            summary: summary,
            setupHint: status == "ready" ? nil : "Grant Calendar access for events; Contacts access is enough for contact birthday fallback only.",
            checks: checks
        )
    }

    private static func remindersRecord() -> ProviderReadinessRecord {
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        let discoveredPaths = LocalRemindersProvider.discoverReminderDatabasePaths()
        let checks = discoveredPaths.isEmpty
            ? [ProviderReadinessCheck(name: "reminders-private-store", status: "missing", path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Reminders").path, message: "No candidate Reminders SQLite stores were discovered.")]
            : discoveredPaths.map { pathCheck(name: "reminders-private-store", url: URL(fileURLWithPath: $0)) }
        let permissionStatus = eventAccessStatus(reminderStatus)
        let hasReadableStore = checks.contains { $0.status == "ok" }
        let status = hasReadableStore || permissionStatus == "ok" ? "ready" : "needs_permission"
        let summary: String
        if permissionStatus == "ok" {
            summary = "EventKit Reminders access is available."
        } else if hasReadableStore {
            summary = "Reminders private store is readable."
        } else {
            summary = "Reminders access is not currently available."
        }
        return ProviderReadinessRecord(
            source: SearchSource.reminders.rawValue,
            status: status,
            summary: summary,
            setupHint: status == "ready" ? nil : "Grant Reminders access or Full Disk Access to Limelight, then retry.",
            checks: [ProviderReadinessCheck(name: "eventkit-reminders", status: permissionStatus, message: "\(reminderStatus)")] + checks
        )
    }

    private static func notesRecord() -> ProviderReadinessRecord {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.apple.Notes/Data/Library/Notes/NotesV7.storedata")
        ]
        let checks = candidates.map { pathCheck(name: "notes-private-store", url: $0) }
        let status = readinessStatus(for: checks)
        return ProviderReadinessRecord(
            source: SearchSource.notes.rawValue,
            status: status,
            summary: status == "ready" ? "Notes private store is readable." : "Notes private store is not currently readable.",
            setupHint: status == "ready" ? nil : "Grant Full Disk Access to Limelight, then retry.",
            checks: checks
        )
    }

    private static func mailRecord() -> ProviderReadinessRecord {
        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        var checks = [pathCheck(name: "mail-container", url: mailURL)]
        if FileManager.default.isReadableFile(atPath: mailURL.path),
           let enumerator = FileManager.default.enumerator(at: mailURL, includingPropertiesForKeys: nil) {
            var envelopeChecks: [ProviderReadinessCheck] = []
            for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("Envelope Index") {
                envelopeChecks.append(pathCheck(name: "mail-envelope-index", url: url))
                if envelopeChecks.count >= 8 {
                    break
                }
            }
            checks.append(contentsOf: envelopeChecks.isEmpty ? [
                ProviderReadinessCheck(name: "mail-envelope-index", status: "missing", message: "No Envelope Index file was found under \(mailURL.path).")
            ] : envelopeChecks)
        }
        let status = checks.contains(where: { $0.name == "mail-envelope-index" && $0.status == "ok" }) ? "ready" : readinessStatus(for: checks)
        return ProviderReadinessRecord(
            source: SearchSource.mail.rawValue,
            status: status,
            summary: status == "ready" ? "Mail envelope index is readable." : "Mail envelope index is not currently readable.",
            setupHint: status == "ready" ? nil : "Grant Full Disk Access to Limelight, then retry.",
            checks: checks
        )
    }

    private static func safariRecord() -> ProviderReadinessRecord {
        let safariURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
        let historyDB = safariURL.appendingPathComponent("History.db")
        let checks = [
            pathCheck(name: "safari-container", url: safariURL),
            pathCheck(name: "safari-history-db", url: historyDB)
        ]
        let status = FileManager.default.isReadableFile(atPath: historyDB.path) ? "ready" : readinessStatus(for: checks)
        return ProviderReadinessRecord(
            source: SearchSource.safari.rawValue,
            status: status,
            summary: status == "ready" ? "Safari history database is readable." : "Safari history database is not currently readable.",
            setupHint: status == "ready" ? nil : "Grant Full Disk Access to Limelight, then retry.",
            checks: checks
        )
    }

    private static func messagesRecord() -> ProviderReadinessRecord {
        let messagesURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages")
        let chatDB = messagesURL.appendingPathComponent("chat.db")
        let checks = [
            pathCheck(name: "messages-container", url: messagesURL),
            pathCheck(name: "messages-chat-db", url: chatDB)
        ]
        let status = FileManager.default.isReadableFile(atPath: chatDB.path) ? "ready" : readinessStatus(for: checks)
        return ProviderReadinessRecord(
            source: SearchSource.messages.rawValue,
            status: status,
            summary: status == "ready" ? "Messages chat database is readable." : "Messages chat database is not currently readable.",
            setupHint: status == "ready" ? nil : "Grant Full Disk Access to Limelight, then retry.",
            checks: checks
        )
    }

    private static func pathCheck(name: String, url: URL) -> ProviderReadinessCheck {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            let parent = url.deletingLastPathComponent()
            if ProtectedStore.isUnreadableExistingPath(parent) {
                return ProviderReadinessCheck(
                    name: name,
                    status: "needs_permission",
                    path: url.path,
                    message: "Parent path exists but is not readable: \(parent.path)"
                )
            }
            return ProviderReadinessCheck(name: name, status: "missing", path: url.path, message: "Path does not exist.")
        }
        let readable = FileManager.default.isReadableFile(atPath: url.path)
        return ProviderReadinessCheck(
            name: name,
            status: readable ? "ok" : "needs_permission",
            path: url.path,
            message: readable ? (isDirectory.boolValue ? "Directory is readable." : "File is readable.") : "Path exists but is not readable."
        )
    }

    private static func readinessStatus(for checks: [ProviderReadinessCheck]) -> String {
        if checks.contains(where: { $0.status == "ok" }) {
            return "ready"
        }
        if checks.contains(where: { $0.status == "needs_permission" }) {
            return "needs_permission"
        }
        return "missing"
    }

    private static func eventAccessStatus(_ status: EKAuthorizationStatus) -> String {
        if canReadEvents(status) {
            return "ok"
        }
        switch status {
        case .fullAccess:
            return "ok"
        case .writeOnly:
            return "needs_permission"
        case .denied, .restricted, .notDetermined:
            return "needs_permission"
        @unknown default:
            return "unknown"
        }
    }

    private static func canReadEvents(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status.rawValue == 3
    }
}
