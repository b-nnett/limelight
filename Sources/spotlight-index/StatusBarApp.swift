import Foundation
import SpotlightIndexCore

#if canImport(AppKit)
import AppKit

@MainActor
final class SpotlightIndexAppDelegate: NSObject, NSApplicationDelegate {
    private static let reopenPermissionsOnNextLaunchKey = "LimelightReopenPermissionsOnNextLaunch"
    private let arguments: Arguments
    private var server: SpotlightHTTPServer?
    private var statusItem: NSStatusItem?
    private var recentSearches: [RecentSearch] = []
    private var permissionsWindow: PermissionsWindowController?
    private var recentSearchesWindow: RecentSearchesWindowController?
    private var settingsWindow: SettingsWindowController?
    private var lastProviderStatus: ProvidersResponse?
    private var statusRefreshTask: Task<Void, Never>?
    private var statusRefreshTimer: Timer?
    private lazy var updateService = UpdateService(
        onUpdateAvailable: { [weak self] release in
            self?.presentUpdateAlert(for: release)
        }
    )

    init(arguments: Arguments) {
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !quitIfRunningFromReadOnlyVolume() else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = Self.appIcon()
        installStatusItem()
        startServer()
        SpotlightSearchService.warmProviderIndexes()
        refreshProviderStatus { [weak self] in
            self?.showPermissionsOnLaunchIfNeeded()
        }
        updateService.startPeriodicChecks()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProviderStatus()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if permissionsWindow?.window?.isVisible == true {
            UserDefaults.standard.set(true, forKey: Self.reopenPermissionsOnNextLaunchKey)
        }
        statusRefreshTimer?.invalidate()
        statusRefreshTask?.cancel()
        server?.stop()
    }

    private func quitIfRunningFromReadOnlyVolume() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.path.hasPrefix("/Volumes/"),
              let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
              values.volumeIsReadOnly == true else {
            return false
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Limelight to Applications"
        alert.informativeText = "Limelight is running from a mounted disk image. Drag Limelight to your Applications folder, eject the disk image, then open Limelight from Applications."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusButton(item.button, warning: false)
        statusItem = item
        rebuildMenu()
    }

    private func configureStatusButton(_ button: NSStatusBarButton?, warning: Bool) {
        guard let button else {
            return
        }
        let image = Self.menuBarIcon()
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
        button.imagePosition = .imageOnly
        button.title = warning ? "!" : ""
        button.toolTip = warning ? "Limelight needs attention" : "Limelight"
    }

    private static func menuBarIcon() -> NSImage? {
        bundledImage(named: "limelight-menu-template.png") ??
            NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: "Limelight")
    }

    private static func appIcon() -> NSImage? {
        bundledImage(named: "limelight.png")
    }

    private static func bundledImage(named name: String) -> NSImage? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/spotlight-index/Resources/\(name)")
        return NSImage(contentsOf: developmentURL)
    }

    private func startServer() {
        let observer: SpotlightHTTPServer.SearchObserver = { [weak self] request, response, context in
            DispatchQueue.main.async {
                self?.recordSearch(request: request, response: response, context: context)
            }
        }

        do {
            let started = try startSpotlightHTTPServer(host: arguments.host, preferredPort: arguments.port, onSearch: observer)
            self.server = started.server
            configureStatusButton(statusItem?.button, warning: false)
        } catch {
            configureStatusButton(statusItem?.button, warning: true)
            presentError("Failed to start Limelight: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    private func recordSearch(request: SearchRequest, response: SearchResponse, context: SearchAuditContext) {
        let sources = request.sources?.joined(separator: ", ") ?? "all"
        let entry = RecentSearch(
            query: request.query.isEmpty ? "(empty query)" : request.query,
            sources: sources,
            types: request.types?.joined(separator: ", ") ?? "all",
            originatorApp: context.originatorApp,
            limit: request.limit,
            count: response.count,
            searchedAt: Date()
        )
        recentSearches.removeAll { $0.query == entry.query && $0.sources == entry.sources && $0.originatorApp == entry.originatorApp }
        recentSearches.insert(entry, at: 0)
        recentSearches = Array(recentSearches.prefix(100))
        recentSearchesWindow?.update(searches: recentSearches)
        rebuildMenu()
    }

    private func refreshProviderStatus(onComplete: (() -> Void)? = nil) {
        statusRefreshTask?.cancel()
        statusRefreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                SpotlightSearchService().providerReadiness()
            }.value
            guard let self, !Task.isCancelled else {
                return
            }
            self.lastProviderStatus = status
            self.permissionsWindow?.update(status: status)
            self.rebuildMenu()
            onComplete?()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if recentSearches.isEmpty {
            let emptyItem = NSMenuItem(title: "No searches yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let recentHeader = NSMenuItem(title: "Recent Searches", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            menu.addItem(recentHeader)

            for search in recentSearches.prefix(5) {
                let item = NSMenuItem(title: search.menuTitle, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        let viewAllItem = NSMenuItem(title: "View All Recent Searches...", action: #selector(openRecentSearches), keyEquivalent: "")
        viewAllItem.target = self
        menu.addItem(viewAllItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Limelight", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openPermissions() {
        if permissionsWindow == nil || permissionsWindow?.window == nil {
            permissionsWindow = PermissionsWindowController()
        }
        permissionsWindow?.update(status: lastProviderStatus)
        permissionsWindow?.showWindow(nil)
        permissionsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openRecentSearches() {
        if recentSearchesWindow == nil {
            recentSearchesWindow = RecentSearchesWindowController { [weak self] in
                self?.clearRecentSearches()
            }
        }
        recentSearchesWindow?.update(searches: recentSearches)
        recentSearchesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func clearRecentSearches() {
        recentSearches.removeAll()
        recentSearchesWindow?.update(searches: recentSearches)
        rebuildMenu()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(onManagePermissions: { [weak self] in
                self?.openPermissions()
            })
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionsOnLaunchIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.reopenPermissionsOnNextLaunchKey) {
            UserDefaults.standard.removeObject(forKey: Self.reopenPermissionsOnNextLaunchKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.openPermissions()
            }
            return
        }

        if let lastProviderStatus,
           !PermissionsWindowController.fullDiskAccessLooksReady(lastProviderStatus) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.openPermissions()
            }
            return
        }

        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return
        }

        let installStamp = "\(Int(modifiedAt.timeIntervalSince1970))"
        let key = "LimelightLastPermissionsInstallStamp"
        guard UserDefaults.standard.string(forKey: key) != installStamp else {
            return
        }
        UserDefaults.standard.set(installStamp, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.openPermissions()
        }
    }

    private func presentUpdateAlert(for release: GitHubReleaseChecker.Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "A Limelight update is available"
        alert.informativeText = "Version \(release.version) is available on GitHub."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Skip This One")
        alert.addButton(withTitle: "Later")
        alert.window.level = .floating
        alert.window.orderFrontRegardless()
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            updateService.downloadAndInstall(release)
        case .alertSecondButtonReturn:
            updateService.skip(release)
        default:
            break
        }
    }

    @objc private func openFullDiskAccess() {
        UserDefaults.standard.set(true, forKey: "LimelightReopenPermissionsOnNextLaunch")
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Limelight"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

@MainActor
func runMenuBarApp(arguments: Arguments) {
    let app = NSApplication.shared
    let delegate = SpotlightIndexAppDelegate(arguments: arguments)
    app.delegate = delegate
    app.run()
}
#endif
