import Foundation

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
