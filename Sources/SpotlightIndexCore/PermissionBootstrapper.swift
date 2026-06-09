import Contacts
import EventKit
import Foundation

enum PermissionBootstrapper {
    static func request(_ request: PermissionRequest) throws -> PermissionResponse {
        let sources = try requestedSources(request.sources)
        return PermissionResponse(results: sources.map(requestPermission(for:)))
    }

    private static func requestedSources(_ names: [String]?) throws -> [SearchSource] {
        let names = names ?? ["contacts", "calendar", "reminders", "photos", "notes", "mail", "messages", "safari"]
        var sources: [SearchSource] = []
        for name in names {
            guard let source = SearchSource(rawValue: name) else {
                throw SpotlightSearchError.unsupportedSource(name)
            }
            if !sources.contains(source) {
                sources.append(source)
            }
        }
        return sources
    }

    private static func requestPermission(for source: SearchSource) -> PermissionActionRecord {
        switch source {
        case .contacts:
            return requestContacts()
        case .calendar:
            return requestEvents()
        case .reminders:
            return requestReminders()
        case .photos, .notes, .mail, .messages, .safari:
            return PermissionActionRecord(
                source: source.rawValue,
                status: "manual",
                message: "macOS does not expose a programmatic Full Disk Access prompt for this source.",
                setupHint: fullDiskAccessHint()
            )
        case .files:
            return PermissionActionRecord(
                source: source.rawValue,
                status: "not_required",
                message: "No framework permission prompt is available for this source in v1.",
                setupHint: nil
            )
        }
    }

    private static func fullDiskAccessHint() -> String {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return "Open Full Disk Access and grant \(Bundle.main.bundlePath)."
        }
        return "Open Full Disk Access and grant the Limelight app bundle."
    }

    private static func requestContacts() -> PermissionActionRecord {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .notDetermined else {
            return PermissionActionRecord(source: SearchSource.contacts.rawValue, status: statusLabel(status), message: "\(status)", setupHint: nil)
        }

        let result = PermissionResult()
        let semaphore = DispatchSemaphore(value: 0)
        CNContactStore().requestAccess(for: .contacts) { granted, error in
            result.granted = granted
            result.error = error?.localizedDescription
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        let finalStatus = CNContactStore.authorizationStatus(for: .contacts)
        return PermissionActionRecord(
            source: SearchSource.contacts.rawValue,
            status: result.granted ? "authorized" : statusLabel(finalStatus),
            message: result.error ?? "\(finalStatus)",
            setupHint: result.granted ? nil : "Grant Contacts access in System Settings."
        )
    }

    private static func requestEvents() -> PermissionActionRecord {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .notDetermined else {
            return PermissionActionRecord(source: SearchSource.calendar.rawValue, status: eventStatusLabel(status), message: "\(status)", setupHint: nil)
        }

        let store = EKEventStore()
        let result = PermissionResult()
        let semaphore = DispatchSemaphore(value: 0)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                result.granted = granted
                result.error = error?.localizedDescription
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                result.granted = granted
                result.error = error?.localizedDescription
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 15)
        let finalStatus = EKEventStore.authorizationStatus(for: .event)
        return PermissionActionRecord(
            source: SearchSource.calendar.rawValue,
            status: result.granted ? "authorized" : eventStatusLabel(finalStatus),
            message: result.error ?? "\(finalStatus)",
            setupHint: result.granted ? nil : "Grant Calendar access in System Settings."
        )
    }

    private static func requestReminders() -> PermissionActionRecord {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .notDetermined else {
            return PermissionActionRecord(source: SearchSource.reminders.rawValue, status: eventStatusLabel(status), message: "\(status)", setupHint: nil)
        }

        let store = EKEventStore()
        let result = PermissionResult()
        let semaphore = DispatchSemaphore(value: 0)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { granted, error in
                result.granted = granted
                result.error = error?.localizedDescription
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .reminder) { granted, error in
                result.granted = granted
                result.error = error?.localizedDescription
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 15)
        let finalStatus = EKEventStore.authorizationStatus(for: .reminder)
        return PermissionActionRecord(
            source: SearchSource.reminders.rawValue,
            status: result.granted ? "authorized" : eventStatusLabel(finalStatus),
            message: result.error ?? "\(finalStatus)",
            setupHint: result.granted ? nil : "Grant Reminders access in System Settings."
        )
    }

    private static func statusLabel(_ status: CNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }

    private static func eventStatusLabel(_ status: EKAuthorizationStatus) -> String {
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:
                return "authorized"
            case .writeOnly:
                return "write_only"
            default:
                break
            }
        }

        switch status {
        case .fullAccess:
            return "authorized"
        case .writeOnly:
            return "write_only"
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }
}

private final class PermissionResult: @unchecked Sendable {
    var granted = false
    var error: String?
}
