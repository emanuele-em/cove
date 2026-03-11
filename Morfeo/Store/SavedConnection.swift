import Foundation

struct SavedConnection: Codable, Identifiable {
    var id = UUID()
    var name: String
    var backend: BackendType
    var host: String
    var port: String
    var user: String
    var password: String
    var database: String
    var colorHex: String?

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
}
