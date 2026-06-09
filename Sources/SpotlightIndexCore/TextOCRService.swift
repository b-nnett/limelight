import AppKit
import Foundation
import Vision

enum TextOCRService {
    static func recognize(_ request: OCRRequest) throws -> OCRResponse {
        let resolved = try resolveSource(path: request.path, photoUUID: request.photoUUID)
        let lines = try recognizeLines(
            path: resolved.path,
            recognitionLevel: request.recognitionLevel,
            languages: request.languages
        )
        return OCRResponse(
            sourcePath: resolved.path,
            photoUUID: resolved.photoUUID,
            text: request.includeText == false ? nil : lines.map(\.text).joined(separator: "\n"),
            lines: lines
        )
    }

    static func recognize(path: String, photoUUID: String? = nil, recognitionLevel: String? = nil) throws -> OCRResponse {
        let lines = try recognizeLines(path: path, recognitionLevel: recognitionLevel, languages: nil)
        return OCRResponse(
            sourcePath: path,
            photoUUID: photoUUID,
            text: lines.map(\.text).joined(separator: "\n"),
            lines: lines
        )
    }

    private static func resolveSource(path: String?, photoUUID: String?) throws -> (path: String, photoUUID: String?) {
        if let photoUUID, !photoUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let file = try PhotosAssetResolver().thumbnail(uuid: photoUUID)
            return (file.path, photoUUID)
        }

        guard let path, path.hasPrefix("/") else {
            throw SpotlightSearchError.invalidPath(path ?? "")
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw SpotlightSearchError.unreadablePath(path)
        }
        return (path, nil)
    }

    private static func recognizeLines(path: String, recognitionLevel: String?, languages: [String]?) throws -> [OCRLineRecord] {
        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel == "fast" ? .fast : .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        if let languages, !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return OCRLineRecord(text: text, confidence: candidate.confidence)
        }
    }
}
