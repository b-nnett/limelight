import AppKit
import CoreServices
import Foundation

public final class SpotlightSearchService: @unchecked Sendable {
    private let providers: [SearchSource: SearchProvider]
    private let itemOpener: ItemOpening

    public convenience init() {
        self.init(providers: [
            SpotlightFileProvider(),
            PhotosSQLiteProvider(),
            ContactsProvider(),
            LocalCalendarProvider(),
            LocalRemindersProvider(),
            NotesSQLiteProvider(),
            MailSQLiteProvider(),
            MessagesSQLiteProvider(),
            SafariHistoryProvider()
        ])
    }

    init(providers: [SearchProvider], itemOpener: ItemOpening = WorkspaceItemOpener()) {
        let defaultProviders: [SearchProvider] = providers
        self.providers = Dictionary(uniqueKeysWithValues: defaultProviders.map { ($0.source, $0) })
        self.itemOpener = itemOpener
    }

    public func health() -> HealthResponse {
        HealthResponse(
            status: "ok",
            spotlightIndexingEnabled: Self.spotlightIndexingAppearsEnabled(),
            providers: SearchSource.allCases.map(\.rawValue)
        )
    }

    public static func warmProviderIndexes() {
        MailSQLiteProvider.warmPathIndexInBackground()
    }

    public func schema() -> SchemaResponse {
        SchemaResponse(
            normalizedFields: SpotlightAttributes.normalizedFields,
            supportedTypes: SpotlightQueryBuilder.supportedTypes(),
            supportedSources: SearchSource.allCases.map(\.rawValue),
            metadataAttributes: SpotlightAttributes.rawMetadataKeys,
            providerFields: Dictionary(uniqueKeysWithValues: ProviderCatalog.schemas.map { ($0.key.rawValue, $0.value) })
        )
    }

    public func providerReadiness() -> ProvidersResponse {
        ProvidersResponse(providers: ProviderReadinessDetector.records())
    }

    public func capabilities() -> CapabilitiesResponse {
        let readiness = providerReadiness()
        return CapabilitiesResponse(
            generatedAt: Date(),
            sources: ProviderCatalog.capabilities(readiness: readiness)
        )
    }

    public func requestPermissions(_ request: PermissionRequest) throws -> PermissionResponse {
        try PermissionBootstrapper.request(request)
    }

    public func deepSearch(_ request: DeepSearchRequest) throws -> DeepSearchResponse {
        let queries = request.queries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let regexes = request.regexes ?? []
        let limit = min(max(request.limit ?? 50, 1), 500)
        let limitPerQuery = min(max(request.limitPerQuery ?? 50, 1), 500)

        var merged: [String: (record: SearchResultRecord, queries: Set<String>, regexes: Set<String>, score: Int)] = [:]
        var providerStatuses: [String: ProviderSearchStatus] = [:]

        for query in queries {
            let response = try search(SearchRequest(
                query: query,
                types: request.types,
                sources: request.sources,
                onlyIn: request.onlyIn,
                limit: limitPerQuery
            ))
            for status in response.providers {
                let key = "\(status.source):\(status.status):\(status.error ?? "")"
                providerStatuses[key] = status
            }
            for result in response.results {
                let key = result.id
                var entry = merged[key] ?? (record: result, queries: [], regexes: [], score: 0)
                entry.queries.insert(query)
                entry.score += score(result: result, query: query)
                merged[key] = entry
            }
        }

        let compiledRegexes = try regexes.map { pattern in
            (pattern, try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
        }
        if !compiledRegexes.isEmpty {
            for key in Array(merged.keys) {
                guard var entry = merged[key] else {
                    continue
                }
                let haystack = searchableText(for: entry.record)
                for (pattern, regex) in compiledRegexes where regex.firstMatch(in: haystack, range: NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)) != nil {
                    entry.regexes.insert(pattern)
                    entry.score += 20
                }
                merged[key] = entry
            }
        }

        let records = merged.values
            .filter { compiledRegexes.isEmpty || !$0.regexes.isEmpty }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.record.title < $1.record.title
            }
            .prefix(limit)
            .map {
                DeepSearchResultRecord(
                    result: $0.record,
                    matchedQueries: Array($0.queries).sorted(),
                    matchedRegexes: Array($0.regexes).sorted(),
                    score: $0.score
                )
            }

        return DeepSearchResponse(
            queries: queries,
            regexes: regexes,
            count: records.count,
            limit: limit,
            results: Array(records),
            providers: Array(providerStatuses.values).sorted { $0.source < $1.source }
        )
    }

    public func ocr(_ request: OCRRequest) throws -> OCRResponse {
        try TextOCRService.recognize(request)
    }

    public func extract(_ request: ExtractRequest) throws -> ExtractResponse {
        let entityTypes = request.entityTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        var inputs: [ExtractionInput] = []
        var ocrDocuments: [OCRDocumentRecord] = []
        var searchedResults = 0
        var ocrResults = 0
        let includeOCRText = request.includeOCRText != false

        if let text = request.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputs.append(ExtractionInput(text: text, source: nil))
        }

        if request.path != nil || request.photoUUID != nil {
            let ocrResponse = try ocr(OCRRequest(
                path: request.path,
                photoUUID: request.photoUUID,
                recognitionLevel: request.ocr?.recognitionLevel,
                includeText: true
            ))
            let source = ExtractionSourceRecord(
                source: nil,
                entityType: "image",
                title: nil,
                path: ocrResponse.sourcePath,
                url: nil,
                photoUUID: ocrResponse.photoUUID,
                resultID: nil
            )
            let text = ocrResponse.text ?? ocrResponse.lines.map(\.text).joined(separator: "\n")
            inputs.append(ExtractionInput(text: text, source: source))
            if includeOCRText {
                ocrDocuments.append(OCRDocumentRecord(source: source, text: text, lines: ocrResponse.lines))
            }
            ocrResults += 1
        }

        if let searchRequest = request.search {
            let searchResponse = try deepSearch(searchRequest)
            searchedResults = searchResponse.results.count
            let ocrEnabled = request.ocr?.enabled ?? true
            let maxOCRItems = min(max(request.ocr?.maxItems ?? 12, 0), 50)
            let stopOnHighConfidence = request.ocr?.stopOnHighConfidence ?? true
            var scannedOCRItems = 0

            for deepResult in searchResponse.results {
                let result = deepResult.result
                let source = extractionSource(for: result)
                let metadataInput = ExtractionInput(text: searchableText(for: result), source: source)
                inputs.append(metadataInput)
                if stopOnHighConfidence, try hasHighConfidenceEntity(in: [metadataInput], entityTypes: entityTypes, includeContext: request.includeContext == true) {
                    break
                }

                guard ocrEnabled, scannedOCRItems < maxOCRItems, shouldOCR(result) else {
                    continue
                }
                guard let path = result.path else {
                    continue
                }
                do {
                    let response = try TextOCRService.recognize(
                        path: path,
                        photoUUID: source.photoUUID,
                        recognitionLevel: request.ocr?.recognitionLevel
                    )
                    let ocrInput = ExtractionInput(text: response.text ?? response.lines.map(\.text).joined(separator: "\n"), source: source)
                    inputs.append(ocrInput)
                    if includeOCRText {
                        ocrDocuments.append(OCRDocumentRecord(source: source, text: ocrInput.text, lines: response.lines))
                    }
                    scannedOCRItems += 1
                    ocrResults += 1
                    if stopOnHighConfidence, try hasHighConfidenceEntity(in: [ocrInput], entityTypes: entityTypes, includeContext: request.includeContext == true) {
                        break
                    }
                } catch {
                    continue
                }
            }
        }

        let entities = try EntityExtractor.extract(
            entityTypes: entityTypes,
            inputs: inputs,
            includeContext: request.includeContext == true
        )
        let savedTo = try saveIfNeeded(entities: entities, request: request)

        return ExtractResponse(
            entityTypes: entityTypes,
            count: entities.count,
            entities: entities,
            searchedResults: searchedResults,
            ocrResults: ocrResults,
            ocrDocuments: ocrDocuments,
            savedTo: savedTo
        )
    }

    public func photoThumbnail(uuid: String) throws -> PhotoAssetFile {
        guard !uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpotlightSearchError.invalidAssetID(uuid)
        }
        return try PhotosAssetResolver().thumbnail(uuid: uuid)
    }

    public func search(_ request: SearchRequest) throws -> SearchResponse {
        let built = try SpotlightQueryBuilder.build(from: request)
        var unifiedResults: [SearchResultRecord] = []
        var statuses: [ProviderSearchStatus] = []
        let sources = try requestedSources(request.sources)
        let context = ProviderSearchContext(query: request.query, types: request.types ?? [], onlyIn: built.scopes, limit: built.limit)

        for source in sources {
            guard let provider = providers[source] else {
                statuses.append(ProviderSearchStatus(source: source.rawValue, status: "unavailable", count: 0, error: "provider is not registered"))
                continue
            }

            do {
                let providerResults = try provider.search(context)
                unifiedResults.append(contentsOf: providerResults)
                statuses.append(ProviderSearchStatus(source: source.rawValue, status: "ok", count: providerResults.count, error: nil))
            } catch {
                statuses.append(ProviderSearchStatus(source: source.rawValue, status: "unavailable", count: 0, error: error.localizedDescription))
            }
        }

        let capped = Array(unifiedResults.prefix(built.limit))
        return SearchResponse(query: built.expression, count: capped.count, limit: built.limit, results: capped, providers: statuses)
    }

    public func item(at path: String) throws -> ItemResponse {
        guard path.hasPrefix("/") else {
            throw SpotlightSearchError.invalidPath(path)
        }

        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            throw SpotlightMetadataError.itemNotFound(path)
        }

        let reader = MDItemMetadataReader(item: item, path: path)
        return ItemResponse(item: ItemRecord(file: SpotlightRecordNormalizer.normalize(reader)))
    }

    public func item(source sourceName: String, id: String) throws -> ItemResponse {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw SpotlightSearchError.invalidItemID(id)
        }
        let source = try requestedSource(sourceName)
        guard let provider = providers[source] as? ItemProvider else {
            throw SpotlightSearchError.unsupportedItemSource(source.rawValue)
        }
        return ItemResponse(item: try provider.item(id: trimmedID))
    }

    public func open(_ request: OpenItemRequest) throws -> OpenItemResponse {
        if let urlString = request.url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
            let url = try validatedURL(urlString)
            try itemOpener.open(url)
            return OpenItemResponse(opened: true, target: url.absoluteString, item: nil)
        }

        if let path = request.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            guard path.hasPrefix("/") else {
                throw SpotlightSearchError.invalidPath(path)
            }
            let url = URL(fileURLWithPath: path)
            try itemOpener.open(url)
            return OpenItemResponse(opened: true, target: path, item: nil)
        }

        if let source = request.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty,
           let id = request.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            let item = try item(source: source, id: id).item
            let url = try openURL(for: item)
            try itemOpener.open(url)
            return OpenItemResponse(opened: true, target: url.absoluteString, item: item)
        }

        throw SpotlightSearchError.missingOpenTarget
    }

    static func spotlightIndexingAppearsEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        process.arguments = ["-s", "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.localizedCaseInsensitiveContains("Indexing enabled")
    }

    private func requestedSources(_ sourceNames: [String]?) throws -> [SearchSource] {
        let names = sourceNames ?? SearchSource.allCases.map(\.rawValue)
        var sources: [SearchSource] = []
        for name in names {
            let source = try requestedSource(name)
            if !sources.contains(source) {
                sources.append(source)
            }
        }
        return sources
    }

    private func requestedSource(_ sourceName: String) throws -> SearchSource {
        guard let source = SearchSource(rawValue: sourceName) else {
            throw SpotlightSearchError.unsupportedSource(sourceName)
        }
        return source
    }

    private func openURL(for item: ItemRecord) throws -> URL {
        if let urlString = item.url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
            return try validatedURL(urlString)
        }
        if let path = item.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty, path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        throw SpotlightSearchError.unopenableItem(item.id)
    }

    private func validatedURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString), url.scheme?.isEmpty == false else {
            throw SpotlightSearchError.invalidURL(urlString)
        }
        return url
    }

    private func score(result: SearchResultRecord, query: String) -> Int {
        var score = 10
        if SearchUtilities.contains(result.title, query) {
            score += 50
        }
        if SearchUtilities.contains(result.subtitle, query) {
            score += 25
        }
        if SearchUtilities.contains(result.path, query) {
            score += 15
        }
        if result.metadata["matchReason"] != nil {
            score += 10
        }
        return score
    }

    private func searchableText(for result: SearchResultRecord) -> String {
        var parts = [
            result.title,
            result.subtitle,
            result.path,
            result.url,
            result.contentType
        ].compactMap { $0 }
        parts.append(contentsOf: result.authors ?? [])
        parts.append(contentsOf: result.metadata.map { "\($0.key): \(Self.jsonText($0.value))" })
        return parts.joined(separator: "\n")
    }

    private func extractionSource(for result: SearchResultRecord) -> ExtractionSourceRecord {
        ExtractionSourceRecord(
            source: result.source,
            entityType: result.entityType,
            title: result.title,
            path: result.path,
            url: result.url,
            photoUUID: result.metadata["uuid"].flatMap(Self.jsonString),
            resultID: result.id
        )
    }

    private func shouldOCR(_ result: SearchResultRecord) -> Bool {
        if result.source == SearchSource.photos.rawValue {
            return result.path != nil
        }
        if let contentType = result.contentType?.lowercased() {
            return contentType.contains("image") || contentType.contains("jpeg") || contentType.contains("png") || contentType.contains("heic")
        }
        let ext = URL(fileURLWithPath: result.path ?? "").pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "tiff", "tif"].contains(ext)
    }

    private func saveIfNeeded(entities: [ExtractedEntityRecord], request: ExtractRequest) throws -> String? {
        guard let saveTo = request.saveTo, !saveTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let outputPath = expandOutputPath(saveTo)
        guard outputPath.hasPrefix("/") else {
            throw SpotlightSearchError.invalidOutputPath(saveTo)
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = savedEntityReport(entities)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try body.write(to: outputURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
        return outputURL.path
    }

    private func hasHighConfidenceEntity(in inputs: [ExtractionInput], entityTypes: [String], includeContext: Bool) throws -> Bool {
        try EntityExtractor.extract(entityTypes: entityTypes, inputs: inputs, includeContext: includeContext).contains { $0.confidence >= 100 }
    }

    private func savedEntityReport(_ entities: [ExtractedEntityRecord]) -> String {
        guard let best = entities.first else {
            return "No entities found.\n"
        }

        var lines = [
            "\(best.entityType): \(best.value)",
            "Confidence: \(best.confidence)",
            "Reason: \(best.reason)"
        ]
        if let source = best.source {
            if let title = source.title {
                lines.append("Source title: \(title)")
            }
            if let path = source.path {
                lines.append("Source path: \(path)")
            }
            if let uuid = source.photoUUID {
                lines.append("Source uuid: \(uuid)")
            }
        }

        let alternatives = entities.dropFirst().prefix(10).map {
            "- \($0.entityType): \($0.redactedValue) confidence=\($0.confidence) reason=\($0.reason) source=\($0.source?.title ?? "")"
        }
        lines.append("")
        lines.append("Other redacted candidates:")
        lines.append(alternatives.isEmpty ? "None" : alternatives.joined(separator: "\n"))
        return lines.joined(separator: "\n") + "\n"
    }

    private func expandOutputPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private static func jsonText(_ value: JSONValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .array(let values):
            return values.map(jsonText).joined(separator: " ")
        case .object(let object):
            return object.map { "\($0.key): \(jsonText($0.value))" }.joined(separator: " ")
        case .null:
            return ""
        }
    }

    private static func jsonString(_ value: JSONValue) -> String? {
        if case .string(let string) = value {
            return string
        }
        return nil
    }
}

public enum SpotlightSearchError: Error, LocalizedError {
    case queryCreationFailed
    case queryExecutionFailed
    case invalidPath(String)
    case invalidItemID(String)
    case invalidAssetID(String)
    case unsupportedSource(String)
    case unsupportedItemSource(String)
    case unreadablePath(String)
    case unsupportedOCRPath(String)
    case unsupportedEntityType(String)
    case invalidOutputPath(String)
    case invalidURL(String)
    case missingOpenTarget
    case unopenableItem(String)
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .queryCreationFailed:
            "failed to create Spotlight query"
        case .queryExecutionFailed:
            "failed to execute Spotlight query"
        case .invalidPath(let path):
            "path must be absolute: \(path)"
        case .invalidItemID(let id):
            "item id is required: \(id)"
        case .invalidAssetID(let id):
            "asset id is required: \(id)"
        case .unsupportedSource(let source):
            "unsupported source: \(source)"
        case .unsupportedItemSource(let source):
            "source does not support item loading: \(source)"
        case .unreadablePath(let path):
            "path is not readable: \(path)"
        case .unsupportedOCRPath(let path):
            "path is not an OCR-readable image: \(path)"
        case .unsupportedEntityType(let entityType):
            "unsupported entity type: \(entityType)"
        case .invalidOutputPath(let path):
            "output path must be absolute: \(path)"
        case .invalidURL(let url):
            "url is invalid: \(url)"
        case .missingOpenTarget:
            "open request requires url, path, or source and id"
        case .unopenableItem(let id):
            "item has no openable url or path: \(id)"
        case .openFailed(let target):
            "failed to open item: \(target)"
        }
    }
}

protocol ItemOpening: Sendable {
    func open(_ url: URL) throws
}

struct WorkspaceItemOpener: ItemOpening {
    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw SpotlightSearchError.openFailed(url.absoluteString)
        }
    }
}
