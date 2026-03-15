import Foundation

enum QueryStoreIO {
    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Cove/queries.json")
    }

    static func load() -> [String: String] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return store
    }

    static func save(_ store: [String: String]) {
        guard let url = fileURL else { return }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Cove] Failed to save queries: \(error)")
        }
    }
}
