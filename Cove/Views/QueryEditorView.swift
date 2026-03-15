import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var query = state.query

        ZStack(alignment: .bottomTrailing) {
            SQLEditorView(text: $query.text, selectedRange: $query.selectedRange, runnableRange: state.query.runnableRange, keywords: state.connection?.syntaxKeywords ?? [], completionSchema: state.completionSchema)

            HStack(spacing: 8) {
                if !state.query.error.isEmpty {
                    Text(state.query.error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                if state.query.executing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    state.executeQuery()
                } label: {
                    Label("Run Current", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(8)
        }
    }
}
