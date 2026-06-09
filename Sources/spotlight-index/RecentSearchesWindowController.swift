import Foundation

#if canImport(AppKit)
import AppKit

@MainActor
final class RecentSearchesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
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
            return AppIconLookup.icon(bundleIdentifier: "com.apple.Photos", fallbackSymbol: "photo.on.rectangle")
        case "mail":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.mail", fallbackSymbol: "envelope")
        case "messages":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.MobileSMS", fallbackSymbol: "message")
        case "safari":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.Safari", fallbackSymbol: "safari")
        case "notes":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.Notes", fallbackSymbol: "note.text")
        case "calendar":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.iCal", fallbackSymbol: "calendar")
        case "contacts":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.AddressBook", fallbackSymbol: "person.crop.circle")
        case "reminders":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.reminders", fallbackSymbol: "checklist")
        case "files", "file":
            return AppIconLookup.icon(bundleIdentifier: "com.apple.finder", fallbackSymbol: "folder")
        default:
            return NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") ?? NSImage()
        }
    }
}

struct RecentSearch {
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

#endif
