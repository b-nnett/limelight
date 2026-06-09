import Foundation

public struct BuiltSpotlightQuery: Equatable {
    public let expression: String
    public let scopes: [String]
    public let limit: Int
}

public enum SpotlightQueryError: Error, LocalizedError, Equatable {
    case queryTooLong
    case unsupportedType(String)
    case invalidScope(String)
    case tooManyScopes

    public var errorDescription: String? {
        switch self {
        case .queryTooLong:
            "query must be 500 characters or fewer"
        case .unsupportedType(let type):
            "unsupported type filter: \(type)"
        case .invalidScope(let scope):
            "onlyIn entries must be absolute paths: \(scope)"
        case .tooManyScopes:
            "onlyIn supports at most 20 paths"
        }
    }
}

public enum SpotlightType: String, CaseIterable {
    case application
    case document
    case image
    case audio
    case video
    case folder
    case archive
    case source

    var predicate: String {
        switch self {
        case .application:
            "kMDItemContentType == 'com.apple.application-bundle'"
        case .document:
            "(" + [
                "kMDItemContentTypeTree == 'public.text'",
                "kMDItemContentTypeTree == 'public.composite-content'",
                "kMDItemContentType == 'com.adobe.pdf'",
                "kMDItemContentType == 'org.openxmlformats.wordprocessingml.document'",
                "kMDItemContentType == 'com.microsoft.word.doc'",
                "kMDItemContentType == 'com.apple.iwork.pages.pages'"
            ].joined(separator: " || ") + ")"
        case .image:
            "kMDItemContentTypeTree == 'public.image'"
        case .audio:
            "kMDItemContentTypeTree == 'public.audio'"
        case .video:
            "kMDItemContentTypeTree == 'public.movie'"
        case .folder:
            "kMDItemContentType == 'public.folder'"
        case .archive:
            "kMDItemContentTypeTree == 'public.archive'"
        case .source:
            "kMDItemContentTypeTree == 'public.source-code'"
        }
    }
}

public enum SpotlightQueryBuilder {
    public static let defaultLimit = 50
    public static let maxLimit = 500
    private static let maxQueryLength = 500
    private static let maxScopes = 20

    public static func build(from request: SearchRequest) throws -> BuiltSpotlightQuery {
        if request.query.count > maxQueryLength {
            throw SpotlightQueryError.queryTooLong
        }

        let scopes = try validateScopes(request.onlyIn ?? [])
        let limit = min(max(request.limit ?? defaultLimit, 1), maxLimit)
        let textPredicate = textPredicate(for: request.query)
        let typePredicate = try typePredicate(for: request.types ?? [])

        let expression: String
        if let textPredicate, let typePredicate {
            expression = "(\(textPredicate)) && (\(typePredicate))"
        } else if let textPredicate {
            expression = textPredicate
        } else {
            expression = typePredicate ?? allSupportedTypesPredicate()
        }

        return BuiltSpotlightQuery(expression: expression, scopes: scopes, limit: limit)
    }

    public static func supportedTypes() -> [String] {
        SpotlightType.allCases.map(\.rawValue)
    }

    private static func validateScopes(_ scopes: [String]) throws -> [String] {
        if scopes.count > maxScopes {
            throw SpotlightQueryError.tooManyScopes
        }

        return try scopes.map { scope in
            guard scope.hasPrefix("/") else {
                throw SpotlightQueryError.invalidScope(scope)
            }
            return scope
        }
    }

    private static func typePredicate(for types: [String]) throws -> String? {
        guard !types.isEmpty else {
            return nil
        }

        let predicates = try types.map { typeName in
            guard let type = SpotlightType(rawValue: typeName) else {
                throw SpotlightQueryError.unsupportedType(typeName)
            }
            return type.predicate
        }

        return predicates.map { "(\($0))" }.joined(separator: " || ")
    }

    private static func textPredicate(for query: String) -> String? {
        let sanitized = sanitizeSearchText(query)
        guard !sanitized.isEmpty else {
            return nil
        }

        let literal = spotlightLiteral("*\(sanitized)*")
        return [
            "kMDItemDisplayName == \(literal)",
            "kMDItemFSName == \(literal)",
            "kMDItemTextContent == \(literal)"
        ].joined(separator: " || ")
    }

    private static func allSupportedTypesPredicate() -> String {
        SpotlightType.allCases.map { "(\($0.predicate))" }.joined(separator: " || ")
    }

    private static func sanitizeSearchText(_ input: String) -> String {
        let dangerous = CharacterSet(charactersIn: "\"'\\()[]=<>!&|{};*?`")
        let scalars = input.unicodeScalars.map { scalar -> Character in
            if scalar.value == 0 || dangerous.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                return " "
            }
            return Character(scalar)
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func spotlightLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))'"
    }
}
