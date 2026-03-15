import SwiftUI
import AppKit

private let coveWindowBg = NSColor(name: nil) { appearance in
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return isDark
        ? NSColor(red: 0.12, green: 0.14, blue: 0.28, alpha: 0.45)
        : NSColor(red: 0.68, green: 0.74, blue: 0.88, alpha: 0.45)
}

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
            window.backgroundColor = coveWindowBg
            window.titlebarAppearsTransparent = true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApplication.shared.windows {
            window.isOpaque = false
            window.backgroundColor = coveWindowBg
            window.titlebarAppearsTransparent = true
        }
    }
}
