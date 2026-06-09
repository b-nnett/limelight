import Foundation

enum ProviderCatalog {
    static let schemas: [SearchSource: ProviderSchemaRecord] = [
        .files: ProviderSchemaRecord(
            entityTypes: ["file"],
            fields: baseFields.merging([
                "path": "Absolute filesystem path.",
                "contentType": "Uniform Type Identifier from Spotlight.",
                "bundleIdentifier": "Application bundle identifier when available.",
                "authors": "Author metadata from kMDItemAuthors."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "kMDItemDisplayName": "Spotlight display name.",
                "kMDItemContentType": "Primary UTI.",
                "kMDItemKind": "Localized Finder kind.",
                "kMDItemFSSize": "File size in bytes."
            ]
        ),
        .photos: ProviderSchemaRecord(
            entityTypes: ["photo", "video"],
            fields: baseFields.merging([
                "path": "Best local derivative path when available.",
                "subtitle": "Matched person name or Photos source label."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "uuid": "Photos asset UUID.",
                "matchReason": "person or photos-search.",
                "mediaKind": "image, video, live-photo, or screenshot-or-image.",
                "width": "Pixel width.",
                "height": "Pixel height."
            ]
        ),
        .contacts: ProviderSchemaRecord(
            entityTypes: ["contact"],
            fields: baseFields.merging([
                "subtitle": "Primary email when available."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "identifier": "Contacts identifier.",
                "emails": "Email addresses.",
                "phones": "Phone numbers.",
                "birthday": "Birthday date components.",
                "organization": "Organization name."
            ]
        ),
        .calendar: ProviderSchemaRecord(
            entityTypes: ["calendar-event", "birthday"],
            fields: baseFields.merging([
                "startAt": "Event start date.",
                "endAt": "Event end date.",
                "subtitle": "Calendar title."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "eventIdentifier": "EventKit or private-store event identifier.",
                "calendar": "Calendar name.",
                "location": "Event location."
            ]
        ),
        .reminders: ProviderSchemaRecord(
            entityTypes: ["reminder"],
            fields: baseFields.merging([
                "startAt": "Reminder due date when available."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "reminderID": "Private-store reminder identifier.",
                "completed": "Completion state."
            ]
        ),
        .notes: ProviderSchemaRecord(
            entityTypes: ["note"],
            fields: baseFields.merging([
                "subtitle": "Short snippet, not full note body.",
                "modifiedAt": "Note modification date when available."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "noteID": "Private-store note identifier.",
                "matchReason": "title or body."
            ]
        ),
        .mail: ProviderSchemaRecord(
            entityTypes: ["email"],
            fields: baseFields.merging([
                "subtitle": "Sender address or display name.",
                "createdAt": "Sent or received date when available.",
                "authors": "Sender list."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "rowid": "Envelope Index row id.",
                "messageID": "RFC 822 or Apple Mail message identifier when available.",
                "mailbox": "Mailbox or account label when available.",
                "flags": "Raw message flags when available.",
                "recipients": "Recipient metadata when available.",
                "snippet": "Message snippet when available."
            ]
        ),
        .messages: ProviderSchemaRecord(
            entityTypes: ["message"],
            fields: baseFields.merging([
                "subtitle": "Sender, participant, chat, or service label.",
                "createdAt": "Message date when available.",
                "authors": "Sender or chat participant when available.",
                "url": "Local imessage:// URL when a GUID is available."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "rowid": "Messages message row id.",
                "guid": "Messages GUID when available.",
                "handle": "Sender or participant handle when available.",
                "chat": "Chat display name or identifier when available.",
                "service": "Message transport such as iMessage or SMS.",
                "isFromMe": "Whether the message was sent by the local user.",
                "snippet": "Short message snippet; full conversation bodies are not exported."
            ]
        ),
        .safari: ProviderSchemaRecord(
            entityTypes: ["safari-history"],
            fields: baseFields.merging([
                "url": "Visited URL.",
                "subtitle": "Visited URL.",
                "modifiedAt": "Latest visit date."
            ], uniquingKeysWith: { _, new in new }),
            metadataFields: [
                "historyID": "Safari history item id.",
                "visitedAt": "Latest visit date.",
                "visitCount": "Number of recorded visits for the URL."
            ]
        )
    ]

    static func capabilities(readiness: ProvidersResponse) -> [SourceCapabilityRecord] {
        let readinessBySource = Dictionary(uniqueKeysWithValues: readiness.providers.map { ($0.source, $0) })
        return SearchSource.allCases.map { source in
            let schema = schemas[source] ?? ProviderSchemaRecord(entityTypes: [], fields: [:], metadataFields: [:])
            let readiness = readinessBySource[source.rawValue]
            return SourceCapabilityRecord(
                source: source.rawValue,
                entityTypes: schema.entityTypes,
                permissionRequired: permissionRequirement(for: source),
                liveStatus: readiness?.status ?? "unknown",
                summary: readiness?.summary ?? "No live readiness data is available.",
                supportedFields: (Array(schema.fields.keys) + Array(schema.metadataFields.keys)).sorted(),
                limitations: limitations(for: source),
                setupHint: readiness?.setupHint
            )
        }
    }

    private static let baseFields: [String: String] = [
        "id": "Stable local result identifier.",
        "source": "Provider name.",
        "entityType": "Provider-specific entity kind.",
        "title": "Human-readable result title."
    ]

    private static func permissionRequirement(for source: SearchSource) -> String {
        switch source {
        case .files:
            "Spotlight indexing; scoped filesystem access for paths being queried."
        case .photos:
            "Readable local Photos library database/search indexes."
        case .contacts:
            "Contacts permission."
        case .calendar:
            "Calendar permission; Contacts permission for birthday fallback."
        case .reminders:
            "Reminders permission or readable local Reminders private store."
        case .notes:
            "Full Disk Access for Notes private store."
        case .mail:
            "Full Disk Access for Mail Envelope Index."
        case .messages:
            "Full Disk Access for Messages chat.db."
        case .safari:
            "Full Disk Access for Safari History.db."
        }
    }

    private static func limitations(for source: SearchSource) -> [String] {
        switch source {
        case .files:
            return ["Uses Spotlight file metadata; ranking and content-match explanation are still basic."]
        case .photos:
            return ["Uses private Photos SQLite/search indexes; thumbnails are served from local derivatives only when available."]
        case .contacts:
            return ["Requires user permission and may return duplicate local/iCloud contact cards."]
        case .calendar:
            return ["Private Calendar SQLite fallback is machine-dependent; EventKit supplies most live results."]
        case .reminders:
            return ["Uses EventKit when permission is granted; private-store fallback remains schema-dependent."]
        case .notes:
            return ["Does not expose full note bodies by default; rich attributed note decoding is partial."]
        case .mail:
            return ["Mail message file paths and mailbox/account metadata are not fully resolved yet."]
        case .messages:
            return ["Reads the local Messages chat database; rich attributed body decoding is best-effort and full conversation export is intentionally not implemented."]
        case .safari:
            return ["Only Safari history is implemented; Chrome/Arc history are pending."]
        }
    }
}
