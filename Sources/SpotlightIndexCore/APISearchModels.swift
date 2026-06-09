import Foundation

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

public struct ProviderSearchStatus: Codable, Equatable, Sendable {
    public let source: String
    public let status: String
    public let count: Int
    public let error: String?
}
