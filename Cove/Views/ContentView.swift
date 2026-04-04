import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state


    var body: some View {
        VStack(spacing: 0) {
            if !state.errorText.isEmpty {
                errorBar
            }

            HStack(spacing: 0) {
                ConnectionRail()

                if state.connection != nil {
                    HSplitView {
                        if state.showSidebar {
                            SidebarView()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.quaternary, lineWidth: 1)
                                )
                                .padding(.trailing, 4)
                                .frame(minWidth: 184, idealWidth: 264, maxWidth: 604)
                        }

                        if state.showQueryEditor {
                            contentArea
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .layoutPriority(1)
                        } else {
                            contentArea
                                .background {
                                    VisualEffectBackground(material: .underWindowBackground)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.quaternary, lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .layoutPriority(1)
                        }

                        if state.showInspector, !state.showQueryEditor, let table = state.table,
                           state.contentMode == .table, table.selectedRow != nil {
                            RowInspectorView(table: table)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.quaternary, lineWidth: 1)
                                )
                                .padding(.leading, 4)
                                .frame(minWidth: 204, idealWidth: 284, maxWidth: 404)
                        }
                    }
                    .hideSplitDividers()
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .opacity(0.6)
                        HStack(spacing: 5) {
                            Text("Click")
                            Button {
                                state.openDialog()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(.quaternary, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            Text("to create a new connection")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .background {
            Color.clear.ignoresSafeArea()
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { toolbarContent }
        .sheet(isPresented: Binding(
            get: { state.dialog.visible },
            set: { if !$0 { state.dialogCancel() } }
        )) {
            ConnectionDialog()
                .environment(state)
        }
        .alert(
            "Delete Connection",
            isPresented: Binding(
                get: { state.connectionToDelete != nil },
                set: { if !$0 { state.connectionToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                state.connectionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                state.confirmDeleteConnection()
            }
        } message: {
            if let conn = state.connectionToDelete {
                Text("Are you sure you want to delete \"\(conn.name)\"?")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var state = state

        let hasTable = state.table != nil && state.contentMode == .table && !state.showQueryEditor
        let canInspect = hasTable && state.table?.selectedRow != nil

        let connected = state.connection != nil

        ToolbarItem(placement: .navigation) {
            Menu {
                ForEach(ConnectionEnvironment.allCases, id: \.self) { env in
                    Button {
                        state.switchEnvironment(to: env)
                    } label: {
                        Label {
                            Text(env.displayName)
                        } icon: {
                            Image(nsImage: coloredDot(env.color))
                        }
                    }
                }
            } label: {
                Label {
                    Text(state.selectedEnvironment.displayName)
                        .font(.system(size: 12))
                } icon: {
                    Image(nsImage: coloredDot(state.selectedEnvironment.color, padding: 3))
                }
                .labelStyle(SpacedLabelStyle())
            }
        }

        ToolbarItem(placement: .principal) {
            Text(state.breadcrumb.isEmpty ? "No connection" : state.breadcrumb)
                .font(.system(size: 12))
                .foregroundStyle(connected ? .primary : .tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { state.showQueryEditor },
                set: { _ in state.toggleQuery() }
            )) {
                Text("Query")
                    .font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(.button)
            .disabled(!connected)
        }

        ToolbarItemGroup(placement: .automatic) {
            Button { state.showSidebar.toggle() } label: {
                Image(systemName: "sidebar.leading")
            }
            .disabled(!connected)

            Button { state.showInspector.toggle() } label: {
                Image(systemName: "sidebar.trailing")
            }
            .disabled(!canInspect)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if state.showQueryEditor {
            VSplitView {
                QueryEditorView()
                    .background { VisualEffectBackground(material: .underWindowBackground) }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
                    .padding(.bottom, 4)
                    .frame(minHeight: 120)

                VStack(spacing: 0) {
                    tableOrEmpty
                    if !state.query.status.isEmpty {
                        queryStatusBar
                    }
                }
                .background { VisualEffectBackground(material: .underWindowBackground) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
                .frame(minHeight: 80)
            }
            .hideSplitDividers()
        } else {
            tableOrEmpty
        }
    }

    @ViewBuilder
    private var tableOrEmpty: some View {
        switch state.contentMode {
        case .empty:
            Text("Select a table or open a query")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .table:
            if let table = state.table {
                VStack(spacing: 0) {
                    if state.tableTab == .structure, state.hasStructureTab {
                        if let structure = state.structureTable {
                            DataTableView(table: structure, isQueryResult: true)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        DataTableView(table: table, isQueryResult: table.tablePath.isEmpty)
                    }

                    if !state.showQueryEditor, state.hasStructureTab, state.tableTab == .structure {
                        structureFooter
                    }
                }
            }
        }
    }

    private var queryStatusBar: some View {
        HStack {
            Text(state.query.status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 28)
        .background(.ultraThinMaterial)
    }

    private var structureFooter: some View {
        HStack {
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
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 34)
        .background(.ultraThinMaterial)
    }

    private func coloredDot(_ color: Color, padding: CGFloat = 0) -> NSImage {
        let dot: CGFloat = 8
        let total = dot + padding * 2
        let image = NSImage(size: NSSize(width: total, height: total), flipped: false) { _ in
            let oval = NSRect(x: padding, y: padding, width: dot, height: dot)
            NSColor(color).setFill()
            NSBezierPath(ovalIn: oval).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private var errorBar: some View {
        HStack {
            Text(state.errorText)
                .font(.system(size: 12))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.red)
    }
}

private struct SpacedLabelStyle: LabelStyle {
    var spacing: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

private struct SplitDividerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let splitView = findSplitView(from: view) else { return }
            splitView.dividerStyle = .thin
            for subview in splitView.subviews {
                let className = String(describing: type(of: subview))
                if className.contains("Divider") || className.contains("divider") {
                    subview.alphaValue = 0
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func findSplitView(from view: NSView) -> NSSplitView? {
        var current: NSView? = view
        while let v = current {
            if let split = v as? NSSplitView { return split }
            current = v.superview
        }
        return nil
    }
}

extension View {
    func hideSplitDividers() -> some View {
        background { SplitDividerHider() }
    }
}

