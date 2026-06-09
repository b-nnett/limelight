import Foundation

#if canImport(AppKit)
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let updateStatusLabel = NSTextField(labelWithString: "Updates have not been checked.")
    private let versionLabel = NSTextField(labelWithString: SettingsWindowController.currentVersionText)
    private let launchAtStartupButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let onManagePermissions: () -> Void

    init(onManagePermissions: @escaping () -> Void) {
        self.onManagePermissions = onManagePermissions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 342),
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
        let versionSeparator = NSBox()
        versionSeparator.boxType = .separator
        let versionRow = buildVersionRow()
        let permissionsSeparator = NSBox()
        permissionsSeparator.boxType = .separator
        let permissionsRow = buildManagePermissionsRow()
        stack.addArrangedSubview(updatesRow)
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(launchRow)
        stack.addArrangedSubview(versionSeparator)
        stack.addArrangedSubview(versionRow)
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
            versionRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            versionSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
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

    private func buildVersionRow() -> NSView {
        versionLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return buildGroupedRow(
            symbolName: "info.circle",
            title: "Version",
            detailView: versionLabel,
            accessoryView: spacer
        )
    }

    private static var currentVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
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

private enum LaunchAtStartupController {
    private static var label: String {
        Bundle.main.bundleIdentifier ?? "com.bennett.limelight"
    }

    static var isEnabled: Bool {
        launchAgentMatchesCurrentApp()
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
        guard let executableURL = Bundle.main.executableURL else {
            throw NSError(domain: "LimelightLaunchAtStartup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not resolve the Limelight executable path."])
        }
        try runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path], allowFailure: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executableURL.path)</string>
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

    private static func launchAgentMatchesCurrentApp() -> Bool {
        guard FileManager.default.fileExists(atPath: launchAgentURL.path),
              let executablePath = Bundle.main.executableURL?.path,
              let plist = NSDictionary(contentsOf: launchAgentURL) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              arguments.first == executablePath else {
            return false
        }
        return true
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

#endif
