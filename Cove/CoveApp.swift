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
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @FocusedValue(\.appState) private var focusedTab

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        UserDefaults.standard.set(0, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup {
            TabRootWrapper()
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    guard let currentWindow = NSApp.keyWindow,
                          let windowController = currentWindow.windowController else { return }
                    windowController.newWindowForTab(nil)
                    if let newWindow = NSApp.keyWindow, currentWindow != newWindow {
                        currentWindow.addTabbedWindow(newWindow, ordered: .above)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    focusedTab?.refreshCurrentScope()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(focusedTab?.connection == nil)

                Button("Agent Mode") {
                    focusedTab?.showAgentModeAtCursor()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(focusedTab == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            styleWindow(window)
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.styleWindow(window)
        }

        let count = SharedStore.shared.savedTabCount
        guard count > 1 else { return }

        DispatchQueue.main.async {
            guard let currentWindow = NSApp.keyWindow,
                  let windowController = currentWindow.windowController else { return }
            for _ in 1..<count {
                windowController.newWindowForTab(nil)
                if let newWindow = NSApp.keyWindow, currentWindow != newWindow {
                    currentWindow.addTabbedWindow(newWindow, ordered: .above)
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SharedStore.shared.saveAllTabSessions()
        SharedStore.shared.isTerminating = true
        return .terminateNow
    }

    private func styleWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .automatic
        if window.backgroundColor?.alphaComponent == 1 {
            window.backgroundColor = coveWindowBg
        }
    }
}
