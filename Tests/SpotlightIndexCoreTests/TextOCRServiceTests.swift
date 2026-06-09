import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SpotlightIndexCore

final class TextOCRServiceTests: XCTestCase {
    func testPreflightRejectsOversizedEncodedFileBeforeDecode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        try Data(repeating: 0, count: 128).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let limits = TextOCRImageLimits(maxFileBytes: 16, maxSourceDimension: 1_000, maxSourcePixels: 1_000_000, maxVisionDimension: 128)

        XCTAssertThrowsError(try TextOCRService.preflightImage(path: url.path, limits: limits)) { error in
            guard case SpotlightSearchError.ocrFileTooLarge = error else {
                return XCTFail("expected ocrFileTooLarge, got \(error)")
            }
        }
    }

    func testPreflightRejectsOversizedPixelDimensions() throws {
        let url = try makePNG(width: 32, height: 16)
        defer { try? FileManager.default.removeItem(at: url) }

        let limits = TextOCRImageLimits(maxFileBytes: 1_000_000, maxSourceDimension: 1_000, maxSourcePixels: 100, maxVisionDimension: 128)

        XCTAssertThrowsError(try TextOCRService.preflightImage(path: url.path, limits: limits)) { error in
            guard case SpotlightSearchError.ocrImageTooLarge = error else {
                return XCTFail("expected ocrImageTooLarge, got \(error)")
            }
        }
    }

    func testDownsampledImageRespectsVisionDimensionLimit() throws {
        let url = try makePNG(width: 32, height: 16)
        defer { try? FileManager.default.removeItem(at: url) }

        let limits = TextOCRImageLimits(maxFileBytes: 1_000_000, maxSourceDimension: 1_000, maxSourcePixels: 1_000_000, maxVisionDimension: 8)
        let image = try TextOCRService.downsampledImage(path: url.path, limits: limits)

        XCTAssertLessThanOrEqual(max(image.width, image.height), 8)
    }

    func testPreflightRejectsInvalidImage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        try "not an image".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try TextOCRService.preflightImage(path: url.path)) { error in
            guard case SpotlightSearchError.unsupportedOCRPath(url.path) = error else {
                return XCTFail("expected unsupportedOCRPath, got \(error)")
            }
        }
    }

    func testHTTPStatusMapsOversizedOCRErrorsToPayloadTooLarge() {
        XCTAssertEqual(
            httpStatus(for: SpotlightSearchError.ocrFileTooLarge(path: "/tmp/large.png", bytes: 2, limit: 1)),
            413
        )
        XCTAssertEqual(
            httpStatus(for: SpotlightSearchError.ocrImageTooLarge(path: "/tmp/large.png", width: 10, height: 10, maxPixels: 50, maxDimension: 10)),
            413
        )
        XCTAssertEqual(httpStatus(for: SpotlightSearchError.unsupportedOCRPath("/tmp/not-image")), 400)
    }

    private func makePNG(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "TextOCRServiceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to create PNG fixture"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "TextOCRServiceTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to write PNG fixture"])
        }
        return url
    }
}
