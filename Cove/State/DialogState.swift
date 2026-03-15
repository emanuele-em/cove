import Foundation

@Observable
final class DialogState {
    var name = ""
    var backend: BackendType = .postgres
    var host = "localhost"
    var port = BackendType.postgres.defaultPort
    var user = ""
    var password = ""
    var database = ""
    var error = ""
    var connecting = false
    var testing = false
    var testResult: (success: Bool, message: String)?
    var visible = false
    var editingConnectionId: UUID?
    var colorHex: String = CoveTheme.accentHex

    // SSH tunnel
    var sshEnabled = false
    var sshHost = ""
    var sshPort = "22"
    var sshUser = ""
    var sshAuthMethod: SSHAuthMethod = .password
    var sshPassword = ""
    var sshPrivateKeyPath = ""
    var sshPassphrase = ""

    var isEditing: Bool { editingConnectionId != nil }

    func reset() {
        name = ""
        backend = .postgres
        host = "localhost"
        port = backend.defaultPort
        user = ""
        password = ""
        database = ""
        error = ""
        connecting = false
        testing = false
        testResult = nil
        editingConnectionId = nil
        colorHex = CoveTheme.accentHex
        sshEnabled = false
        sshHost = ""
        sshPort = "22"
        sshUser = ""
        sshAuthMethod = .password
        sshPassword = ""
        sshPrivateKeyPath = ""
        sshPassphrase = ""
    }
}
