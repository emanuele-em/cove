import SwiftUI

struct TreeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(state.tree.flatItems) { item in
                    treeRow(item)
                        .padding(.leading, CGFloat(item.depth) * 10)
                        .contextMenu { contextMenuItems(for: item.path) }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .contextMenu { contextMenuItems(for: []) }
    }

    private func treeRow(_ item: FlatTreeItem) -> some View {
        HStack(spacing: 4) {
            if item.expandable {
                Button {
                    state.treeToggleExpansion(path: item.path)
                } label: {
                    Image(systemName: item.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 12)
            }

            Button {
                state.treeSelectNode(path: item.path)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(item.tint.color)
                        .saturation(1.5)
                        .frame(width: 14)

                    Text(item.label)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(
                    item.selected
                        ? RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                        : nil
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for path: [String]) -> some View {
        if let label = state.connection?.creatableChildLabel(path: path) {
            Button("New \(label)...") {
                state.promptCreateChild(parentPath: path)
            }
        }
        if state.connection?.isDeletable(path: path) == true {
            Divider()
            Button("Drop \(path.last ?? "")...", role: .destructive) {
                state.promptDeleteNode(path: path)
            }
        }
    }
}
