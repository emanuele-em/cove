import SwiftUI
import AppKit

@main
struct CoveApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.restoreSession() }
                .onAppear { configureWindow() }
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }

    private func configureWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApplication.shared.windows {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        }
    }
}
