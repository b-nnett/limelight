import Foundation

struct ExtractionInput {
    let text: String
    let source: ExtractionSourceRecord?
}

enum EntityExtractor {
    static let supportedEntityTypes = ["passport_number"]

    static func extract(entityTypes: [String], inputs: [ExtractionInput], includeContext: Bool) throws -> [ExtractedEntityRecord] {
        let normalizedTypes = entityTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        for entityType in normalizedTypes where !supportedEntityTypes.contains(entityType) {
            throw SpotlightSearchError.unsupportedEntityType(entityType)
        }

        var records: [ExtractedEntityRecord] = []
        for input in inputs {
            if normalizedTypes.contains("passport_number") {
                records.append(contentsOf: passportNumbers(in: input, includeContext: includeContext))
            }
        }

        var bestByKey: [String: ExtractedEntityRecord] = [:]
        for record in records {
            let sourceKey = record.source?.resultID ?? record.source?.path ?? record.source?.photoUUID ?? ""
            let key = [record.entityType, record.value, sourceKey].joined(separator: "\u{1f}")
            if let existing = bestByKey[key], existing.confidence >= record.confidence {
                continue
            }
            bestByKey[key] = record
        }

        return bestByKey.values.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.value < $1.value
        }
    }

    private static func passportNumbers(in input: ExtractionInput, includeContext: Bool) -> [ExtractedEntityRecord] {
        let text = input.text
        let lines = text.components(separatedBy: .newlines)
        var records: [ExtractedEntityRecord] = []

        let mrzLines = lines.map {
            $0.uppercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "«", with: "<")
                .replacingOccurrences(of: "‹", with: "<")
        }

        for index in mrzLines.indices {
            let line = mrzLines[index]
            guard line.count >= 30 else {
                continue
            }
            let looksLikeMRZ = line.hasPrefix("P<") || line.filter { $0 == "<" }.count >= 3
            guard looksLikeMRZ || (index > 0 && mrzLines[index - 1].hasPrefix("P<")) else {
                continue
            }

            let raw = String(line.prefix(9)).replacingOccurrences(of: "<", with: "")
            let candidate = cleanCandidate(raw)
            guard isLikelyPassportNumber(candidate) else {
                continue
            }
            records.append(record(
                value: candidate,
                confidence: 100,
                reason: "mrz",
                input: input,
                context: includeContext ? contextSnippet(around: raw, in: text) : nil
            ))
        }

        for match in regexMatches(#"(?i)(PASSPORT\s*(NO|NUMBER|NUM|N0|#)?|DOCUMENT\s*(NO|NUMBER|NUM|N0|#)?)[^\nA-Z0-9]{0,12}([A-Z0-9][A-Z0-9 <\-]{6,14}[A-Z0-9])"#, in: text) {
            guard let raw = match.last else {
                continue
            }
            let candidate = cleanCandidate(raw)
            guard isLikelyPassportNumber(candidate) else {
                continue
            }
            records.append(record(
                value: candidate,
                confidence: 90,
                reason: "passport-label",
                input: input,
                context: includeContext ? contextSnippet(around: raw, in: text) : nil
            ))
        }

        let normalized = text.uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if normalized.contains("PASSPORT") {
            for match in regexMatches(#"(?<![A-Z0-9])([A-Z0-9]{9})(?![A-Z0-9])"#, in: normalized) {
                guard let raw = match.last else {
                    continue
                }
                let candidate = cleanCandidate(raw)
                guard isLikelyPassportNumber(candidate) else {
                    continue
                }
                records.append(record(
                    value: candidate,
                    confidence: 70,
                    reason: "near-passport-text",
                    input: input,
                    context: nil
                ))
            }
        }

        return records
    }

    private static func record(value: String, confidence: Int, reason: String, input: ExtractionInput, context: String?) -> ExtractedEntityRecord {
        ExtractedEntityRecord(
            entityType: "passport_number",
            value: value,
            redactedValue: redact(value),
            confidence: confidence,
            reason: reason,
            source: input.source,
            context: context
        )
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private static func cleanCandidate(_ value: String) -> String {
        String(value.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .filter { $0.isLetter || $0.isNumber })
    }

    private static func isLikelyPassportNumber(_ value: String) -> Bool {
        guard (8...9).contains(value.count) else {
            return false
        }
        guard value.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return false
        }
        return value.filter(\.isNumber).count >= 6
    }

    private static func redact(_ value: String) -> String {
        guard value.count > 4 else {
            return String(repeating: "*", count: value.count)
        }
        return String(repeating: "*", count: max(0, value.count - 4)) + value.suffix(4)
    }

    private static func contextSnippet(around needle: String, in text: String) -> String? {
        guard let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let lower = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
