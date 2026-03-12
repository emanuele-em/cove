import Foundation
import CryptoKit

enum SecretStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?

    private static var supportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Cove")
    }

    private static var keyURL: URL? { supportDir?.appendingPathComponent(".secrets.key") }
    private static var storeURL: URL? { supportDir?.appendingPathComponent(".secrets") }

    // MARK: - Symmetric key

    private static func loadOrCreateKey() -> SymmetricKey? {
        if let cachedKey { return cachedKey }
        guard let keyURL, let dir = supportDir else { return nil }

        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[Cove] SecretStore: failed to create directory: \(error)")
            return nil
        }

        guard FileManager.default.createFile(
            atPath: keyURL.path, contents: keyData,
            attributes: [.posixPermissions: 0o600]
        ) else {
            print("[Cove] SecretStore: failed to write key file")
            return nil
        }

        cachedKey = key
        return key
    }

    // MARK: - Encrypted store

    private static func loadStore() -> [String: String] {
        guard let url = storeURL, let key = loadOrCreateKey() else { return [:] }

        guard let encrypted = try? Data(contentsOf: url) else { return [:] }

        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([String: String].self, from: decrypted)
        } catch {
            print("[Cove] SecretStore: failed to decrypt secrets: \(error)")
            return [:]
        }
    }

    private static func saveStore(_ dict: [String: String]) {
        guard let url = storeURL, let key = loadOrCreateKey() else { return }

        do {
            let data = try JSONEncoder().encode(dict)
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return }
            try combined.write(to: url, options: .atomic)
        } catch {
            print("[Cove] SecretStore: failed to save secrets: \(error)")
        }
    }

    // MARK: - Public API

    static func save(account: String, password: String) {
        lock.withLock {
            var store = loadStore()
            store[account] = password
            saveStore(store)
        }
    }

    static func load(account: String) -> String? {
        lock.withLock {
            loadStore()[account]
        }
    }

    static func delete(account: String) {
        lock.withLock {
            var store = loadStore()
            store.removeValue(forKey: account)
            saveStore(store)
        }
    }
}
