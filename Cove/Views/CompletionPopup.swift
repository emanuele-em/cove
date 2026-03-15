import AppKit

final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private let panel: NSPanel
    private let tableView: NSTableView
    private var items: [CompletionItem] = []
    var onAccept: ((CompletionItem) -> Void)?

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 6
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -4),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.isEditable = false
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        super.init()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
    }

    var isVisible: Bool { panel.isVisible }

    func show(items newItems: [CompletionItem], at screenPoint: NSPoint, textView: NSTextView) {
        items = newItems
        tableView.reloadData()

        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        let visibleRows = min(CGFloat(items.count), 10)
        let height = visibleRows * 23 + 8
        let width: CGFloat = 320

        panel.setFrame(
            NSRect(x: screenPoint.x, y: screenPoint.y - height, width: width, height: height),
            display: true
        )

        if !panel.isVisible {
            panel.orderFront(nil)
            textView.window?.addChildWindow(panel, ordered: .above)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveUp() -> Bool {
        guard !items.isEmpty else { return false }
        let row = tableView.selectedRow
        if row > 0 {
            tableView.selectRowIndexes(IndexSet(integer: row - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(row - 1)
        }
        return true
    }

    func moveDown() -> Bool {
        guard !items.isEmpty else { return false }
        let row = tableView.selectedRow
        if row < items.count - 1 {
            tableView.selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(row + 1)
        }
        return true
    }

    var selectedItem: CompletionItem? {
        let row = tableView.selectedRow
        guard row >= 0 && row < items.count else { return nil }
        return items[row]
    }

    @objc private func doubleClicked() {
        guard let item = selectedItem else { return }
        onAccept?(item)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]

        let cell = NSView()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: iconName(for: item.kind), accessibilityDescription: nil)
        icon.contentTintColor = tintColor(for: item.kind)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)

        let label = NSTextField(labelWithString: item.label)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        let detail = NSTextField(labelWithString: item.detail)
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(detail)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            detail.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            detail.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            detail.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 22 }

    // MARK: - Kind appearance

    private func iconName(for kind: CompletionKind) -> String {
        switch kind {
        case .keyword:  "textformat"
        case .table:    "tablecells"
        case .column:   "line.3.horizontal"
        case .function: "function"
        case .schema:   "square.grid.2x2"
        case .type:     "textformat.abc"
        }
    }

    private func tintColor(for kind: CompletionKind) -> NSColor {
        switch kind {
        case .keyword:  NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
        case .table:    NSColor(red: 0.42, green: 0.62, blue: 0.80, alpha: 1)
        case .column:   NSColor(red: 0.55, green: 0.66, blue: 0.78, alpha: 1)
        case .function: NSColor(red: 0.69, green: 0.51, blue: 0.80, alpha: 1)
        case .schema:   NSColor(red: 0.77, green: 0.53, blue: 0.75, alpha: 1)
        case .type:     NSColor(red: 0.88, green: 0.65, blue: 0.41, alpha: 1)
        }
    }
}
