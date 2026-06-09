import Foundation
import Security
import SpotlightIndexCore

struct Arguments {
    var host = "127.0.0.1"
    var port: UInt16 = 8765
    var menuBar: Bool?
    var authToken = ProcessInfo.processInfo.environment["SPOTLIGHT_INDEX_AUTH_TOKEN"]
}

func parseArguments(_ values: [String]) -> Arguments {
    var arguments = Arguments()
    var iterator = values.dropFirst().makeIterator()

    while let value = iterator.next() {
        switch value {
        case "--host":
            if let host = iterator.next() {
                arguments.host = host
            }
        case "--port":
            if let portValue = iterator.next(), let port = UInt16(portValue) {
                arguments.port = port
            }
        case "--menu-bar":
            arguments.menuBar = true
        case "--no-menu-bar":
            arguments.menuBar = false
        case "--auth-token":
            arguments.authToken = iterator.next()
        default:
            break
        }
    }

    return arguments
}

#if canImport(AppKit)
let launchedFromAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
#else
let launchedFromAppBundle = false
#endif

func installedAppAuthToken() throws -> String? {
    guard launchedFromAppBundle else {
        return nil
    }
    let tokenURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Limelight/auth-token")
    if let token = try? String(contentsOf: tokenURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !token.isEmpty {
        return token
    }

    let token = try generateAuthToken()
    try FileManager.default.createDirectory(at: tokenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(
        atPath: tokenURL.path,
        contents: Data((token + "\n").utf8),
        attributes: [.posixPermissions: 0o600]
    ) else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: [NSLocalizedDescriptionKey: "failed to write local auth token"])
    }
    return token
}

func generateAuthToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "failed to generate local auth token"])
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
}

func hostIsLoopback(_ host: String) -> Bool {
    let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "localhost"
        || normalized == "::1"
        || normalized == "[::1]"
        || normalized.hasPrefix("127.")
}

var arguments = parseArguments(CommandLine.arguments)
if arguments.authToken == nil {
    do {
        arguments.authToken = try installedAppAuthToken()
    } catch {
        fputs("failed to prepare Limelight auth token: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if arguments.authToken == nil && !hostIsLoopback(arguments.host) {
    fputs("refusing to start unauthenticated Limelight server on non-loopback host \(arguments.host). Set SPOTLIGHT_INDEX_AUTH_TOKEN or pass --auth-token.\n", stderr)
    exit(1)
}

#if canImport(AppKit)
if arguments.menuBar == true || (arguments.menuBar == nil && launchedFromAppBundle) {
    runMenuBarApp(arguments: arguments)
    exit(0)
}
#endif

let server = SpotlightHTTPServer(host: arguments.host, port: arguments.port, authToken: arguments.authToken)

do {
    try server.start()
    print("spotlight-index listening on http://\(arguments.host):\(arguments.port)")
    dispatchMain()
} catch {
    fputs("failed to start spotlight-index: \(error.localizedDescription)\n", stderr)
    exit(1)
}
