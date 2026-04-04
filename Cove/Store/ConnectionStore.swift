import Foundation

struct ConnectionStore: Codable {
    var connections: [SavedConnection] = []
}

enum ConnectionStoreIO {
    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Cove/connections.json")
    }

    static func load() -> ConnectionStore {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else {
            return ConnectionStore()
        }

        // Try loading with the new schema (no passwords in JSON)
        var store = (try? JSONDecoder().decode(ConnectionStore.self, from: data)) ?? ConnectionStore()

        // Migration: check if old JSON had passwords inline
        let needsMigration = migratePasswordsIfNeeded(data: data, store: &store)

        for i in store.connections.indices {
            store.connections[i].loadPasswords()
        }

        if needsMigration {
            save(store)
        }

        return store
    }

    static func save(_ store: ConnectionStore) {
        guard let url = fileURL else { return }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            for conn in store.connections {
                conn.savePasswords()
            }

            // JSON is written without password fields (custom CodingKeys)
            let data = try JSONEncoder().encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Cove] Failed to save connections: \(error)")
        }
    }

    // MARK: - Migration from plaintext passwords

    /// Reads old-format JSON that had password fields inline. Migrates them to Keychain.
    /// Returns true if migration occurred.
    private static func migratePasswordsIfNeeded(data: Data, store: inout ConnectionStore) -> Bool {
        guard let jsonArray = parseOldFormatPasswords(data: data) else { return false }

        var migrated = false
        for i in store.connections.indices {
            let id = store.connections[i].id.uuidString.lowercased()
            guard let entry = jsonArray.first(where: {
                ($0["id"] as? String)?.lowercased() == id
            }) else { continue }

            if let pw = entry["password"] as? String, !pw.isEmpty,
               store.connections[i].password.isEmpty {
                store.connections[i].password = pw
                migrated = true
            }
            if let pw = entry["sshPassword"] as? String, !pw.isEmpty,
               store.connections[i].sshPassword == nil {
                store.connections[i].sshPassword = pw
                migrated = true
            }
            if let pw = entry["sshPassphrase"] as? String, !pw.isEmpty,
               store.connections[i].sshPassphrase == nil {
                store.connections[i].sshPassphrase = pw
                migrated = true
            }
        }
        return migrated
    }

    private static func parseOldFormatPasswords(data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let conns = json["connections"] as? [[String: Any]] else { return nil }
        let hasPasswords = conns.contains { entry in
            if let pw = entry["password"] as? String, !pw.isEmpty { return true }
            if let pw = entry["sshPassword"] as? String, !pw.isEmpty { return true }
            if let pw = entry["sshPassphrase"] as? String, !pw.isEmpty { return true }
            return false
        }
        return hasPasswords ? conns : nil
    }
}
