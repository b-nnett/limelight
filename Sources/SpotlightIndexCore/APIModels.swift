import Foundation

public struct HealthResponse: Codable, Equatable, Sendable {
    public let status: String
    public let spotlightIndexingEnabled: Bool
    public let providers: [String]
}

public struct SearchRequest: Codable, Equatable, Sendable {
    public let query: String
    public let types: [String]?
    public let sources: [String]?
    public let onlyIn: [String]?
    public let limit: Int?

    public init(query: String, types: [String]? = nil, sources: [String]? = nil, onlyIn: [String]? = nil, limit: Int? = nil) {
        self.query = query
        self.types = types
        self.sources = sources
        self.onlyIn = onlyIn
        self.limit = limit
    }
}

public struct SearchResponse: Codable, Equatable, Sendable {
    public let query: String
    public let count: Int
    public let limit: Int
    public let results: [SearchResultRecord]
    public let providers: [ProviderSearchStatus]
}

public struct DeepSearchRequest: Codable, Equatable, Sendable {
    public let queries: [String]
    public let regexes: [String]?
    public let types: [String]?
    public let sources: [String]?
    public let onlyIn: [String]?
    public let limitPerQuery: Int?
    public let limit: Int?

    public init(
        queries: [String],
        regexes: [String]? = nil,
        types: [String]? = nil,
        sources: [String]? = nil,
        onlyIn: [String]? = nil,
        limitPerQuery: Int? = nil,
        limit: Int? = nil
    ) {
        self.queries = queries
        self.regexes = regexes
        self.types = types
        self.sources = sources
        self.onlyIn = onlyIn
        self.limitPerQuery = limitPerQuery
        self.limit = limit
    }
}

public struct DeepSearchResponse: Codable, Equatable, Sendable {
    public let queries: [String]
    public let regexes: [String]
    public let count: Int
    public let limit: Int
    public let results: [DeepSearchResultRecord]
    public let providers: [ProviderSearchStatus]
}

public struct DeepSearchResultRecord: Codable, Equatable, Sendable {
    public let result: SearchResultRecord
    public let matchedQueries: [String]
    public let matchedRegexes: [String]
    public let score: Int
}

public struct OCRRequest: Codable, Equatable, Sendable {
    public let path: String?
    public let photoUUID: String?
    public let recognitionLevel: String?
    public let languages: [String]?
    public let includeText: Bool?

    public init(path: String? = nil, photoUUID: String? = nil, recognitionLevel: String? = nil, languages: [String]? = nil, includeText: Bool? = nil) {
        self.path = path
        self.photoUUID = photoUUID
        self.recognitionLevel = recognitionLevel
        self.languages = languages
        self.includeText = includeText
    }
}

public struct OCRResponse: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let photoUUID: String?
    public let text: String?
    public let lines: [OCRLineRecord]
}

public struct OCRLineRecord: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Float
}

public struct ExtractRequest: Codable, Equatable, Sendable {
    public let entityTypes: [String]
    public let text: String?
    public let path: String?
    public let photoUUID: String?
    public let search: DeepSearchRequest?
    public let ocr: ExtractOCRRequest?
    public let saveTo: String?
    public let includeContext: Bool?
    public let includeOCRText: Bool?

    public init(
        entityTypes: [String],
        text: String? = nil,
        path: String? = nil,
        photoUUID: String? = nil,
        search: DeepSearchRequest? = nil,
        ocr: ExtractOCRRequest? = nil,
        saveTo: String? = nil,
        includeContext: Bool? = nil,
        includeOCRText: Bool? = nil
    ) {
        self.entityTypes = entityTypes
        self.text = text
        self.path = path
        self.photoUUID = photoUUID
        self.search = search
        self.ocr = ocr
        self.saveTo = saveTo
        self.includeContext = includeContext
        self.includeOCRText = includeOCRText
    }
}

public struct ExtractOCRRequest: Codable, Equatable, Sendable {
    public let enabled: Bool?
    public let maxItems: Int?
    public let recognitionLevel: String?
    public let stopOnHighConfidence: Bool?

    public init(enabled: Bool? = nil, maxItems: Int? = nil, recognitionLevel: String? = nil, stopOnHighConfidence: Bool? = nil) {
        self.enabled = enabled
        self.maxItems = maxItems
        self.recognitionLevel = recognitionLevel
        self.stopOnHighConfidence = stopOnHighConfidence
    }
}

public struct ExtractResponse: Codable, Equatable, Sendable {
    public let entityTypes: [String]
    public let count: Int
    public let entities: [ExtractedEntityRecord]
    public let searchedResults: Int
    public let ocrResults: Int
    public let ocrDocuments: [OCRDocumentRecord]
    public let savedTo: String?
}

public struct OCRDocumentRecord: Codable, Equatable, Sendable {
    public let source: ExtractionSourceRecord?
    public let text: String
    public let lines: [OCRLineRecord]
}

public struct ExtractedEntityRecord: Codable, Equatable, Sendable {
    public let entityType: String
    public let value: String
    public let redactedValue: String
    public let confidence: Int
    public let reason: String
    public let source: ExtractionSourceRecord?
    public let context: String?
}

public struct ExtractionSourceRecord: Codable, Equatable, Sendable {
    public let source: String?
    public let entityType: String?
    public let title: String?
    public let path: String?
    public let url: String?
    public let photoUUID: String?
    public let resultID: String?
}

public struct ProviderSearchStatus: Codable, Equatable, Sendable {
    public let source: String
    public let status: String
    public let count: Int
    public let error: String?
}

public struct ItemResponse: Codable, Equatable, Sendable {
    public let item: ItemRecord
}

public struct OpenItemRequest: Codable, Equatable, Sendable {
    public let path: String?
    public let source: String?
    public let id: String?
    public let url: String?

    public init(path: String? = nil, source: String? = nil, id: String? = nil, url: String? = nil) {
        self.path = path
        self.source = source
        self.id = id
        self.url = url
    }
}

public struct OpenItemResponse: Codable, Equatable, Sendable {
    public let opened: Bool
    public let target: String
    public let item: ItemRecord?
}

public struct SchemaResponse: Codable, Equatable, Sendable {
    public let normalizedFields: [String: String]
    public let supportedTypes: [String]
    public let supportedSources: [String]
    public let metadataAttributes: [String]
    public let providerFields: [String: ProviderSchemaRecord]
}

public struct ProviderSchemaRecord: Codable, Equatable, Sendable {
    public let entityTypes: [String]
    public let fields: [String: String]
    public let metadataFields: [String: String]
}

public struct CapabilitiesResponse: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let sources: [SourceCapabilityRecord]
}

public struct SourceCapabilityRecord: Codable, Equatable, Sendable {
    public let source: String
    public let entityTypes: [String]
    public let permissionRequired: String
    public let liveStatus: String
    public let summary: String
    public let supportedFields: [String]
    public let limitations: [String]
    public let setupHint: String?
}

public struct PermissionRequest: Codable, Equatable, Sendable {
    public let sources: [String]?

    public init(sources: [String]? = nil) {
        self.sources = sources
    }
}

public struct PermissionResponse: Codable, Equatable, Sendable {
    public let results: [PermissionActionRecord]
}

public struct PermissionActionRecord: Codable, Equatable, Sendable {
    public let source: String
    public let status: String
    public let message: String
    public let setupHint: String?
}

public struct ProvidersResponse: Codable, Equatable, Sendable {
    public let providers: [ProviderReadinessRecord]
}

public struct ProviderReadinessRecord: Codable, Equatable, Sendable {
    public let source: String
    public let status: String
    public let summary: String
    public let setupHint: String?
    public let checks: [ProviderReadinessCheck]

    public init(source: String, status: String, summary: String, setupHint: String? = nil, checks: [ProviderReadinessCheck] = []) {
        self.source = source
        self.status = status
        self.summary = summary
        self.setupHint = setupHint
        self.checks = checks
    }
}

public struct ProviderReadinessCheck: Codable, Equatable, Sendable {
    public let name: String
    public let status: String
    public let path: String?
    public let message: String?

    public init(name: String, status: String, path: String? = nil, message: String? = nil) {
        self.name = name
        self.status = status
        self.path = path
        self.message = message
    }
}

public struct ErrorResponse: Codable, Equatable, Sendable {
    public let error: String
}

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
