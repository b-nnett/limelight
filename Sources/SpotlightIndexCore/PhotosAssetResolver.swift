import Foundation

struct PhotosAssetResolver {
    let libraryURL: URL

    init(libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Photos Library.photoslibrary")) {
        self.libraryURL = libraryURL
    }

    func thumbnail(uuid: String) throws -> PhotoAssetFile {
        guard let path = resolveDerivativePath(uuid: uuid) else {
            throw ProviderError.unavailable("Photos thumbnail is not available for asset \(uuid)")
        }
        return try photoAssetFile(path: path, fallbackContentType: "image/jpeg")
    }

    func bestAssetPath(uuid: String, filename: String, directory: String? = nil) -> String? {
        resolveOriginalPath(filename: filename, directory: directory) ?? resolveDerivativePath(uuid: uuid)
    }

    func mediaKind(contentType: String?, filename: String) -> String {
        let loweredType = contentType?.lowercased() ?? ""
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if loweredType.contains("movie") || loweredType.contains("video") || loweredType.contains("quicktime") || ["mov", "mp4", "m4v"].contains(ext) {
            return "video"
        }
        if loweredType.contains("live-photo") {
            return "live-photo"
        }
        if ext == "png" {
            return "screenshot-or-image"
        }
        return "image"
    }

    private func resolveOriginalPath(filename: String, directory: String?) -> String? {
        if let directory = directory?.trimmingCharacters(in: .whitespacesAndNewlines), !directory.isEmpty {
            let path = libraryURL.appendingPathComponent("originals/\(directory)/\(filename)").path
            if let safe = safeExistingPath(path) {
                return safe
            }
        }
        guard let first = filename.first else { return nil }
        let path = libraryURL.appendingPathComponent("originals/\(first)/\(filename)").path
        return safeExistingPath(path)
    }

    private func resolveDerivativePath(uuid: String) -> String? {
        guard let first = uuid.first else { return nil }
        let folders = [
            libraryURL.appendingPathComponent("resources/derivatives/masters/\(first)"),
            libraryURL.appendingPathComponent("resources/derivatives/\(first)"),
            libraryURL.appendingPathComponent("resources/renders/\(first)")
        ]

        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                continue
            }
            if let match = files.first(where: { isDerivativeMatch($0, uuid: uuid) }),
               let path = safeExistingPath(match.path) {
                return path
            }
        }
        for root in [
            libraryURL.appendingPathComponent("resources/derivatives"),
            libraryURL.appendingPathComponent("resources/renders")
        ] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            var inspected = 0
            for case let url as URL in enumerator {
                inspected += 1
                if inspected > 20_000 {
                    break
                }
                guard isDerivativeMatch(url, uuid: uuid),
                      let path = safeExistingPath(url.path) else {
                    continue
                }
                return path
            }
        }
        return nil
    }

    private func isDerivativeMatch(_ url: URL, uuid: String) -> Bool {
        url.lastPathComponent.hasPrefix(uuid)
            && ["jpeg", "jpg", "png", "heic", "tif", "tiff"].contains(url.pathExtension.lowercased())
    }

    private func photoAssetFile(path: String, fallbackContentType: String) throws -> PhotoAssetFile {
        guard let safePath = safeExistingPath(path), FileManager.default.isReadableFile(atPath: safePath) else {
            throw ProviderError.unavailable("Photos asset file is not readable")
        }
        return PhotoAssetFile(path: safePath, contentType: contentType(for: safePath) ?? fallbackContentType)
    }

    private func safeExistingPath(_ path: String) -> String? {
        let standardizedLibrary = libraryURL.standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardizedPath == standardizedLibrary || standardizedPath.hasPrefix("\(standardizedLibrary)/") else {
            return nil
        }
        return FileManager.default.fileExists(atPath: standardizedPath) ? standardizedPath : nil
    }

    private func contentType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        default:
            return nil
        }
    }
}

public struct PhotoAssetFile: Equatable, Sendable {
    public let path: String
    public let contentType: String
}
