import SwiftUI

struct RowInspectorView: View {
    @Environment(AppState.self) private var state
    let table: TableState
    @FocusState private var focusedField: Int?

    var body: some View {
        if let rowIdx = table.selectedRow, rowIdx < table.rows.count {
            let isNew = table.isNewRow(rowIdx)
            let isDeleted = table.isDeletedRow(rowIdx)
            let isEditable = !isDeleted && state.isEditableTable

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
            .onAppear { applyFocus() }
            .onChange(of: state.focusedColumn) { applyFocus() }
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

    private func applyFocus() {
        if let col = state.focusedColumn {
            focusedField = col
        }
    }

    private func editableFieldRow(rowIdx: Int, colIdx: Int, name: String) -> some View {
        let hasEdit = table.hasEdit(row: rowIdx, col: colIdx)

        let binding = Binding<String>(
            get: { table.effectiveValue(row: rowIdx, col: colIdx) ?? "" },
            set: { state.inspectorFieldChanged(col: colIdx, value: $0) }
        )

        return VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("NULL", text: binding, axis: .vertical)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .foregroundStyle(hasEdit ? Color.green : .primary)
                .focused($focusedField, equals: colIdx)
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
}
