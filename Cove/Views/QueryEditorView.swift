import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var query = state.query

        VStack(spacing: 0) {
            SQLEditorView(
                text: $query.text,
                selectedRange: $query.selectedRange,
                runnableRange: state.query.runnableRange,
                keywords: state.connection?.syntaxKeywords ?? [],
                completionSchema: state.completionSchema,
                isEditable: !state.query.agentExecuting,
                agentInputVisible: $query.agentInputVisible,
                agentTargetRange: $query.agentTargetRange,
                onAgentMode: { range in
                    state.query.showAgentMode(for: range)
                },
                onAgentCancel: {
                    state.cancelQueryAgentGeneration()
                }
            ) {
                AnyView(AgentComposer().environment(state))
            }
            .frame(minWidth: 320)

            Divider()
            QueryEditorControls()
        }
    }
}
