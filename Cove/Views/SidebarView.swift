import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                VisualEffectBackground(material: .sidebar)
            }
    }

    @ViewBuilder
    private var content: some View {
        if state.connecting {
            ProgressView("Connecting...")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.connection == nil {
            Text("Connect to a database")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(20)
        } else {
            TreeView()
                .sheet(isPresented: Bindable(state).showCreateSheet) {
                    CreateChildSheet()
                        .environment(state)
                }
                .sheet(isPresented: Bindable(state).showTreeAction) {
                    DropConfirmSheet()
                        .environment(state)
                }
        }
    }
}

// MARK: - Create sheet with form fields + live SQL preview

struct CreateChildSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private var sqlPreview: String? {
        state.connection?.generateCreateChildSQL(
            path: state.createSheetParentPath,
            values: values
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New \(state.createSheetLabel)")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Form {
                ForEach(state.createSheetFields) { field in
                    if let options = field.options {
                        Picker(field.label, selection: binding(for: field)) {
                            ForEach(options, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } else {
                        TextField(
                            field.label,
                            text: binding(for: field),
                            prompt: Text(field.placeholder)
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 4)

            Text("SQL Preview")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ScrollView {
                Text(sqlPreview ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(sqlPreview != nil ? .primary : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 80)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Execute") {
                    state.executeCreateChild(values: values)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(sqlPreview == nil)
            }
            .padding(16)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background()
        .onAppear {
            for field in state.createSheetFields {
                values[field.id] = field.defaultValue
            }
        }
    }

    private func binding(for field: CreateField) -> Binding<String> {
        Binding(
            get: { values[field.id] ?? field.defaultValue },
            set: { values[field.id] = $0 }
        )
    }
}

// MARK: - Drop confirmation sheet with SQL preview

struct DropConfirmSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confirm Drop")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                Text(state.treeActionSQL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Execute") {
                    state.executeTreeAction()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 280)
        .background()
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
