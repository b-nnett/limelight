import Foundation

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
