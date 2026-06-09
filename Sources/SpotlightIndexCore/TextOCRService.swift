import AppKit
import Foundation
import ImageIO
import Vision

struct TextOCRImageLimits {
    let maxFileBytes: Int64
    let maxSourceDimension: Int
    let maxSourcePixels: Int
    let maxVisionDimension: Int

    static let production = TextOCRImageLimits(
        maxFileBytes: 50 * 1024 * 1024,
        maxSourceDimension: 30_000,
        maxSourcePixels: 120_000_000,
        maxVisionDimension: 4_096
    )
}

struct TextOCRImageInfo: Equatable {
    let path: String
    let width: Int
    let height: Int
    let fileBytes: Int64
}

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
        let cgImage = try downsampledImage(path: path, limits: .production)

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

    static func preflightImage(path: String, limits: TextOCRImageLimits = .production) throws -> TextOCRImageInfo {
        let url = URL(fileURLWithPath: path)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }
        guard values.isRegularFile == true else {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }
        let fileBytes = Int64(values.fileSize ?? 0)
        guard fileBytes <= limits.maxFileBytes else {
            throw SpotlightSearchError.ocrFileTooLarge(path: path, bytes: fileBytes, limit: limits.maxFileBytes)
        }

        guard let source = imageSource(path: path) else {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }

        guard width <= limits.maxSourceDimension,
              height <= limits.maxSourceDimension,
              width <= limits.maxSourcePixels / max(height, 1) else {
            throw SpotlightSearchError.ocrImageTooLarge(
                path: path,
                width: width,
                height: height,
                maxPixels: limits.maxSourcePixels,
                maxDimension: limits.maxSourceDimension
            )
        }

        return TextOCRImageInfo(path: path, width: width, height: height, fileBytes: fileBytes)
    }

    static func downsampledImage(path: String, limits: TextOCRImageLimits = .production) throws -> CGImage {
        _ = try preflightImage(path: path, limits: limits)
        guard let source = imageSource(path: path) else {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limits.maxVisionDimension,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SpotlightSearchError.unsupportedOCRPath(path)
        }
        return image
    }

    private static func imageSource(path: String) -> CGImageSource? {
        CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary)
    }
}
