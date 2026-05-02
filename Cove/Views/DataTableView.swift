import SwiftUI
import AppKit

struct DataTableView: View {
    @Environment(AppState.self) private var state
    let table: TableState
    let isQueryResult: Bool

    @FocusState private var isTableFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                NativeDataTable(
                    table: table,
                    isQueryResult: isQueryResult,
                    onRowClicked: { row, col in
                        if let activeTable = state.table, activeTable === table {
                            state.tableRowClicked(row: row)
                        } else {
                            table.selectedRow = row
                        }
                        table.selectedColumn = col
                        isTableFocused = true
                    },
                    onDoubleClicked: { row, col in
                        guard let activeTable = state.table, activeTable === table else { return }
                        state.tableCellDoubleClicked(row: row, col: col)
                    },
                    onSortClicked: { col in
                        guard !isQueryResult else { return }
                        state.tableSortClicked(col)
                    },
                    onDelete: {
                        guard !isQueryResult else { return }
                        state.deleteSelectedRow()
                    }
                )

                reviewChangesButton
            }
            .focusable()
            .focused($isTableFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                switch press.key {
                case .upArrow: table.selectUp()
                case .downArrow: table.selectDown()
                case .leftArrow: table.selectLeft()
                case .rightArrow: table.selectRight()
                default: break
                }
                return .handled
            }
            .onKeyPress(phases: .down, action: handleKeyPress)
            .onAppear { isTableFocused = true }

            if !isQueryResult {
                paginationFooter
            }
        }
        .sheet(isPresented: Bindable(state).showSQLPreview) {
            SQLPreviewSheet()
                .environment(state)
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let key = keyPress.key
        let mods = keyPress.modifiers

        if mods.isEmpty {
            switch key {
            case .tab where !isQueryResult:
                table.tabForward()
                return .handled
            case .escape where !isQueryResult:
                state.tableEscape()
                isTableFocused = true
                return .handled
            case .return where !isQueryResult:
                state.tableEnter()
                return .handled
            default: break
            }
        }

        if mods == .shift && key == .tab && !isQueryResult {
            table.tabBackward()
            return .handled
        }

        if mods == .command && keyPress.characters == "s" {
            guard let activeTable = state.table, activeTable === table, table.hasPendingEdits else {
                return .ignored
            }
            state.showSQLPreview = true
            return .handled
        }

        if mods == .command && !isQueryResult {
            switch keyPress.characters {
            case "c": state.tableCopyCell(); return .handled
            case "r": state.refresh(); return .handled
            default: break
            }
        }

        return .ignored
    }

    @ViewBuilder
    private var reviewChangesButton: some View {
        if let activeTable = state.table, activeTable === table, table.hasPendingEdits {
            Button {
                state.showSQLPreview = true
            } label: {
                Label("Review Changes", systemImage: "eye")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(16)
        }
    }

    private var paginationFooter: some View {
        HStack {
            if state.hasStructureTab {
                Picker("", selection: Binding(
                    get: { state.tableTab },
                    set: { state.tableTabChanged($0) }
                )) {
                    Text("Data").tag(TableTab.data)
                    Text("Structure").tag(TableTab.structure)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            if state.isEditableTable {
                Button { state.addRow() } label: {
                    Label("New Row", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            HStack(spacing: 6) {
                Button { state.tablePrevPage() } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!table.hasPrev)

                Text(table.pageInfo)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button { state.tableNextPage() } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!table.hasNext)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { table.pageSize },
                set: { state.tablePageSize($0) }
            )) {
                Text("50").tag(UInt32(50))
                Text("100").tag(UInt32(100))
                Text("500").tag(UInt32(500))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 34)
        .background(.ultraThinMaterial)
    }
}

// MARK: - NSTableView wrapper

private struct NativeDataTable: NSViewRepresentable {
    let table: TableState
    let isQueryResult: Bool
    let onRowClicked: (Int, Int) -> Void
    let onDoubleClicked: (Int, Int) -> Void
    let onSortClicked: (Int) -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = KeyableTableView()
        let coordinator = context.coordinator
        tableView.onDelete = { [weak coordinator] in
            coordinator?.parent.onDelete()
        }
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.allowsMultipleSelection = false
        tableView.headerView = NSTableHeaderView()
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.tableDoubleClick(_:))

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        setupColumns(tableView)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self

        let currentIds = tableView.tableColumns.map { $0.identifier.rawValue }
        let newIds = table.columns.enumerated().map { "col_\($0)_\($1.name)" }
        if currentIds != newIds {
            for col in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(col)
            }
            setupColumns(tableView)
        }

        tableView.reloadData()
        syncSortIndicator(tableView)

        if let row = table.selectedRow, row < table.rows.count {
            if tableView.selectedRow != row {
                context.coordinator.suppressSelectionCallback = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
                context.coordinator.suppressSelectionCallback = false
            }
        } else if tableView.selectedRow >= 0 {
            context.coordinator.suppressSelectionCallback = true
            tableView.deselectAll(nil)
            context.coordinator.suppressSelectionCallback = false
        }
    }

    private func setupColumns(_ tableView: NSTableView) {
        for (i, col) in table.columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(i)_\(col.name)"))
            column.headerCell.attributedStringValue = Self.headerString(name: col.name, typeName: col.typeName)
            column.minWidth = 60
            column.maxWidth = 600
            column.width = table.cachedColWidths.indices.contains(i) ? table.cachedColWidths[i] : 120

            if !isQueryResult {
                column.sortDescriptorPrototype = NSSortDescriptor(key: col.name, ascending: true)
            }

            tableView.addTableColumn(column)
        }
    }

    private func syncSortIndicator(_ tableView: NSTableView) {
        for col in tableView.tableColumns {
            tableView.setIndicatorImage(nil, in: col)
        }

        guard let sortName = table.sortColumn,
              let col = tableView.tableColumns.first(where: {
                  $0.sortDescriptorPrototype?.key == sortName
              }) else { return }

        let imageName = table.sortDirection == .asc
            ? "NSAscendingSortIndicator"
            : "NSDescendingSortIndicator"
        tableView.setIndicatorImage(NSImage(named: NSImage.Name(imageName)), in: col)
        tableView.highlightedTableColumn = col
    }

    private static func headerString(name: String, typeName: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: name,
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]
        )
        result.append(NSAttributedString(
            string: " \(typeName)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        return result
    }

    // MARK: - Coordinator

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeDataTable
        weak var tableView: NSTableView?
        var suppressSelectionCallback = false

        init(parent: NativeDataTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.table.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            guard let colIdx = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }
            guard row < parent.table.rows.count, colIdx < parent.table.columns.count else { return nil }

            let cellId = NSUserInterfaceItemIdentifier("DataCell")
            let cellView: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView {
                cellView = existing
            } else {
                let tf = NSTextField()
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isEditable = false
                tf.lineBreakMode = .byTruncatingTail
                tf.font = .systemFont(ofSize: 12)
                tf.translatesAutoresizingMaskIntoConstraints = false

                let cv = NSTableCellView()
                cv.identifier = cellId
                cv.textField = tf
                cv.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 2),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -2),
                    tf.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
                ])
                cellView = cv
            }

            let tf = cellView.textField!
            let value = parent.table.effectiveValue(row: row, col: colIdx)
            tf.stringValue = value ?? "NULL"

            let isDeleted = parent.table.isDeletedRow(row)
            let isEdited = parent.table.hasEdit(row: row, col: colIdx)
            let isNull = value == nil

            if isDeleted {
                tf.textColor = .secondaryLabelColor
            } else if isEdited {
                tf.textColor = .systemOrange
            } else if isNull {
                tf.textColor = .tertiaryLabelColor
            } else {
                tf.textColor = .labelColor
            }

            return cellView
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let table = parent.table
            if table.isDeletedRow(row) {
                let rv = TintedRowView()
                rv.tintColor = NSColor.systemRed.withAlphaComponent(0.08)
                return rv
            } else if table.hasEditInRow(row) || table.isNewRow(row) {
                let rv = TintedRowView()
                rv.tintColor = NSColor.systemGreen.withAlphaComponent(0.08)
                return rv
            }
            return nil
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionCallback else { return }
            guard let tv = notification.object as? NSTableView else { return }
            let row = tv.selectedRow
            if row >= 0 {
                let col = max(tv.clickedColumn, 0)
                parent.onRowClicked(row, col)
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sort = tableView.sortDescriptors.first,
                  let key = sort.key,
                  let idx = parent.table.columns.firstIndex(where: { $0.name == key }) else { return }
            parent.onSortClicked(idx)
        }

        @objc func tableDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            let col = sender.clickedColumn
            guard row >= 0, col >= 0 else { return }
            parent.onDoubleClicked(row, col)
        }
    }
}

// MARK: - Key-aware table view

private final class KeyableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isDelete = event.keyCode == 51 // backspace
        let isForwardDelete = event.keyCode == 117 // forward delete

        if (flags == .command && isDelete) || (flags.isEmpty && isForwardDelete) {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Tinted row background

private final class TintedRowView: NSTableRowView {
    var tintColor: NSColor?

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if let tint = tintColor {
            tint.setFill()
            dirtyRect.fill()
        }
    }
}
