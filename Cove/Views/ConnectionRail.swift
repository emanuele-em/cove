import SwiftUI

struct ConnectionRail: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                addButton

                ForEach(state.connectionsForSelectedEnvironment) { conn in
                    connectionButton(conn)
                }
            }
        }
        .safeAreaPadding(.top, 8)
        .frame(width: 50)
        .frame(maxHeight: .infinity)
        .background(.clear)
    }

    private var addButton: some View {
        Button {
            state.openDialog()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func connectionButton(_ conn: SavedConnection) -> some View {
        let isActive = state.activeConnectionId == conn.id
        let color = Color(hex: conn.colorHex ?? CoveTheme.accentHex)
        return Button {
            state.selectConnection(conn.id)
        } label: {
            VStack(spacing: 1) {
                Image(conn.backend.iconAsset)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text(abbreviate(conn.name))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .background(color.opacity(isActive ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if state.activeConnectionId == conn.id {
                Button("Disconnect") {
                    state.disconnect()
                }
                Divider()
            }
            Button("Edit") {
                state.openEditDialog(for: conn)
            }
            Button("Delete", role: .destructive) {
                state.requestDeleteConnection(conn)
            }
        }
    }

    private func abbreviate(_ name: String) -> String {
        let words = name.split(separator: " ")
        switch words.count {
        case 0: return "??"
        case 1: return String(words[0].prefix(2)).uppercased()
        default:
            let a = words[0].first ?? Character("?")
            let b = words[1].first ?? Character("?")
            return "\(a)\(b)".uppercased()
        }
    }
}
