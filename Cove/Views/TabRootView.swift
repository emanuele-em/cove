import SwiftUI
import AppKit

struct TabRootWrapper: View {
    var body: some View {
        TabRootView()
    }
}

struct TabRootView: View {
    @State private var appState: AppState?

    var body: some View {
        Group {
            if let appState {
                ContentView()
                    .environment(appState)
                    .focusedValue(\.appState, appState)
            }
        }
        .background {
            PerWindowSetup(appState: $appState)
                .frame(width: 0, height: 0)
                .clipped()
        }
        .onDisappear {
            guard let appState else { return }
            if !appState.shared.isTerminating {
                appState.saveSession()
                appState.unregister()
                appState.shared.removeTabSession(appState.tabId)
            }
        }
    }
}

// MARK: - Per-window AppState initializer (bypasses @State Specter bug)

struct PerWindowSetup: NSViewRepresentable {
    @Binding var appState: AppState?

    final class Coordinator {
        var initialized = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard !context.coordinator.initialized else { return }
            context.coordinator.initialized = true

            let state = AppState()
            state.register()
            self.appState = state
            Task { await state.restoreSession() }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let state = appState, state.window == nil, let window = nsView.window {
            state.window = window
        }
    }
}

// MARK: - FocusedValue key for per-tab AppState

extension FocusedValues {
    @Entry var appState: AppState?
}
