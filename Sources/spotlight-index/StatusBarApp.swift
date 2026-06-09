import Foundation
import SpotlightIndexCore

#if canImport(AppKit)
import AppKit
import QuartzCore

@MainActor
final class SpotlightIndexAppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: Arguments
    private var server: SpotlightHTTPServer?
    private var statusItem: NSStatusItem?
    private var recentSearches: [RecentSearch] = []
    private var permissionsWindow: PermissionsWindowController?
    private var recentSearchesWindow: RecentSearchesWindowController?
    private var settingsWindow: SettingsWindowController?
    private var lastProviderStatus: ProvidersResponse?
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
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = Self.appIcon()
        installStatusItem()
        startServer()
        SpotlightSearchService.warmProviderIndexes()
        refreshProviderStatus()
        showPermissionsAfterInstallIfNeeded()
        updateService.startPeriodicChecks()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProviderStatus()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusRefreshTimer?.invalidate()
        server?.stop()
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

        let server = SpotlightHTTPServer(host: arguments.host, port: arguments.port, onSearch: observer, authToken: arguments.authToken)
        do {
            try server.start()
            self.server = server
            configureStatusButton(statusItem?.button, warning: false)
        } catch {
            configureStatusButton(statusItem?.button, warning: true)
            presentError("Failed to start Limelight: \(error.localizedDescription)")
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

    private func refreshProviderStatus() {
        let service = SpotlightSearchService()
        lastProviderStatus = service.providerReadiness()
        permissionsWindow?.update(status: lastProviderStatus)
        rebuildMenu()
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
        if permissionsWindow == nil {
            permissionsWindow = PermissionsWindowController()
        }
        permissionsWindow?.update(status: lastProviderStatus)
        permissionsWindow?.showWindow(nil)
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

    private func showPermissionsAfterInstallIfNeeded() {
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
        let alert = NSAlert()
        alert.messageText = "A Limelight update is available"
        alert.informativeText = "Version \(release.version) is available on GitHub."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Skip This One")
        alert.addButton(withTitle: "Later")
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
final class PermissionsWindowController: NSWindowController, NSToolbarDelegate {
    private let stackView = NSStackView()
    private let fullDiskStatusLabel = NSTextField(labelWithString: "Checking...")
    private let carouselView = AppIconCarouselView()
    private let githubToolbarItemIdentifier = NSToolbarItem.Identifier("github")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Limelight Permissions"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.center()
        super.init(window: window)
        installToolbar(on: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(status: ProvidersResponse?) {
        guard let status else {
            fullDiskStatusLabel.stringValue = "Checking..."
            return
        }

        if Self.fullDiskAccessLooksReady(status) {
            fullDiskStatusLabel.stringValue = "Full Disk Access is enabled"
            fullDiskStatusLabel.textColor = NSColor.systemGreen
        } else {
            fullDiskStatusLabel.stringValue = "Full Disk Access required"
            fullDiskStatusLabel.textColor = NSColor.systemOrange
        }
    }

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "limelight.permissions.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, githubToolbarItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, githubToolbarItemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == githubToolbarItemIdentifier else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "GitHub"
        item.paletteLabel = "GitHub"
        item.toolTip = "Open Limelight on GitHub"
        item.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "GitHub")
        item.target = self
        item.action = #selector(openGitHub)
        return item
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        carouselView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(carouselView)

        let permissionRow = buildFullDiskAccessRow()
        stackView.addArrangedSubview(permissionRow)

        let privacyCopy = NSTextField(labelWithString: "Your data is never sent off of your device by Limelight. Using the app simply allows quicker access for AI apps to use the data.\n\nThird-party apps may send your data to their servers; read their privacy policies to learn more.")
        privacyCopy.font = NSFont.systemFont(ofSize: 12)
        privacyCopy.textColor = .secondaryLabelColor
        privacyCopy.alignment = .center
        privacyCopy.lineBreakMode = .byWordWrapping
        privacyCopy.maximumNumberOfLines = 0
        stackView.addArrangedSubview(privacyCopy)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 400),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 62),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            carouselView.widthAnchor.constraint(equalToConstant: 330),
            carouselView.heightAnchor.constraint(equalToConstant: 150),
            permissionRow.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func buildFullDiskAccessRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "externaldrive.badge.checkmark", accessibilityDescription: "Full Disk Access")
        iconView.contentTintColor = .labelColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Full Disk Access")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        textStack.addArrangedSubview(title)

        fullDiskStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textStack.addArrangedSubview(fullDiskStatusLabel)

        let button = NSButton(title: "Open Settings", target: self, action: #selector(openFullDiskAccess))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded

        container.addSubview(iconView)
        container.addSubview(textStack)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 74),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @objc private func openFullDiskAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/b-nnett/limelight")!)
    }

    private static func fullDiskAccessLooksReady(_ status: ProvidersResponse) -> Bool {
        let protectedSources: Set<String> = ["photos", "notes", "mail", "messages", "safari"]
        return status.providers
            .filter { protectedSources.contains($0.source) }
            .allSatisfy { $0.status == "ready" }
    }
}

@MainActor
private final class AppIconCarouselView: NSView {
    struct CarouselIcon {
        let name: String
        let image: NSImage
    }

    private var icons: [CarouselIcon] = [
        CarouselIcon(name: "Contacts", image: appIcon(bundleIdentifier: "com.apple.AddressBook", fallbackSymbol: "person.crop.circle")),
        CarouselIcon(name: "Calendar", image: appIcon(bundleIdentifier: "com.apple.iCal", fallbackSymbol: "calendar")),
        CarouselIcon(name: "Photos", image: appIcon(bundleIdentifier: "com.apple.Photos", fallbackSymbol: "photo.on.rectangle")),
        CarouselIcon(name: "Mail", image: appIcon(bundleIdentifier: "com.apple.mail", fallbackSymbol: "envelope")),
        CarouselIcon(name: "Messages", image: appIcon(bundleIdentifier: "com.apple.MobileSMS", fallbackSymbol: "message")),
        CarouselIcon(name: "Safari", image: appIcon(bundleIdentifier: "com.apple.Safari", fallbackSymbol: "safari")),
        CarouselIcon(name: "Notes", image: appIcon(bundleIdentifier: "com.apple.Notes", fallbackSymbol: "note.text")),
        CarouselIcon(name: "Reminders", image: appIcon(bundleIdentifier: "com.apple.reminders", fallbackSymbol: "checklist")),
        CarouselIcon(name: "Files", image: appIcon(bundleIdentifier: "com.apple.finder", fallbackSymbol: "folder"))
    ]
    private var progress: CGFloat = 0
    private var animationElapsed: TimeInterval = 0
    private var lastTickDate: Date?
    private var timer: Timer?
    private let visibleIconCount = 5
    private let renderedIconCount = 7
    private let holdDuration: TimeInterval = 3
    private let transitionDuration: TimeInterval = 0.38
    private let fadeMaskLayer = CAGradientLayer()
    private var iconViews: [CarouselIconView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        fadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMaskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        fadeMaskLayer.locations = [0, 0.16, 0.84, 1]
        layer?.mask = fadeMaskLayer
        buildIconViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func tick() {
        let now = Date()
        let delta = min(now.timeIntervalSince(lastTickDate ?? now), 0.1)
        lastTickDate = now
        animationElapsed += delta

        if animationElapsed <= holdDuration {
            progress = 0
        } else {
            let rawTransitionProgress = (animationElapsed - holdDuration) / transitionDuration
            if rawTransitionProgress >= 1 {
                completeTransition()
            } else {
                progress = Self.easedTransition(CGFloat(rawTransitionProgress))
            }
        }

        layoutIconViews()
    }

    private static func easedTransition(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(t, 1))
        if clamped < 0.5 {
            return 4 * clamped * clamped * clamped
        }
        return 1 - pow(-2 * clamped + 2, 3) / 2
    }

    private func advanceIcons() {
        guard !icons.isEmpty else {
            return
        }
        let first = icons.removeFirst()
        icons.append(first)
    }

    private func resetAnimationClock() {
        progress = 0
        animationElapsed = 0
        lastTickDate = Date()
    }

    private func completeTransition() {
        resetAnimationClock()
        advanceIcons()
    }

    override func layout() {
        super.layout()
        layoutIconViews()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            timer?.invalidate()
            timer = nil
            lastTickDate = nil
        } else {
            resetAnimationClock()
            startAnimation()
        }
    }

    private func buildIconViews() {
        iconViews = (0..<renderedIconCount).map { _ in
            let iconView = CarouselIconView(frame: .zero)
            addSubview(iconView)
            return iconView
        }
        layoutIconViews()
    }

    private func startAnimation() {
        guard timer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func layoutIconViews() {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        fadeMaskLayer.frame = bounds
        let centerY = bounds.midY
        let centerSlot = CGFloat(renderedIconCount / 2)

        for index in 0..<renderedIconCount {
            let icon = icons[index % icons.count]
            let position = CGFloat(index) - progress
            let logicalDistance = position - centerSlot
            let centeredDistance = abs(logicalDistance)
            let centerStrength = pow(max(0, 1 - min(centeredDistance / 2, 1)), 1.55)
            let scale = 0.58 + centerStrength * 1.34
            let size = 46 * scale
            let alpha = 0.18 + centerStrength * 0.82
            let x = bounds.midX + Self.horizontalOffset(for: logicalDistance)

            let iconView = iconViews[index]
            iconView.configure(icon)
            iconView.frame = NSRect(x: x - size / 2, y: centerY - size / 2, width: size, height: size)
            iconView.alphaValue = centeredDistance > 2.35 ? 0 : alpha
            iconView.layer?.zPosition = centerStrength
            iconView.layer?.shadowOpacity = Float(0.05 + centerStrength * 0.16)
            iconView.layer?.shadowRadius = 4 + centerStrength * 6
            iconView.layer?.shadowOffset = CGSize(width: 0, height: 2 + centerStrength * 3)
        }
    }

    private static func horizontalOffset(for logicalDistance: CGFloat) -> CGFloat {
        let sign: CGFloat = logicalDistance < 0 ? -1 : 1
        let distance = abs(logicalDistance)
        let centerToSecondary: CGFloat = 70
        let outerGap: CGFloat = 38
        if distance <= 1 {
            return sign * distance * centerToSecondary
        }
        return sign * (centerToSecondary + (distance - 1) * outerGap)
    }

    private static func appIcon(bundleIdentifier: String, fallbackSymbol: String) -> NSImage {
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

@MainActor
private final class CarouselIconView: NSImageView {
    private var configuredName: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(_ icon: AppIconCarouselView.CarouselIcon) {
        guard configuredName != icon.name else {
            return
        }
        configuredName = icon.name
        image = icon.image
        toolTip = icon.name
    }
}

@MainActor
private final class RecentSearchesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No searches yet")
    private let clearToolbarItemIdentifier = NSToolbarItem.Identifier("clearHistory")
    private let onClearHistory: () -> Void
    private var searches: [RecentSearch] = []
    private var clearToolbarItem: NSToolbarItem?
    private var clearHistoryButton: NSButton?

    init(onClearHistory: @escaping () -> Void) {
        self.onClearHistory = onClearHistory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Recent Searches"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.center()
        super.init(window: window)
        installToolbar(on: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(searches: [RecentSearch]) {
        self.searches = searches
        tableView.reloadData()
        emptyLabel.isHidden = !searches.isEmpty
        tableView.isHidden = searches.isEmpty
        clearToolbarItem?.isEnabled = !searches.isEmpty
        clearHistoryButton?.isEnabled = !searches.isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        searches.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        58
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard searches.indices.contains(row) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("recentSearchCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? RecentSearchCellView ?? RecentSearchCellView()
        cell.identifier = identifier
        cell.configure(with: searches[row])
        return cell
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, clearToolbarItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, clearToolbarItemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == clearToolbarItemIdentifier else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Clear"
        item.paletteLabel = "Clear History"
        item.toolTip = "Clear search history"
        let button = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear History") ?? NSImage(), target: self, action: #selector(clearHistory))
        button.bezelStyle = .texturedRounded
        button.controlSize = .regular
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
        button.toolTip = "Clear search history"
        button.isEnabled = !searches.isEmpty
        item.view = button
        item.isEnabled = !searches.isEmpty
        clearToolbarItem = item
        clearHistoryButton = button
        return item
    }

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "limelight.recent-searches.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.windowBackgroundColor
        contentView.addSubview(scrollView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.backgroundColor = NSColor.windowBackgroundColor
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("search"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 300
        column.width = 590
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    @objc private func clearHistory() {
        onClearHistory()
    }
}

@MainActor
private final class RecentSearchCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let queryLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let resultLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(with search: RecentSearch) {
        let sourceIcon = Self.icon(for: search)
        sourceIcon.size = NSSize(width: 22, height: 22)
        iconView.image = sourceIcon
        iconView.toolTip = search.sources
        queryLabel.stringValue = search.query
        sourceLabel.stringValue = search.primaryLine
        detailLabel.stringValue = search.secondaryLine
        resultLabel.stringValue = "\(search.count) result\(search.count == 1 ? "" : "s")"
    }

    private func buildContent() {
        wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        addSubview(iconView)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        queryLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        queryLabel.lineBreakMode = .byTruncatingTail
        queryLabel.maximumNumberOfLines = 1
        textStack.addArrangedSubview(queryLabel)

        sourceLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.maximumNumberOfLines = 1
        textStack.addArrangedSubview(sourceLabel)

        detailLabel.font = NSFont.systemFont(ofSize: 10)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        textStack.addArrangedSubview(detailLabel)

        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.alignment = .right
        resultLabel.lineBreakMode = .byTruncatingTail
        addSubview(resultLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: resultLabel.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            resultLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            resultLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 62)
        ])
    }

    private static func icon(for search: RecentSearch) -> NSImage {
        let source = search.sources
            .split(separator: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "all"

        switch source {
        case "photos":
            return appIcon(bundleIdentifier: "com.apple.Photos", fallbackSymbol: "photo.on.rectangle")
        case "mail":
            return appIcon(bundleIdentifier: "com.apple.mail", fallbackSymbol: "envelope")
        case "messages":
            return appIcon(bundleIdentifier: "com.apple.MobileSMS", fallbackSymbol: "message")
        case "safari":
            return appIcon(bundleIdentifier: "com.apple.Safari", fallbackSymbol: "safari")
        case "notes":
            return appIcon(bundleIdentifier: "com.apple.Notes", fallbackSymbol: "note.text")
        case "calendar":
            return appIcon(bundleIdentifier: "com.apple.iCal", fallbackSymbol: "calendar")
        case "contacts":
            return appIcon(bundleIdentifier: "com.apple.AddressBook", fallbackSymbol: "person.crop.circle")
        case "reminders":
            return appIcon(bundleIdentifier: "com.apple.reminders", fallbackSymbol: "checklist")
        case "files", "file":
            return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        default:
            return NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") ?? NSImage()
        }
    }

    private static func appIcon(bundleIdentifier: String, fallbackSymbol: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil) ?? NSImage()
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let updateStatusLabel = NSTextField(labelWithString: "Updates have not been checked.")
    private let launchAtStartupButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let onManagePermissions: () -> Void

    init(onManagePermissions: @escaping () -> Void) {
        self.onManagePermissions = onManagePermissions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 286),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        installToolbar(on: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        launchAtStartupButton.state = LaunchAtStartupController.isEnabled ? .on : .off
        super.showWindow(sender)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "limelight.settings.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        launchAtStartupButton.target = self
        launchAtStartupButton.action = #selector(toggleLaunchAtStartup)
        stack.addArrangedSubview(buildSettingsGroup())

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 14)
        ])
    }

    private func buildSettingsGroup() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let updatesRow = buildUpdatesRow()
        let separator = NSBox()
        separator.boxType = .separator
        let launchRow = buildLaunchAtStartupRow()
        let permissionsSeparator = NSBox()
        permissionsSeparator.boxType = .separator
        let permissionsRow = buildManagePermissionsRow()
        stack.addArrangedSubview(updatesRow)
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(launchRow)
        stack.addArrangedSubview(permissionsSeparator)
        stack.addArrangedSubview(permissionsRow)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 388),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            updatesRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            launchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            permissionsSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52)
        ])

        return container
    }

    private func buildUpdatesRow() -> NSView {
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.lineBreakMode = .byWordWrapping
        updateStatusLabel.maximumNumberOfLines = 0

        let button = NSButton(title: "Check for Updates", target: self, action: #selector(checkForUpdates))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return buildGroupedRow(
            symbolName: "arrow.triangle.2.circlepath",
            title: "Updates",
            detailView: updateStatusLabel,
            accessoryView: button
        )
    }

    private func buildLaunchAtStartupRow() -> NSView {
        return buildGroupedRow(
            symbolName: "power",
            title: "Launch at startup",
            subtitle: "Start Limelight when you sign in.",
            accessoryView: launchAtStartupButton
        )
    }

    private func buildManagePermissionsRow() -> NSView {
        let button = NSButton(title: "Manage Permissions", target: self, action: #selector(managePermissions))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return buildGroupedRow(
            symbolName: "externaldrive.badge.checkmark",
            title: "Permissions",
            subtitle: "Review local data access and Full Disk Access.",
            accessoryView: button
        )
    }

    private func buildGroupedRow(symbolName: String, title: String, subtitle: String? = nil, detailView: NSView? = nil, accessoryView: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        iconView.contentTintColor = .secondaryLabelColor
        container.addSubview(iconView)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        textStack.addArrangedSubview(titleLabel)

        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byWordWrapping
            subtitleLabel.maximumNumberOfLines = 0
            textStack.addArrangedSubview(subtitleLabel)
        }

        if let detailView {
            textStack.addArrangedSubview(detailView)
        }

        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        if let control = accessoryView as? NSControl {
            control.controlSize = .small
        }
        container.addSubview(accessoryView)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 13),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: accessoryView.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            accessoryView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            accessoryView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @objc private func checkForUpdates() {
        updateStatusLabel.stringValue = "Checking GitHub releases..."
        Task {
            do {
                let latest = try await GitHubReleaseChecker.latestRelease()
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
                if latest.version == current || latest.version == "v\(current)" {
                    updateStatusLabel.stringValue = "Limelight is up to date (\(current))."
                } else {
                    updateStatusLabel.stringValue = "Latest GitHub release is \(latest.version). Current app is \(current)."
                }
            } catch {
                updateStatusLabel.stringValue = "Could not check GitHub releases: \(error.localizedDescription)"
            }
        }
    }

    @objc private func toggleLaunchAtStartup() {
        do {
            try LaunchAtStartupController.setEnabled(launchAtStartupButton.state == .on)
            launchAtStartupButton.state = LaunchAtStartupController.isEnabled ? .on : .off
        } catch {
            launchAtStartupButton.state = LaunchAtStartupController.isEnabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Launch at startup could not be updated"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func managePermissions() {
        onManagePermissions()
    }
}

@MainActor
private final class UpdateService {
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
                guard isNewer(release.version, than: currentVersion),
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

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = versionParts(candidate)
        let rhs = versionParts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { part in
                Int(part.filter(\.isNumber)) ?? 0
            }
    }
}

private enum UpdateInstaller {
    static func install(_ release: GitHubReleaseChecker.Release) async throws {
        guard let asset = release.installableAsset else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }

        let downloadedURL = try await download(asset.url)
        switch downloadedURL.pathExtension.lowercased() {
        case "zip":
            try await installZip(downloadedURL)
        default:
            NSWorkspace.shared.open(downloadedURL)
        }
    }

    private static func download(_ url: URL) async throws -> URL {
        let (temporaryURL, _) = try await URLSession.shared.download(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Limelight-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension.isEmpty ? "download" : url.pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func installZip(_ zipURL: URL) async throws {
        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LimelightUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, workDirectory.path])

        guard let appURL = findApp(in: workDirectory) else {
            throw NSError(domain: "LimelightUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloaded update did not contain an app bundle."])
        }

        let currentAppURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let scriptURL = workDirectory.appendingPathComponent("install.sh")
        let script = """
        #!/bin/zsh
        sleep 1
        rm -rf "\(currentAppURL.path)"
        /usr/bin/ditto "\(appURL.path)" "\(currentAppURL.path)"
        /usr/bin/open -gj "\(currentAppURL.path)" --args --host 127.0.0.1 --port 8765
        rm -rf "\(workDirectory.path)"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try run("/bin/zsh", arguments: [scriptURL.path], wait: false)
        await MainActor.run {
            NSApp.terminate(nil)
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
}

private enum GitHubReleaseChecker {
    struct Release {
        let version: String
        let htmlURL: URL
        let assets: [Asset]

        var installableAsset: Asset? {
            assets.first { asset in
                let ext = asset.url.pathExtension.lowercased()
                return ext == "zip" || ext == "dmg"
            }
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

private enum LaunchAtStartupController {
    private static let label = "com.bennett.spotlight-index.local"

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            try uninstall()
        }
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static func install() throws {
        let appPath = Bundle.main.bundlePath
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-gj</string>
                <string>\(appPath)</string>
                <string>--args</string>
                <string>--host</string>
                <string>127.0.0.1</string>
                <string>--port</string>
                <string>8765</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        try runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path], allowFailure: true)
    }

    private static func uninstall() throws {
        try runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path], allowFailure: true)
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private static func runLaunchctl(_ arguments: [String], allowFailure: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 && !allowFailure {
            throw NSError(domain: "LimelightLaunchAtStartup", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "launchctl failed with status \(process.terminationStatus)."])
        }
    }
}

private struct RecentSearch {
    let query: String
    let sources: String
    let types: String
    let originatorApp: String
    let limit: Int?
    let count: Int
    let searchedAt: Date

    var menuTitle: String {
        "\(query.limited(to: 44)) · \(count) result\(count == 1 ? "" : "s")".limited(to: 68)
    }

    var detailLine: String {
        let limitText = limit.map(String.init) ?? "default"
        return "Originator: \(originatorApp) · Sources: \(sources) · Types: \(types) · Results: \(count) · Limit: \(limitText) · \(Self.dateFormatter.string(from: searchedAt))"
    }

    var primaryLine: String {
        "\(originatorApp) searched \(sources)"
    }

    var secondaryLine: String {
        let limitText = limit.map { "limit \($0)" } ?? "default limit"
        return "\(types) · \(limitText) · \(Self.dateFormatter.string(from: searchedAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private extension String {
    func limited(to maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }
        return String(prefix(max(0, maxLength - 1))) + "…"
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
