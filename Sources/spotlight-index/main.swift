import Foundation
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

let arguments = parseArguments(CommandLine.arguments)

#if canImport(AppKit)
let launchedFromAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
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
