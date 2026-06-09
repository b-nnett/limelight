import Foundation

public struct SpotlightRecord: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String?
    public let contentType: String?
    public let kind: String?
    public let bundleIdentifier: String?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let authors: [String]?
    public let sizeBytes: Int64?
    public let metadata: [String: JSONValue]
}

public struct ItemRecord: Codable, Equatable, Sendable {
    public let id: String
    public let source: String?
    public let entityType: String?
    public let title: String?
    public let subtitle: String?
    public let path: String?
    public let url: String?
    public let displayName: String?
    public let contentType: String?
    public let kind: String?
    public let bundleIdentifier: String?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let startAt: Date?
    public let endAt: Date?
    public let authors: [String]?
    public let sizeBytes: Int64?
    public let metadata: [String: JSONValue]

    public init(
        id: String,
        source: String? = nil,
        entityType: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        path: String? = nil,
        url: String? = nil,
        displayName: String? = nil,
        contentType: String? = nil,
        kind: String? = nil,
        bundleIdentifier: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        authors: [String]? = nil,
        sizeBytes: Int64? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.source = source
        self.entityType = entityType
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.url = url
        self.displayName = displayName
        self.contentType = contentType
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.startAt = startAt
        self.endAt = endAt
        self.authors = authors
        self.sizeBytes = sizeBytes
        self.metadata = metadata
    }

    init(file record: SpotlightRecord) {
        self.init(
            id: record.id,
            source: SearchSource.files.rawValue,
            entityType: "file",
            title: record.displayName ?? URL(fileURLWithPath: record.path).lastPathComponent,
            path: record.path,
            displayName: record.displayName,
            contentType: record.contentType,
            kind: record.kind,
            bundleIdentifier: record.bundleIdentifier,
            createdAt: record.createdAt,
            modifiedAt: record.modifiedAt,
            authors: record.authors,
            sizeBytes: record.sizeBytes,
            metadata: record.metadata
        )
    }

    init(result record: SearchResultRecord) {
        self.init(
            id: record.id,
            source: record.source,
            entityType: record.entityType,
            title: record.title,
            subtitle: record.subtitle,
            path: record.path,
            url: record.url,
            contentType: record.contentType,
            createdAt: record.createdAt,
            modifiedAt: record.modifiedAt,
            startAt: record.startAt,
            endAt: record.endAt,
            authors: record.authors,
            sizeBytes: record.sizeBytes,
            metadata: record.metadata
        )
    }
}

public struct SearchResultRecord: Codable, Equatable, Sendable {
    public let id: String
    public let source: String
    public let entityType: String
    public let title: String
    public let subtitle: String?
    public let path: String?
    public let url: String?
    public let contentType: String?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let startAt: Date?
    public let endAt: Date?
    public let authors: [String]?
    public let sizeBytes: Int64?
    public let metadata: [String: JSONValue]

    public init(
        id: String,
        source: String,
        entityType: String,
        title: String,
        subtitle: String? = nil,
        path: String? = nil,
        url: String? = nil,
        contentType: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        authors: [String]? = nil,
        sizeBytes: Int64? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.source = source
        self.entityType = entityType
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.url = url
        self.contentType = contentType
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.startAt = startAt
        self.endAt = endAt
        self.authors = authors
        self.sizeBytes = sizeBytes
        self.metadata = metadata
    }
}
