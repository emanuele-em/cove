import Foundation

struct SessionState: Codable {
    var activeConnectionId: UUID?
    var selectedPath: [String]?
    var expandedPaths: Set<[String]>?
    var showInspector: Bool
    var showSidebar: Bool
    var sidebarWidth: CGFloat?
    var showQueryEditor: Bool?
}

enum SessionStoreIO {
    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Cove/session.json")
    }

    static func load() -> SessionState? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SessionState.self, from: data) else {
            return nil
        }
        return state
    }

    static func save(_ state: SessionState) {
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
