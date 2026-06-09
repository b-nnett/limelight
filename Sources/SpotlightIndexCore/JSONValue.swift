import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public static func convert(_ value: Any?) -> JSONValue {
        guard let value else {
            return .null
        }

        if let value = value as? String {
            return .string(value)
        }

        if let value = value as? Date {
            return .string(ISO8601DateFormatter().string(from: value))
        }

        if let value = value as? URL {
            return .string(value.absoluteString)
        }

        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        }

        if let value = value as? [Any] {
            return .array(value.map { JSONValue.convert($0) })
        }

        if let value = value as? [String: Any] {
            return .object(value.mapValues { JSONValue.convert($0) })
        }

        return .string(String(describing: value))
    }
}
