import Foundation
import SwiftUI

enum ConnectionEnvironment: String, Codable, CaseIterable, Sendable {
    case production, staging, development, local

    var displayName: String {
        switch self {
        case .production:  "Production"
        case .staging:     "Staging"
        case .development: "Development"
        case .local:       "Local"
        }
    }

    var color: Color {
        switch self {
        case .production:  .red
        case .staging:     .orange
        case .development: .blue
        case .local:       .green
        }
    }
}

struct SavedConnection: Codable, Identifiable {
    var id = UUID()
    var name: String
    var backend: BackendType
    var host: String
    var port: String
    var user: String
    var password: String = ""
    var database: String
    var colorHex: String?
    var environment: ConnectionEnvironment = .local

    // SSH tunnel (all optional for backward compatibility)
    var sshEnabled: Bool?
    var sshHost: String?
    var sshPort: String?
    var sshUser: String?
    var sshAuthMethod: SSHAuthMethod?
    var sshPassword: String?
    var sshPrivateKeyPath: String?
    var sshPassphrase: String?

    var sshTunnelConfig: SSHTunnelConfig? {
        guard sshEnabled == true, let host = sshHost, !host.isEmpty else { return nil }
        return SSHTunnelConfig(
            sshHost: host,
            sshPort: sshPort ?? "22",
            sshUser: sshUser ?? "",
            authMethod: sshAuthMethod ?? .password,
            sshPassword: sshPassword,
            privateKeyPath: sshPrivateKeyPath,
            passphrase: sshPassphrase
        )
    }

    init(
        id: UUID = UUID(), name: String, backend: BackendType,
        host: String, port: String, user: String, password: String = "",
        database: String, colorHex: String? = nil,
        environment: ConnectionEnvironment = .local,
        sshEnabled: Bool? = nil, sshHost: String? = nil,
        sshPort: String? = nil, sshUser: String? = nil,
        sshAuthMethod: SSHAuthMethod? = nil, sshPassword: String? = nil,
        sshPrivateKeyPath: String? = nil, sshPassphrase: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.colorHex = colorHex
        self.environment = environment
        self.sshEnabled = sshEnabled
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshAuthMethod = sshAuthMethod
        self.sshPassword = sshPassword
        self.sshPrivateKeyPath = sshPrivateKeyPath
        self.sshPassphrase = sshPassphrase
    }

    // Passwords are stored in Keychain, not JSON
    private enum CodingKeys: String, CodingKey {
        case id, name, backend, host, port, user, database, colorHex, environment
        case sshEnabled, sshHost, sshPort, sshUser, sshAuthMethod
        case sshPrivateKeyPath
        // password, sshPassword, sshPassphrase intentionally excluded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        backend = try c.decode(BackendType.self, forKey: .backend)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(String.self, forKey: .port)
        user = try c.decode(String.self, forKey: .user)
        database = try c.decode(String.self, forKey: .database)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        environment = try c.decodeIfPresent(ConnectionEnvironment.self, forKey: .environment) ?? .local
        sshEnabled = try c.decodeIfPresent(Bool.self, forKey: .sshEnabled)
        sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost)
        sshPort = try c.decodeIfPresent(String.self, forKey: .sshPort)
        sshUser = try c.decodeIfPresent(String.self, forKey: .sshUser)
        sshAuthMethod = try c.decodeIfPresent(SSHAuthMethod.self, forKey: .sshAuthMethod)
        sshPrivateKeyPath = try c.decodeIfPresent(String.self, forKey: .sshPrivateKeyPath)
    }

    // MARK: - Secret storage

    func savePasswords() {
        let prefix = id.uuidString
        if !password.isEmpty {
            SecretStore.save(account: "\(prefix).password", password: password)
        }
        if let sshPassword, !sshPassword.isEmpty {
            SecretStore.save(account: "\(prefix).sshPassword", password: sshPassword)
        }
        if let sshPassphrase, !sshPassphrase.isEmpty {
            SecretStore.save(account: "\(prefix).sshPassphrase", password: sshPassphrase)
        }
    }

    mutating func loadPasswords() {
        let prefix = id.uuidString
        password = SecretStore.load(account: "\(prefix).password") ?? ""
        sshPassword = SecretStore.load(account: "\(prefix).sshPassword")
        sshPassphrase = SecretStore.load(account: "\(prefix).sshPassphrase")
    }

    func deletePasswords() {
        let prefix = id.uuidString
        SecretStore.delete(account: "\(prefix).password")
        SecretStore.delete(account: "\(prefix).sshPassword")
        SecretStore.delete(account: "\(prefix).sshPassphrase")
    }
}
