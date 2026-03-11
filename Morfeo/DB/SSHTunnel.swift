import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Crypto

enum SSHTunnelError: LocalizedError {
    case authFailed
    case connectionRefused(String, Int)
    case tunnelFailed
    case missingPrivateKey
    case unsupportedKeyFormat
    case encryptedKey
    case wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .authFailed: "SSH authentication failed: check credentials"
        case .connectionRefused(let host, let port): "SSH connection to \(host):\(port) failed"
        case .tunnelFailed: "Could not establish SSH tunnel"
        case .missingPrivateKey: "Private key path not specified"
        case .unsupportedKeyFormat: "Unsupported private key format"
        case .encryptedKey: "Private key is encrypted"
        case .wrongPassphrase: "Incorrect passphrase for private key"
        }
    }
}

final class SSHTunnel: @unchecked Sendable {
    let localPort: Int
    private let group: MultiThreadedEventLoopGroup
    private let serverChannel: Channel
    private let sshChannel: Channel

    private init(group: MultiThreadedEventLoopGroup, serverChannel: Channel, sshChannel: Channel, localPort: Int) {
        self.group = group
        self.serverChannel = serverChannel
        self.sshChannel = sshChannel
        self.localPort = localPort
    }

    static func establish(
        config: SSHTunnelConfig,
        remoteHost: String,
        remotePort: Int
    ) async throws -> SSHTunnel {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sshPort = Int(config.sshPort) ?? 22

        let authDelegate: any NIOSSHClientUserAuthenticationDelegate & Sendable
        switch config.authMethod {
        case .password:
            authDelegate = PasswordAuthDelegate(
                username: config.sshUser,
                password: config.sshPassword ?? ""
            )
        case .privateKey:
            guard let keyPath = config.privateKeyPath, !keyPath.isEmpty else {
                try? await group.shutdownGracefully()
                throw SSHTunnelError.missingPrivateKey
            }
            let key = try loadPrivateKey(at: keyPath, passphrase: config.passphrase)
            authDelegate = PrivateKeyAuthDelegate(username: config.sshUser, key: key)
        }

        let sshChannel: Channel
        do {
            sshChannel = try await ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(
                        NIOSSHHandler(
                            role: .client(SSHClientConfiguration(
                                userAuthDelegate: authDelegate,
                                serverAuthDelegate: AcceptAllHostKeys()
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                    )
                }
                .connectTimeout(.seconds(10))
                .connect(host: config.sshHost, port: sshPort)
                .get()
        } catch {
            try? await group.shutdownGracefully()
            throw SSHTunnelError.connectionRefused(config.sshHost, sshPort)
        }

        let sshHandler: NIOSSHHandler
        do {
            sshHandler = try await sshChannel.pipeline.handler(type: NIOSSHHandler.self).get()
        } catch {
            try? await sshChannel.close()
            try? await group.shutdownGracefully()
            throw SSHTunnelError.tunnelFailed
        }

        // Verify SSH handshake + auth by opening a test channel
        let originAddr = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        do {
            let verifyPromise = sshChannel.eventLoop.makePromise(of: Channel.self)
            sshHandler.createChannel(verifyPromise, channelType: .directTCPIP(.init(
                targetHost: remoteHost,
                targetPort: remotePort,
                originatorAddress: originAddr
            ))) { childChannel, _ in
                childChannel.eventLoop.makeSucceededVoidFuture()
            }
            let testChannel = try await verifyPromise.futureResult.get()
            try? await testChannel.close()
        } catch {
            try? await sshChannel.close()
            try? await group.shutdownGracefully()
            throw SSHTunnelError.authFailed
        }

        // Start local TCP server that forwards connections through SSH
        let rHost = remoteHost
        let rPort = remotePort
        let serverChannel: Channel
        do {
            serverChannel = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { localChannel in
                    localChannel.setOption(ChannelOptions.autoRead, value: false).flatMap {
                        let promise = localChannel.eventLoop.makePromise(of: Channel.self)
                        sshHandler.createChannel(promise, channelType: .directTCPIP(.init(
                            targetHost: rHost,
                            targetPort: rPort,
                            originatorAddress: originAddr
                        ))) { sshChild, _ in
                            sshChild.pipeline.addHandler(SSHToLocalHandler(localChannel: localChannel))
                        }
                        return promise.futureResult.flatMap { sshChild in
                            localChannel.pipeline.addHandler(LocalToSSHHandler(sshChannel: sshChild)).flatMap {
                                localChannel.setOption(ChannelOptions.autoRead, value: true)
                            }
                        }
                    }
                }
                .bind(host: "127.0.0.1", port: 0)
                .get()
        } catch {
            try? await sshChannel.close()
            try? await group.shutdownGracefully()
            throw SSHTunnelError.tunnelFailed
        }

        guard let port = serverChannel.localAddress?.port else {
            try? await serverChannel.close()
            try? await sshChannel.close()
            try? await group.shutdownGracefully()
            throw SSHTunnelError.tunnelFailed
        }

        return SSHTunnel(group: group, serverChannel: serverChannel, sshChannel: sshChannel, localPort: port)
    }

    func close() async {
        try? await serverChannel.close()
        try? await sshChannel.close()
        try? await group.shutdownGracefully()
    }
}

// MARK: - Auth Delegates

private final class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate, Sendable {
    let username: String
    let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.password) {
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .password(.init(password: password))
            ))
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

private final class PrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate, Sendable {
    let username: String
    let key: NIOSSHPrivateKey

    init(username: String, key: NIOSSHPrivateKey) {
        self.username = username
        self.key = key
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.publicKey) {
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: key))
            ))
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

private final class AcceptAllHostKeys: NIOSSHClientServerAuthenticationDelegate, Sendable {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        validationCompletePromise.succeed(())
    }
}

// MARK: - Channel Handlers

private final class SSHToLocalHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let localChannel: Channel

    init(localChannel: Channel) {
        self.localChannel = localChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = sshData.data, sshData.type == .channel else { return }
        localChannel.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        localChannel.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        localChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

private final class LocalToSSHHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let sshChannel: Channel

    init(sshChannel: Channel) {
        self.sshChannel = sshChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let sshData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        sshChannel.writeAndFlush(sshData, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        sshChannel.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        sshChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

// MARK: - Private Key Loading

private func loadPrivateKey(at path: String, passphrase: String? = nil) throws -> NIOSSHPrivateKey {
    let expandedPath = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath)
    let data = try Data(contentsOf: url)
    guard let pem = String(data: data, encoding: .utf8) else {
        throw SSHTunnelError.unsupportedKeyFormat
    }

    let lines = pem.components(separatedBy: .newlines)
    let header = lines.first(where: { $0.hasPrefix("-----BEGIN") }) ?? ""

    if header.contains("OPENSSH PRIVATE KEY") {
        let base64Lines = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        guard let keyData = Data(base64Encoded: base64Lines.joined()) else {
            throw SSHTunnelError.unsupportedKeyFormat
        }
        do {
            return try parseOpenSSHKey(keyData)
        } catch SSHTunnelError.encryptedKey {
            return try decryptViaSSHKeygen(path: expandedPath, passphrase: passphrase ?? "")
        }
    }

    // PEM-encoded key (PKCS#8 / SEC1)
    let base64Lines = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }
    guard let keyData = Data(base64Encoded: base64Lines.joined()) else {
        throw SSHTunnelError.unsupportedKeyFormat
    }

    if let p256 = try? P256.Signing.PrivateKey(derRepresentation: keyData) {
        return NIOSSHPrivateKey(p256Key: p256)
    }
    if let p384 = try? P384.Signing.PrivateKey(derRepresentation: keyData) {
        return NIOSSHPrivateKey(p384Key: p384)
    }
    if let p521 = try? P521.Signing.PrivateKey(derRepresentation: keyData) {
        return NIOSSHPrivateKey(p521Key: p521)
    }
    if keyData.count == 32 {
        let ed25519 = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        return NIOSSHPrivateKey(ed25519Key: ed25519)
    }

    throw SSHTunnelError.unsupportedKeyFormat
}

private func decryptViaSSHKeygen(path: String, passphrase: String) throws -> NIOSSHPrivateKey {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.copyItem(atPath: path, toPath: tmp.path)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // ssh-keygen -p -P <passphrase> -N "" -f <file> removes encryption in-place
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    process.arguments = ["-p", "-P", passphrase, "-N", "", "-f", tmp.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw SSHTunnelError.wrongPassphrase
    }

    let decryptedData = try Data(contentsOf: tmp)
    guard let decryptedPem = String(data: decryptedData, encoding: .utf8) else {
        throw SSHTunnelError.unsupportedKeyFormat
    }
    let lines = decryptedPem.components(separatedBy: .newlines)
    let base64Lines = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }
    guard let keyData = Data(base64Encoded: base64Lines.joined()) else {
        throw SSHTunnelError.unsupportedKeyFormat
    }
    return try parseOpenSSHKey(keyData)
}

private func parseOpenSSHKey(_ data: Data) throws -> NIOSSHPrivateKey {
    var offset = 0
    let magic = Array("openssh-key-v1\0".utf8)
    guard data.count > magic.count else { throw SSHTunnelError.unsupportedKeyFormat }

    for (i, b) in magic.enumerated() {
        guard data[i] == b else { throw SSHTunnelError.unsupportedKeyFormat }
    }
    offset = magic.count

    func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw SSHTunnelError.unsupportedKeyFormat }
        let v = UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 |
                UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
        offset += 4
        return v
    }

    func readString() throws -> Data {
        let len = Int(try readUInt32())
        guard offset + len <= data.count else { throw SSHTunnelError.unsupportedKeyFormat }
        let result = data[offset..<offset+len]
        offset += len
        return Data(result)
    }

    let cipherName = String(data: try readString(), encoding: .utf8) ?? ""
    let kdfName = String(data: try readString(), encoding: .utf8) ?? ""
    _ = try readString() // kdf options

    guard cipherName == "none" && kdfName == "none" else {
        throw SSHTunnelError.encryptedKey
    }

    let numKeys = try readUInt32()
    guard numKeys == 1 else { throw SSHTunnelError.unsupportedKeyFormat }

    _ = try readString() // public key blob
    let privateSection = try readString()

    // Parse private section
    let pData = privateSection
    var pOff = 0

    func pReadUInt32() throws -> UInt32 {
        guard pOff + 4 <= pData.count else { throw SSHTunnelError.unsupportedKeyFormat }
        let v = UInt32(pData[pOff]) << 24 | UInt32(pData[pOff+1]) << 16 |
                UInt32(pData[pOff+2]) << 8 | UInt32(pData[pOff+3])
        pOff += 4
        return v
    }

    func pReadString() throws -> Data {
        let len = Int(try pReadUInt32())
        guard pOff + len <= pData.count else { throw SSHTunnelError.unsupportedKeyFormat }
        let result = pData[pOff..<pOff+len]
        pOff += len
        return Data(result)
    }

    let check1 = try pReadUInt32()
    let check2 = try pReadUInt32()
    guard check1 == check2 else { throw SSHTunnelError.unsupportedKeyFormat }

    let keyType = String(data: try pReadString(), encoding: .utf8) ?? ""

    switch keyType {
    case "ssh-ed25519":
        _ = try pReadString() // public key (32 bytes)
        let combined = try pReadString() // 64 bytes: private (32) + public (32)
        guard combined.count == 64 else { throw SSHTunnelError.unsupportedKeyFormat }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: combined.prefix(32))
        return NIOSSHPrivateKey(ed25519Key: key)

    case "ecdsa-sha2-nistp256":
        _ = try pReadString() // curve identifier
        _ = try pReadString() // public key
        let privateKeyData = try pReadString()
        let key = try P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return NIOSSHPrivateKey(p256Key: key)

    case "ecdsa-sha2-nistp384":
        _ = try pReadString()
        _ = try pReadString()
        let privateKeyData = try pReadString()
        let key = try P384.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return NIOSSHPrivateKey(p384Key: key)

    case "ecdsa-sha2-nistp521":
        _ = try pReadString()
        _ = try pReadString()
        let privateKeyData = try pReadString()
        let key = try P521.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return NIOSSHPrivateKey(p521Key: key)

    default:
        throw SSHTunnelError.unsupportedKeyFormat
    }
}
