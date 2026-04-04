import Foundation
import AppKit

@Observable
@MainActor
final class SharedStore {
    static let shared = SharedStore()

    var savedConnections: [SavedConnection]
    var savedQueries: [String: String]
    var activeTabs: [UUID: AppState] = [:]
    var isTerminating = false

    private var tabSessions: [UUID: TabSession] = [:]
    private var pendingRestorations: [TabSession] = []
    let savedTabCount: Int

    private init() {
        let store = ConnectionStoreIO.load()
        let multi = SessionStoreIO.load()

        self.savedConnections = store.connections
        self.savedQueries = QueryStoreIO.load()
        self.savedTabCount = multi?.tabs.count ?? 0

        if let tabs = multi?.tabs {
            for tab in tabs {
                tabSessions[tab.tabId] = tab
            }
            pendingRestorations = tabs
        }
    }

    // MARK: - Tab restoration

    /// Each restored window claims the next saved session in order.
    /// Removes the old entry so it won't duplicate when re-saved under a new tabId.
    func claimNextSession() -> TabSession? {
        guard !pendingRestorations.isEmpty else {
            print("[Cove] claimNextSession: queue empty")
            return nil
        }
        let session = pendingRestorations.removeFirst()
        tabSessions.removeValue(forKey: session.tabId)
        let hasEnv = session.environments?.isEmpty == false
        print("[Cove] claimNextSession: tab=\(session.tabId.uuidString.prefix(8)), hasEnvironments=\(hasEnv), remaining=\(pendingRestorations.count)")
        return session
    }

    /// Call after all windows have been restored to discard unclaimed stale sessions.
    func cleanupUnclaimedSessions() {
        let activeIds = Set(activeTabs.keys)
        tabSessions = tabSessions.filter { activeIds.contains($0.key) }
        persistAllSessions()
    }

    func saveConnections() {
        ConnectionStoreIO.save(ConnectionStore(connections: savedConnections))
    }

    func saveQueries() {
        QueryStoreIO.save(savedQueries)
    }

    func saveTabSession(_ session: TabSession) {
        let hasEnv = session.environments?.isEmpty == false
        print("[Cove] saveTabSession: tab=\(session.tabId.uuidString.prefix(8)), hasEnv=\(hasEnv), totalTabs=\(tabSessions.count + 1)")
        tabSessions[session.tabId] = session
        persistAllSessions()
    }

    func removeTabSession(_ id: UUID) {
        tabSessions.removeValue(forKey: id)
        persistAllSessions()
    }

    func saveAllTabSessions() {
        print("[Cove] saveAllTabSessions: activeTabs=\(activeTabs.count), tabSessions=\(tabSessions.count)")
        for (_, state) in activeTabs {
            state.saveSession()
        }
        print("[Cove] saveAllTabSessions: after save, tabSessions=\(tabSessions.count)")

        // Read visual tab order from AppKit, then persist in that order
        let ordered = orderedSessions()
        SessionStoreIO.saveMulti(MultiTabSessionState(tabs: ordered))
    }

    private func persistAllSessions() {
        let sessions = Array(tabSessions.values)
        SessionStoreIO.saveMulti(MultiTabSessionState(tabs: sessions))
    }

    private func orderedSessions() -> [TabSession] {
        let windowToTab: [ObjectIdentifier: UUID] = activeTabs.reduce(into: [:]) { dict, entry in
            if let window = entry.value.window {
                dict[ObjectIdentifier(window)] = entry.key
            }
        }

        guard let anyWindow = activeTabs.values.first(where: { $0.window != nil })?.window,
              let tabbedWindows = anyWindow.tabbedWindows else {
            return Array(tabSessions.values)
        }

        let orderedIds = tabbedWindows.compactMap { windowToTab[ObjectIdentifier($0)] }
        let seen = Set(orderedIds)
        let remaining = tabSessions.keys.filter { !seen.contains($0) }
        return (orderedIds + remaining).compactMap { tabSessions[$0] }
    }

    func handleConnectionDeleted(id: UUID) {
        for (_, state) in activeTabs where state.activeConnectionId == id {
            state.handleConnectionDeleted()
        }
    }
}
