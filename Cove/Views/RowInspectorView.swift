import SwiftUI

struct RowInspectorView: View {
    @Environment(AppState.self) private var state
    let table: TableState
    @State private var drafts: [Int: String] = [:]
    @FocusState private var focusedField: Int?

    var body: some View {
        if let rowIdx = table.selectedRow, rowIdx < table.rows.count {
            let hasPK = table.columns.contains { $0.isPrimaryKey }
            let isNew = table.isNewRow(rowIdx)
            let isDeleted = table.isDeletedRow(rowIdx)
            let isEditable = hasPK && !isDeleted

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(isNew ? "New Row" : "Row \(rowIdx + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isNew ? Color.green : (isDeleted ? .red : .primary))
                    Spacer()
                    if isDeleted {
                        Text("Deleting")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(table.columns.enumerated()), id: \.offset) { colIdx, col in
                            if isEditable {
                                editableFieldRow(
                                    rowIdx: rowIdx,
                                    colIdx: colIdx,
                                    name: col.name
                                )
                            } else {
                                readOnlyFieldRow(
                                    name: col.name,
                                    value: table.rows[rowIdx][colIdx]
                                )
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background {
                VisualEffectBackground(material: .sidebar)
            }
            .onKeyPress(.escape) {
                if focusedField != nil {
                    focusedField = nil
                    return .handled
                }
                return .ignored
            }
            .onAppear { applyFocus(rowIdx: rowIdx) }
            .onChange(of: state.focusedColumn) { applyFocus(rowIdx: rowIdx) }
            .onChange(of: table.selectedRow) { _, _ in resetDrafts() }
            .onChange(of: focusedField) { oldField, _ in
                if let old = oldField, let rowIdx = table.selectedRow {
                    confirmField(colIdx: old, rowIdx: rowIdx)
                }
            }
        } else {
            Text("Select a row to inspect")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    VisualEffectBackground(material: .sidebar)
                }
        }
    }

    private func applyFocus(rowIdx: Int) {
        if let col = state.focusedColumn {
            let effective = table.effectiveValue(row: rowIdx, col: col)
            drafts[col] = effective ?? ""
            focusedField = col
        }
    }

    private func resetDrafts() {
        drafts.removeAll()
    }

    private func editableFieldRow(rowIdx: Int, colIdx: Int, name: String) -> some View {
        let effective = table.effectiveValue(row: rowIdx, col: colIdx)
        let hasEdit = table.hasEdit(row: rowIdx, col: colIdx)
        let displayValue = effective ?? ""

        let binding = Binding<String>(
            get: { drafts[colIdx] ?? displayValue },
            set: { drafts[colIdx] = $0 }
        )

        return VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("NULL", text: binding)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .foregroundStyle(hasEdit ? Color.green : .primary)
                .focused($focusedField, equals: colIdx)
                .onSubmit { confirmField(colIdx: colIdx, rowIdx: rowIdx) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hasEdit ? Color.green.opacity(0.1) : .clear)
    }

    private func readOnlyFieldRow(name: String, value: String?) -> some View {
        let isNull = value == nil
        let display = value ?? "NULL"

        return VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(display)
                .font(.system(size: 12))
                .foregroundStyle(isNull ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confirmField(colIdx: Int, rowIdx: Int) {
        guard let draft = drafts[colIdx] else { return }
        let original = table.rows[rowIdx][colIdx] ?? ""
        guard draft != original else { return }
        state.inspectorFieldConfirmed(col: colIdx, value: draft)
    }
}
