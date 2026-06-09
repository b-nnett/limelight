import CryptoKit
import Foundation

public enum SpotlightRecordNormalizer {
    public static func normalize(_ reader: SpotlightMetadataReading) -> SpotlightRecord {
        let path = reader.path
            ?? stringValue(reader.value(for: SpotlightAttributes.path))
            ?? ""
        let contentType = stringValue(reader.value(for: SpotlightAttributes.contentType))

        var metadata: [String: JSONValue] = [:]
        for key in SpotlightAttributes.rawMetadataKeys {
            if key == "kMDItemTextContent" {
                continue
            }
            metadata[key] = JSONValue.convert(reader.value(for: key))
        }

        return SpotlightRecord(
            id: stableID(path: path, contentType: contentType),
            path: path,
            displayName: stringValue(reader.value(for: SpotlightAttributes.displayName)),
            contentType: contentType,
            kind: stringValue(reader.value(for: SpotlightAttributes.kind)),
            bundleIdentifier: stringValue(reader.value(for: SpotlightAttributes.bundleIdentifier)),
            createdAt: dateValue(reader.value(for: SpotlightAttributes.createdAt)),
            modifiedAt: dateValue(reader.value(for: SpotlightAttributes.modifiedAt)),
            authors: stringArrayValue(reader.value(for: SpotlightAttributes.authors)),
            sizeBytes: int64Value(reader.value(for: SpotlightAttributes.sizeBytes)),
            metadata: metadata
        )
    }

    public static func stableID(path: String, contentType: String?) -> String {
        let input = "\(path)\u{1f}\(contentType ?? "")"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func stringArrayValue(_ value: Any?) -> [String]? {
        if let values = value as? [String] {
            return values
        }
        if let value = value as? String {
            return [value]
        }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        value as? Date
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        return nil
    }
}

extension SpotlightRecord {
    var itemRecord: ItemRecord {
        ItemRecord(
            id: id,
            source: SearchSource.files.rawValue,
            entityType: "file",
            title: displayName ?? URL(fileURLWithPath: path).lastPathComponent,
            subtitle: kind ?? contentType,
            path: path,
            displayName: displayName,
            contentType: contentType,
            kind: kind,
            bundleIdentifier: bundleIdentifier,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            authors: authors,
            sizeBytes: sizeBytes,
            metadata: metadata
        )
    }
}
