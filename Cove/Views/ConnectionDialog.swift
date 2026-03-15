import SwiftUI

struct ConnectionDialog: View {
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var backend: BackendType = .postgres
    @State private var host = "localhost"
    @State private var port = BackendType.postgres.defaultPort
    @State private var user = ""
    @State private var password = ""
    @State private var database = ""
    @State private var selectedColor = CoveTheme.accent

    // SSH tunnel
    @State private var sshEnabled = false
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUser = ""
    @State private var sshAuthMethod: SSHAuthMethod = .password
    @State private var sshPassword = ""
    @State private var sshPrivateKeyPath = ""
    @State private var sshPassphrase = ""

    var body: some View {
        let dialog = state.dialog

        VStack(spacing: 12) {
            Text(dialog.isEditing ? "Edit Connection" : "New Connection")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            formField("Name") {
                HStack(spacing: 8) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .fixedSize()
                }
            }

            formField("Backend") {
                Picker("", selection: $backend) {
                    ForEach(BackendType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                formField("Host") {
                    TextField("Host", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                formField("Port") {
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 80)
            }

            formField("User") {
                TextField("User", text: $user)
                    .textFieldStyle(.roundedBorder)
            }

            formField("Password") {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            formField("Database") {
                TextField("Database", text: $database)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            sshSection

            if !dialog.error.isEmpty {
                Text(dialog.error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Test") {
                    syncToDialog()
                    state.dialogTest()
                }
                .disabled(dialog.testing || dialog.connecting)

                if dialog.testing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
                Button("Cancel") {
                    state.dialogCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                if dialog.isEditing {
                    Button("Save") {
                        syncToDialog()
                        state.dialogSaveEdit()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(dialog.connecting ? "Connecting..." : "Connect") {
                        syncToDialog()
                        state.dialogConnect()
                    }
                    .disabled(dialog.connecting)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
        .presentationBackground(.regularMaterial)
        .onAppear {
            name = dialog.name
            backend = dialog.backend
            host = dialog.host
            port = dialog.port
            user = dialog.user
            password = dialog.password
            database = dialog.database
            selectedColor = Color(hex: dialog.colorHex)
            sshEnabled = dialog.sshEnabled
            sshHost = dialog.sshHost
            sshPort = dialog.sshPort
            sshUser = dialog.sshUser
            sshAuthMethod = dialog.sshAuthMethod
            sshPassword = dialog.sshPassword
            sshPrivateKeyPath = dialog.sshPrivateKeyPath
            sshPassphrase = dialog.sshPassphrase
        }
        .onDisappear {
            NSColorPanel.shared.close()
        }
        .onChange(of: backend) { _, newBackend in
            port = newBackend.defaultPort
        }
        .onChange(of: dialog.testResult?.message) {
            guard let result = dialog.testResult else { return }
            let alert = NSAlert()
            alert.alertStyle = result.success ? .informational : .critical
            alert.messageText = result.success ? "Test Successful" : "Test Failed"
            alert.informativeText = result.message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            dialog.testResult = nil
        }
    }

    @ViewBuilder
    private var sshSection: some View {
        Toggle("SSH Tunnel", isOn: $sshEnabled)
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)

        if sshEnabled {
            HStack(spacing: 8) {
                formField("SSH Host") {
                    TextField("SSH Host", text: $sshHost)
                        .textFieldStyle(.roundedBorder)
                }
                formField("SSH Port") {
                    TextField("Port", text: $sshPort)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 80)
            }

            formField("SSH User") {
                TextField("SSH User", text: $sshUser)
                    .textFieldStyle(.roundedBorder)
            }

            formField("Auth Method") {
                HStack {
                    Picker("Auth Method", selection: $sshAuthMethod) {
                        ForEach(SSHAuthMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 0)
                }
            }

            if sshAuthMethod == .password {
                formField("SSH Password") {
                    SecureField("SSH Password", text: $sshPassword)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                formField("Private Key") {
                    HStack(spacing: 8) {
                        TextField("~/.ssh/id_ed25519", text: $sshPrivateKeyPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseForKeyFile()
                        }
                    }
                }

                formField("Passphrase") {
                    SecureField("Passphrase (if any)", text: $sshPassphrase)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func browseForKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "Select SSH Private Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            sshPrivateKeyPath = url.path
        }
    }

    private func syncToDialog() {
        let dialog = state.dialog
        dialog.name = name
        dialog.backend = backend
        dialog.host = host
        dialog.port = port
        dialog.user = user
        dialog.password = password
        dialog.database = database
        dialog.colorHex = selectedColor.hexString
        dialog.sshEnabled = sshEnabled
        dialog.sshHost = sshHost
        dialog.sshPort = sshPort
        dialog.sshUser = sshUser
        dialog.sshAuthMethod = sshAuthMethod
        dialog.sshPassword = sshPassword
        dialog.sshPrivateKeyPath = sshPrivateKeyPath
        dialog.sshPassphrase = sshPassphrase
    }

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
