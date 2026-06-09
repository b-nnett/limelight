import Foundation

#if canImport(AppKit)
import AppKit

@MainActor
final class UpdateService {
    private let onUpdateAvailable: (GitHubReleaseChecker.Release) -> Void
    private var timer: Timer?
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let lastCheckKey = "LimelightLastUpdateCheckAt"
    private let skippedVersionKey = "LimelightSkippedUpdateVersion"

    init(onUpdateAvailable: @escaping (GitHubReleaseChecker.Release) -> Void) {
        self.onUpdateAvailable = onUpdateAvailable
    }

    func startPeriodicChecks() {
        checkIfDue()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfDue(force: true)
            }
        }
    }

    func skip(_ release: GitHubReleaseChecker.Release) {
        UserDefaults.standard.set(release.version, forKey: skippedVersionKey)
    }

    func downloadAndInstall(_ release: GitHubReleaseChecker.Release) {
        Task {
            do {
                try await UpdateInstaller.install(release)
            } catch {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func checkIfDue(force: Bool = false) {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(lastCheck) >= checkInterval else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        Task {
            do {
                let release = try await GitHubReleaseChecker.latestRelease()
                guard VersionUtils.isNewer(release.version, than: currentVersion),
                      UserDefaults.standard.string(forKey: skippedVersionKey) != release.version else {
                    return
                }
                onUpdateAvailable(release)
            } catch {
                // Silent for periodic checks.
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

private enum UpdateInstaller {
    static func install(_ release: GitHubReleaseChecker.Release) async throws {
        guard let asset = release.installableAsset else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }

        let downloadedURL = try await download(asset.url)
        guard downloadedURL.pathExtension.lowercased() == "dmg" else {
            NSWorkspace.shared.open(downloadedURL)
            return
        }
        try await installDmg(downloadedURL, release: release)
    }

    private static func download(_ url: URL) async throws -> URL {
        let (temporaryURL, _) = try await URLSession.shared.download(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Limelight-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension.isEmpty ? "download" : url.pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func installDmg(_ dmgURL: URL, release: GitHubReleaseChecker.Release) async throws {
        try verifyDownloadedDiskImage(dmgURL)
        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LimelightUpdate-\(UUID().uuidString)")
        let mountURL = workDirectory.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", arguments: ["attach", "-readonly", "-nobrowse", "-mountpoint", mountURL.path, dmgURL.path])

        guard let mountedAppURL = findApp(in: mountURL) else {
            try? run("/usr/bin/hdiutil", arguments: ["detach", mountURL.path])
            throw NSError(domain: "LimelightUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloaded update did not contain an app bundle."])
        }

        let appURL = workDirectory.appendingPathComponent(mountedAppURL.lastPathComponent)
        try run("/usr/bin/ditto", arguments: [mountedAppURL.path, appURL.path])
        try run("/usr/bin/hdiutil", arguments: ["detach", mountURL.path])
        try await installApp(appURL, workDirectory: workDirectory, release: release)
    }

    private static func installApp(_ appURL: URL, workDirectory: URL, release: GitHubReleaseChecker.Release) async throws {
        try verifyDownloadedApp(appURL, release: release)
        let currentAppURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let executableName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "Limelight"
        let executableURL = currentAppURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName)
        let scriptURL = workDirectory.appendingPathComponent("install.sh")
        let script = """
        #!/bin/zsh
        sleep 1
        /usr/bin/codesign --verify --deep --strict --verbose=2 "\(appURL.path)" || exit 1
        /usr/sbin/spctl --assess --type execute --verbose "\(appURL.path)" || exit 1
        rm -rf "\(currentAppURL.path)"
        /usr/bin/ditto "\(appURL.path)" "\(currentAppURL.path)"
        "\(executableURL.path)" --host 127.0.0.1 --port 8765 &
        rm -rf "\(workDirectory.path)"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try run("/bin/zsh", arguments: [scriptURL.path], wait: false)
        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private static func verifyDownloadedDiskImage(_ dmgURL: URL) throws {
        try run("/usr/bin/codesign", arguments: ["--verify", "--strict", "--verbose=2", dmgURL.path])
        try run("/usr/sbin/spctl", arguments: ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose", dmgURL.path])
        try run("/usr/bin/xcrun", arguments: ["stapler", "validate", dmgURL.path])
    }

    private static func verifyDownloadedApp(_ appURL: URL, release: GitHubReleaseChecker.Release) throws {
        let expectedBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.bennett.limelight"
        guard let candidateBundle = Bundle(url: appURL),
              candidateBundle.bundleIdentifier == expectedBundleIdentifier else {
            throw NSError(domain: "LimelightUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Downloaded update bundle identifier does not match Limelight."])
        }
        guard let expectedTeamIdentifier = Bundle.main.object(forInfoDictionaryKey: "LimelightExpectedTeamIdentifier") as? String,
              !expectedTeamIdentifier.isEmpty else {
            throw NSError(domain: "LimelightUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: "This Limelight build does not include self-update signing metadata."])
        }
        let candidateVersion = candidateBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let expectedVersion = VersionUtils.normalized(release.version)
        guard VersionUtils.normalized(candidateVersion) == expectedVersion else {
            throw NSError(domain: "LimelightUpdate", code: 4, userInfo: [NSLocalizedDescriptionKey: "Downloaded update version \(candidateVersion) does not match release \(release.version)."])
        }
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard VersionUtils.compare(candidateVersion, currentVersion) == .orderedDescending else {
            throw NSError(domain: "LimelightUpdate", code: 5, userInfo: [NSLocalizedDescriptionKey: "Downloaded update is not newer than the current Limelight version."])
        }

        try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
        try run("/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--verbose", appURL.path])

        let signature = try runAndCapture("/usr/bin/codesign", arguments: ["-dv", "--verbose=4", appURL.path])
        guard signature.contains("TeamIdentifier=\(expectedTeamIdentifier)") else {
            throw NSError(domain: "LimelightUpdate", code: 6, userInfo: [NSLocalizedDescriptionKey: "Downloaded update is not signed by the expected Limelight team."])
        }
    }

    private static func findApp(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return enumerator.compactMap { $0 as? URL }.first { $0.pathExtension == "app" }
    }

    private static func run(_ executable: String, arguments: [String], wait: Bool = true) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        if wait {
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw NSError(domain: "LimelightUpdate", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(executable) failed with status \(process.terminationStatus)."])
            }
        }
    }

    private static func runAndCapture(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(domain: "LimelightUpdate", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(executable) failed with status \(process.terminationStatus)."])
        }
        return output
    }
}

enum GitHubReleaseChecker {
    struct Release {
        let version: String
        let htmlURL: URL
        let assets: [Asset]

        var installableAsset: Asset? {
            let dmgAssets = assets.filter { $0.url.pathExtension.lowercased() == "dmg" }
            return dmgAssets.first { $0.name.localizedCaseInsensitiveContains(VersionUtils.normalized(version)) } ?? dmgAssets.first
        }
    }

    struct Asset {
        let name: String
        let url: URL
    }

    static func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/b-nnett/limelight/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("Limelight", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "LimelightUpdates", code: 1, userInfo: [NSLocalizedDescriptionKey: "No GitHub release is available yet."])
        }
        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        return Release(
            version: payload.tagName,
            htmlURL: payload.htmlURL,
            assets: payload.assets.map { Asset(name: $0.name, url: $0.downloadURL) }
        )
    }

    private struct ReleasePayload: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [AssetPayload]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct AssetPayload: Decodable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }
}

#endif
