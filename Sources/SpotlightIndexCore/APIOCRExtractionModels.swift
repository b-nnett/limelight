import Foundation

public struct OCRRequest: Codable, Equatable, Sendable {
    public let path: String?
    public let photoUUID: String?
    public let recognitionLevel: String?
    public let languages: [String]?
    public let includeText: Bool?

    public init(path: String? = nil, photoUUID: String? = nil, recognitionLevel: String? = nil, languages: [String]? = nil, includeText: Bool? = nil) {
        self.path = path
        self.photoUUID = photoUUID
        self.recognitionLevel = recognitionLevel
        self.languages = languages
        self.includeText = includeText
    }
}

public struct OCRResponse: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let photoUUID: String?
    public let text: String?
    public let lines: [OCRLineRecord]
}

public struct OCRLineRecord: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Float
}

public struct ExtractRequest: Codable, Equatable, Sendable {
    public let entityTypes: [String]
    public let text: String?
    public let path: String?
    public let photoUUID: String?
    public let search: DeepSearchRequest?
    public let ocr: ExtractOCRRequest?
    public let saveTo: String?
    public let includeContext: Bool?
    public let includeOCRText: Bool?

    public init(
        entityTypes: [String],
        text: String? = nil,
        path: String? = nil,
        photoUUID: String? = nil,
        search: DeepSearchRequest? = nil,
        ocr: ExtractOCRRequest? = nil,
        saveTo: String? = nil,
        includeContext: Bool? = nil,
        includeOCRText: Bool? = nil
    ) {
        self.entityTypes = entityTypes
        self.text = text
        self.path = path
        self.photoUUID = photoUUID
        self.search = search
        self.ocr = ocr
        self.saveTo = saveTo
        self.includeContext = includeContext
        self.includeOCRText = includeOCRText
    }
}

public struct ExtractOCRRequest: Codable, Equatable, Sendable {
    public let enabled: Bool?
    public let maxItems: Int?
    public let recognitionLevel: String?
    public let stopOnHighConfidence: Bool?

    public init(enabled: Bool? = nil, maxItems: Int? = nil, recognitionLevel: String? = nil, stopOnHighConfidence: Bool? = nil) {
        self.enabled = enabled
        self.maxItems = maxItems
        self.recognitionLevel = recognitionLevel
        self.stopOnHighConfidence = stopOnHighConfidence
    }
}

public struct ExtractResponse: Codable, Equatable, Sendable {
    public let entityTypes: [String]
    public let count: Int
    public let entities: [ExtractedEntityRecord]
    public let searchedResults: Int
    public let ocrResults: Int
    public let ocrDocuments: [OCRDocumentRecord]
    public let savedTo: String?
}

public struct OCRDocumentRecord: Codable, Equatable, Sendable {
    public let source: ExtractionSourceRecord?
    public let text: String
    public let lines: [OCRLineRecord]
}

public struct ExtractedEntityRecord: Codable, Equatable, Sendable {
    public let entityType: String
    public let value: String
    public let redactedValue: String
    public let confidence: Int
    public let reason: String
    public let source: ExtractionSourceRecord?
    public let context: String?
}

public struct ExtractionSourceRecord: Codable, Equatable, Sendable {
    public let source: String?
    public let entityType: String?
    public let title: String?
    public let path: String?
    public let url: String?
    public let photoUUID: String?
    public let resultID: String?
}
