import Foundation
import SpotlightIndexCore

#if canImport(AppKit)
import AppKit
import Contacts
import EventKit
import QuartzCore

@MainActor
final class PermissionsWindowController: NSWindowController, NSToolbarDelegate {
    private let stackView = NSStackView()
    private let fullDiskStatusLabel = NSTextField(labelWithString: "Checking...")
    private var frameworkStatusLabels: [String: NSTextField] = [:]
    private var frameworkAccessButtons: [String: NSButton] = [:]
    private var contactsStore: CNContactStore?
    private var eventStores: [String: EKEventStore] = [:]
    private var readinessRefreshTask: Task<Void, Never>?
    private let carouselView = AppIconCarouselView()
    private let githubToolbarItemIdentifier = NSToolbarItem.Identifier("github")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
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

        for source in ["contacts", "calendar", "reminders"] {
            let state = Self.frameworkPermissionState(source: source)
            let label = frameworkStatusLabels[source]
            label?.stringValue = state.status
            label?.textColor = state.color
            frameworkAccessButtons[source]?.title = state.buttonTitle
            frameworkAccessButtons[source]?.isEnabled = state.buttonEnabled
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
        let frameworkPermissionRow = buildFrameworkAccessRow()
        stackView.addArrangedSubview(frameworkPermissionRow)

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
            permissionRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            frameworkPermissionRow.widthAnchor.constraint(equalTo: stackView.widthAnchor)
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

    private func buildFrameworkAccessRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "person.crop.circle.badge.checkmark", accessibilityDescription: "Contacts and Calendar Access")
        iconView.contentTintColor = .labelColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "App Data Access")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        contentStack.addArrangedSubview(title)

        for permission in [
            ("contacts", "Contacts", "person.crop.circle"),
            ("calendar", "Calendar", "calendar"),
            ("reminders", "Reminders", "checklist")
        ] {
            contentStack.addArrangedSubview(buildFrameworkPermissionLine(source: permission.0, title: permission.1, symbolName: permission.2))
        }

        container.addSubview(iconView)
        container.addSubview(contentStack)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 144),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            contentStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 17),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14)
        ])

        return container
    }

    private func buildFrameworkPermissionLine(source: String, title: String, symbolName: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let statusLabel = NSTextField(labelWithString: "Checking...")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        frameworkStatusLabels[source] = statusLabel

        let button = NSButton(title: "Request", target: self, action: #selector(requestFrameworkAccess(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(source)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        frameworkAccessButtons[source] = button

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(statusLabel)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 24),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 76),
            statusLabel.widthAnchor.constraint(equalToConstant: 88)
        ])

        return row
    }

    @objc private func openFullDiskAccess() {
        UserDefaults.standard.set(true, forKey: "LimelightReopenPermissionsOnNextLaunch")
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    @objc private func requestFrameworkAccess(_ sender: NSButton) {
        guard let source = sender.identifier?.rawValue else {
            return
        }

        let state = Self.frameworkPermissionState(source: source)
        if state.opensSettings {
            openPrivacySettings(for: source)
            return
        }

        sender.isEnabled = false
        frameworkStatusLabels[source]?.stringValue = "Requesting..."
        frameworkStatusLabels[source]?.textColor = .secondaryLabelColor

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else {
                return
            }
            switch source {
            case "contacts":
                requestContactsAccess()
            case "calendar":
                requestCalendarAccess()
            case "reminders":
                requestRemindersAccess()
            default:
                refreshReadiness()
            }
        }
    }

    private func requestContactsAccess() {
        let store = CNContactStore()
        contactsStore = store
        Self.logPermissionEvent("contacts request starting with status \(CNContactStore.authorizationStatus(for: .contacts))")
        store.requestAccess(for: .contacts) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.contactsStore = nil
                Self.logPermissionEvent("contacts request completed granted=\(granted) status=\(CNContactStore.authorizationStatus(for: .contacts)) error=\(error?.localizedDescription ?? "nil")")
                NSApp.setActivationPolicy(.accessory)
                self?.refreshReadiness()
            }
        }
    }

    private func requestCalendarAccess() {
        let store = EKEventStore()
        eventStores["calendar"] = store
        Self.logPermissionEvent("calendar request starting with status \(EKEventStore.authorizationStatus(for: .event))")
        let completion: @Sendable (Bool, (any Error)?) -> Void = { [weak self] granted, error in
            DispatchQueue.main.async {
                let status = EKEventStore.authorizationStatus(for: .event)
                Self.logPermissionEvent("calendar request completed granted=\(granted) status=\(status) error=\(error?.localizedDescription ?? "nil")")
                self?.eventStores["calendar"] = nil
                NSApp.setActivationPolicy(.accessory)
                self?.refreshReadiness()
                if Self.eventKitPermissionState(status).buttonEnabled {
                    self?.frameworkStatusLabels["calendar"]?.stringValue = "No prompt shown"
                    self?.frameworkStatusLabels["calendar"]?.textColor = .systemRed
                }
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    private func requestRemindersAccess() {
        let store = EKEventStore()
        eventStores["reminders"] = store
        Self.logPermissionEvent("reminders request starting with status \(EKEventStore.authorizationStatus(for: .reminder))")
        let completion: @Sendable (Bool, (any Error)?) -> Void = { [weak self] granted, error in
            DispatchQueue.main.async {
                Self.logPermissionEvent("reminders request completed granted=\(granted) status=\(EKEventStore.authorizationStatus(for: .reminder)) error=\(error?.localizedDescription ?? "nil")")
                self?.eventStores["reminders"] = nil
                NSApp.setActivationPolicy(.accessory)
                self?.refreshReadiness()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders(completion: completion)
        } else {
            store.requestAccess(to: .reminder, completion: completion)
        }
    }

    private func refreshReadiness() {
        readinessRefreshTask?.cancel()
        readinessRefreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                SpotlightSearchService().providerReadiness()
            }.value
            guard let self, !Task.isCancelled else {
                return
            }
            self.update(status: status)
        }
    }

    private func openPrivacySettings(for source: String) {
        let pane: String
        switch source {
        case "contacts":
            pane = "Privacy_Contacts"
        case "calendar":
            pane = "Privacy_Calendars"
        case "reminders":
            pane = "Privacy_Reminders"
        default:
            pane = "Privacy"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/b-nnett/limelight")!)
    }

    static func fullDiskAccessLooksReady(_ status: ProvidersResponse) -> Bool {
        let protectedSources: Set<String> = ["photos", "notes", "mail", "messages", "safari"]
        return status.providers
            .filter { protectedSources.contains($0.source) }
            .allSatisfy { $0.status == "ready" }
    }

    private static func frameworkPermissionState(source: String) -> FrameworkPermissionState {
        switch source {
        case "contacts":
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized:
                return .enabled
            case .denied, .restricted:
                return .denied
            case .notDetermined:
                return .requestable
            @unknown default:
                return .settings(status: "Unknown")
            }
        case "calendar":
            return eventKitPermissionState(EKEventStore.authorizationStatus(for: .event))
        case "reminders":
            return eventKitPermissionState(EKEventStore.authorizationStatus(for: .reminder))
        default:
            return .settings(status: "Unknown")
        }
    }

    private static func eventKitPermissionState(_ status: EKAuthorizationStatus) -> FrameworkPermissionState {
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:
                return .enabled
            case .writeOnly:
                return .settings(status: "Write only")
            default:
                break
            }
        }

        switch status {
        case .authorized, .fullAccess:
            return .enabled
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .requestable
        case .writeOnly:
            return .settings(status: "Write only")
        @unknown default:
            return .settings(status: "Unknown")
        }
    }

    private static func logPermissionEvent(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Limelight-permissions.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        NSLog("Limelight permission: %@", message)
    }
}

private struct FrameworkPermissionState {
    let status: String
    let color: NSColor
    let buttonTitle: String
    let buttonEnabled: Bool
    let opensSettings: Bool

    static let enabled = FrameworkPermissionState(status: "Enabled", color: .systemGreen, buttonTitle: "Granted", buttonEnabled: false, opensSettings: false)
    static let requestable = FrameworkPermissionState(status: "Needs access", color: .systemOrange, buttonTitle: "Request", buttonEnabled: true, opensSettings: false)
    static let denied = FrameworkPermissionState(status: "Denied", color: .systemRed, buttonTitle: "Settings", buttonEnabled: true, opensSettings: true)

    static func settings(status: String) -> FrameworkPermissionState {
        FrameworkPermissionState(status: status, color: .systemOrange, buttonTitle: "Settings", buttonEnabled: true, opensSettings: true)
    }
}

@MainActor
private final class AppIconCarouselView: NSView {
    struct CarouselIcon {
        let name: String
        let image: NSImage
    }

    private var icons: [CarouselIcon] = [
        CarouselIcon(name: "Contacts", image: AppIconLookup.icon(bundleIdentifier: "com.apple.AddressBook", fallbackSymbol: "person.crop.circle")),
        CarouselIcon(name: "Calendar", image: AppIconLookup.icon(bundleIdentifier: "com.apple.iCal", fallbackSymbol: "calendar")),
        CarouselIcon(name: "Photos", image: AppIconLookup.icon(bundleIdentifier: "com.apple.Photos", fallbackSymbol: "photo.on.rectangle")),
        CarouselIcon(name: "Mail", image: AppIconLookup.icon(bundleIdentifier: "com.apple.mail", fallbackSymbol: "envelope")),
        CarouselIcon(name: "Messages", image: AppIconLookup.icon(bundleIdentifier: "com.apple.MobileSMS", fallbackSymbol: "message")),
        CarouselIcon(name: "Safari", image: AppIconLookup.icon(bundleIdentifier: "com.apple.Safari", fallbackSymbol: "safari")),
        CarouselIcon(name: "Notes", image: AppIconLookup.icon(bundleIdentifier: "com.apple.Notes", fallbackSymbol: "note.text")),
        CarouselIcon(name: "Reminders", image: AppIconLookup.icon(bundleIdentifier: "com.apple.reminders", fallbackSymbol: "checklist")),
        CarouselIcon(name: "Files", image: AppIconLookup.icon(bundleIdentifier: "com.apple.finder", fallbackSymbol: "folder"))
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

#endif
