import Foundation

enum BackendType: String, Codable, CaseIterable, Sendable {
    case postgres
    case mysql
    case scylladb
    case cassandra
    case redis
    case mariadb
    case mongodb
    case sqlite
    case elasticsearch

    var displayName: String {
        switch self {
        case .postgres: "PostgreSQL"
        case .mysql: "MySQL"
        case .scylladb: "ScyllaDB"
        case .cassandra: "Cassandra"
        case .redis: "Redis"
        case .mariadb: "MariaDB"
        case .mongodb: "MongoDB"
        case .sqlite: "SQLite"
        case .elasticsearch: "Elasticsearch"
        }
    }

    var iconAsset: String {
        switch self {
        case .postgres: "postgres-logo"
        case .mysql: "mysql-logo"
        case .scylladb: "scylladb-logo"
        case .cassandra: "cassandra-logo"
        case .redis: "redis-logo"
        case .mariadb: "mariadb-logo"
        case .mongodb: "mongodb-logo"
        case .sqlite: "sqlite-logo"
        case .elasticsearch: "elasticsearch-logo"
        }
    }

    var defaultPort: String {
        switch self {
        case .postgres: "5432"
        case .mysql: "3306"
        case .scylladb: "9042"
        case .cassandra: "9042"
        case .redis: "6379"
        case .mariadb: "3306"
        case .mongodb: "27017"
        case .sqlite: "0"
        case .elasticsearch: "9200"
        }
    }

    var isFileBased: Bool {
        switch self {
        case .sqlite: true
        default: false
        }
    }
}

enum SSHAuthMethod: String, Codable, Sendable, CaseIterable {
    case password
    case privateKey

    var displayName: String {
        switch self {
        case .password: "Password"
        case .privateKey: "Private Key"
        }
    }
}

struct SSHTunnelConfig: Codable, Sendable {
    var sshHost: String
    var sshPort: String
    var sshUser: String
    var authMethod: SSHAuthMethod
    var sshPassword: String?
    var privateKeyPath: String?
    var passphrase: String?
}

struct ConnectionConfig: Sendable {
    let backend: BackendType
    let host: String
    let port: String
    let user: String
    let password: String
    let database: String
    let sshTunnel: SSHTunnelConfig?

    init(backend: BackendType, host: String, port: String, user: String, password: String, database: String, sshTunnel: SSHTunnelConfig? = nil) {
        self.backend = backend
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.sshTunnel = sshTunnel
    }
}

func coveConnect(config: ConnectionConfig) async throws -> (any DatabaseBackend, SSHTunnel?) {
    var effectiveConfig = config
    var tunnel: SSHTunnel?

    if let sshConfig = config.sshTunnel {
        let remoteHost = config.host
        let remotePort = Int(config.port) ?? 0
        tunnel = try await SSHTunnel.establish(
            config: sshConfig,
            remoteHost: remoteHost,
            remotePort: remotePort
        )
        effectiveConfig = ConnectionConfig(
            backend: config.backend,
            host: "127.0.0.1",
            port: String(tunnel!.localPort),
            user: config.user,
            password: config.password,
            database: config.database
        )
    }

    do {
        let backend: any DatabaseBackend
        switch effectiveConfig.backend {
        case .postgres:
            backend = try await PostgresBackend.connect(config: effectiveConfig)
        case .mysql:
            backend = try await MySQLBackend.connect(config: effectiveConfig)
        case .scylladb:
            backend = try await ScyllaBackend.connect(config: effectiveConfig)
        case .cassandra:
            backend = try await CassandraBackend.connect(config: effectiveConfig)
        case .redis:
            backend = try await RedisBackend.connect(config: effectiveConfig)
        case .mariadb:
            backend = try await MariaDBBackend.connect(config: effectiveConfig)
        case .mongodb:
            backend = try await MongoDBBackend.connect(config: effectiveConfig)
        case .sqlite:
            backend = try await SQLiteBackend.connect(config: effectiveConfig)
        case .elasticsearch:
            backend = try await ElasticsearchBackend.connect(config: effectiveConfig)
        }
        return (backend, tunnel)
    } catch {
        await tunnel?.close()
        throw error
    }
}
