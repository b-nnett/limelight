import Foundation

#if canImport(AppKit)
import AppKit

enum AppIconLookup {
    static func icon(bundleIdentifier: String, fallbackSymbol: String) -> NSImage {
        if bundleIdentifier == "com.apple.finder" {
            let path = "/System/Library/CoreServices/Finder.app"
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil) ?? NSImage()
    }
}
#endif
