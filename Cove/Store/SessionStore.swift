import Foundation

struct EnvironmentSession: Codable {
    var activeConnectionId: UUID?
    var selectedPath: [String]?
    var expandedPaths: Set<[String]>?
    var showInspector: Bool?
    var showQueryEditor: Bool?
}

// MARK: - Multi-tab session models

struct TabSession: Codable {
    var tabId: UUID
    var showSidebar: Bool
    var sidebarWidth: CGFloat?
    var selectedEnvironment: ConnectionEnvironment?
    var environments: [String: EnvironmentSession]?
}

struct MultiTabSessionState: Codable {
    var tabs: [TabSession]
}

// MARK: - Legacy single-tab model (for migration)

struct SessionState: Codable {
    var showSidebar: Bool
    var sidebarWidth: CGFloat?
    var selectedEnvironment: ConnectionEnvironment?
    var environments: [String: EnvironmentSession]?

    // Legacy fields — read from old session.json, never written
    var activeConnectionId: UUID?
    var selectedPath: [String]?
    var expandedPaths: Set<[String]>?
    var showInspector: Bool?
    var showQueryEditor: Bool?
}

enum SessionStoreIO {
    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Cove/session.json")
    }

    /// Load multi-tab session state, migrating from old format if needed.
    static func load() -> MultiTabSessionState? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        // Try new multi-tab format first
        if let multi = try? JSONDecoder().decode(MultiTabSessionState.self, from: data),
           !multi.tabs.isEmpty {
            return multi
        }

        // Fall back to old single-tab format and migrate
        guard let old = try? JSONDecoder().decode(SessionState.self, from: data) else {
            return nil
        }

        // Use a deterministic UUID so SwiftUI window restoration can match it
        let migrationId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        var environments = old.environments
        if environments == nil, old.activeConnectionId != nil {
            let env = old.selectedEnvironment ?? .local
            environments = [env.rawValue: EnvironmentSession(
                activeConnectionId: old.activeConnectionId,
                selectedPath: old.selectedPath,
                expandedPaths: old.expandedPaths,
                showInspector: old.showInspector,
                showQueryEditor: old.showQueryEditor
            )]
        }

        let tab = TabSession(
            tabId: migrationId,
            showSidebar: old.showSidebar,
            sidebarWidth: old.sidebarWidth,
            selectedEnvironment: old.selectedEnvironment,
            environments: environments
        )

        let multi = MultiTabSessionState(tabs: [tab])
        saveMulti(multi)
        return multi
    }

    static func saveMulti(_ state: MultiTabSessionState) {
        guard let url = fileURL else { return }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Cove] Failed to save session: \(error)")
        }
    }
}
