import Foundation

public struct HealthResponse: Codable, Equatable, Sendable {
    public let status: String
    public let spotlightIndexingEnabled: Bool
    public let providers: [String]
}

public struct ErrorResponse: Codable, Equatable, Sendable {
    public let error: String
}
