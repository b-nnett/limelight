import Foundation

public enum SearchSource: String, CaseIterable, Sendable {
    case files
    case photos
    case contacts
    case calendar
    case reminders
    case notes
    case mail
    case messages
    case safari
}

struct ProviderSearchContext: Sendable {
    let query: String
    let types: [String]
    let onlyIn: [String]
    let limit: Int
}

protocol SearchProvider: Sendable {
    var source: SearchSource { get }
    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord]
}

protocol ItemProvider: SearchProvider {
    func item(id: String) throws -> ItemRecord
}

enum ProviderError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason
        }
    }
}

enum ProtectedStore {
    static func privacyMessage(source: String, path: String) -> String {
        "\(source) store exists but is not readable at \(path). Grant Full Disk Access to Limelight, then retry."
    }

    static func isUnreadableExistingPath(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !FileManager.default.isReadableFile(atPath: url.path)
    }

    static func isSQLiteAuthorizationDenied(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("authorization denied")
            || error.localizedDescription.localizedCaseInsensitiveContains("operation not permitted")
    }
}

enum SearchUtilities {
    static func stableID(_ parts: [String]) -> String {
        SpotlightRecordNormalizer.stableID(path: parts.joined(separator: "\u{1f}"), contentType: nil)
    }

    static func macAbsoluteDate(_ value: Double?) -> Date? {
        guard let value else { return nil }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    static func contains(_ haystack: String?, _ needle: String) -> Bool {
        guard let haystack else { return false }
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
