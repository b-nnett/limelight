import CoreServices
import Foundation

public protocol SpotlightMetadataReading {
    var path: String? { get }
    func value(for attribute: String) -> Any?
}

public struct MDItemMetadataReader: SpotlightMetadataReading {
    private let item: MDItem
    public let path: String?

    public init(item: MDItem, path: String? = nil) {
        self.item = item
        self.path = path
    }

    public func value(for attribute: String) -> Any? {
        MDItemCopyAttribute(item, attribute as CFString)
    }
}

public enum SpotlightMetadataError: Error, LocalizedError {
    case itemNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let path):
            "No Spotlight metadata item exists for \(path)"
        }
    }
}

public enum SpotlightAttributes {
    public static let path = "kMDItemPath"
    public static let displayName = "kMDItemDisplayName"
    public static let contentType = "kMDItemContentType"
    public static let contentTypeTree = "kMDItemContentTypeTree"
    public static let kind = "kMDItemKind"
    public static let bundleIdentifier = "kMDItemCFBundleIdentifier"
    public static let version = "kMDItemVersion"
    public static let createdAt = "kMDItemContentCreationDate"
    public static let modifiedAt = "kMDItemContentModificationDate"
    public static let authors = "kMDItemAuthors"
    public static let sizeBytes = "kMDItemFSSize"
    public static let fsName = "kMDItemFSName"

    public static let normalizedFields: [String: String] = [
        "path": path,
        "displayName": displayName,
        "contentType": contentType,
        "kind": kind,
        "bundleIdentifier": bundleIdentifier,
        "createdAt": createdAt,
        "modifiedAt": modifiedAt,
        "authors": authors,
        "sizeBytes": sizeBytes
    ]

    public static let rawMetadataKeys: [String] = [
        path,
        displayName,
        contentType,
        contentTypeTree,
        kind,
        bundleIdentifier,
        version,
        createdAt,
        modifiedAt,
        authors,
        sizeBytes,
        fsName
    ]
}
