import Foundation
import CassandraClient

final class ScyllaBackend: DatabaseBackend, @unchecked Sendable {
    let name = "ScyllaDB"
    let client: CassandraClient

    let syntaxKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "KEYSPACE", "TYPE",
        "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE",
        "ORDER", "BY", "GROUP", "LIMIT", "DISTINCT",
        "ALL", "IF", "EXISTS", "VALUES", "PRIMARY",
        "KEY", "CLUSTERING", "PARTITION", "STATIC", "FROZEN",
        "WITH", "USING", "TTL", "TIMESTAMP", "WRITETIME",
        "MAP", "LIST", "TUPLE",
        "ASCII", "BIGINT", "BLOB", "BOOLEAN", "COUNTER", "DATE",
        "DECIMAL", "DOUBLE", "DURATION", "FLOAT", "INET", "INT",
        "SMALLINT", "TEXT", "TIME", "TIMEUUID", "TINYINT",
        "UUID", "VARCHAR", "VARINT",
        "COUNT", "SUM", "AVG", "MIN", "MAX",
        "TOKEN", "ALLOW", "FILTERING", "MATERIALIZED", "VIEW",
        "FUNCTION", "AGGREGATE", "RETURNS", "CALLED", "INPUT",
        "LANGUAGE", "AS", "ON", "TO", "GRANT", "REVOKE",
        "DESCRIBE", "USE", "BATCH", "BEGIN", "APPLY",
        "TRUE", "FALSE", "ASC", "DESC", "CONTAINS",
        "COMPACT", "STORAGE", "REPLICATION", "DURABLE_WRITES",
    ]

    private init(client: CassandraClient) {
        self.client = client
    }

    static func connect(config: ConnectionConfig) async throws -> ScyllaBackend {
        let host = config.host
        var configuration = CassandraClient.Configuration(
            contactPointsProvider: { callback in
                callback(.success([host]))
            },
            port: Int32(config.port) ?? 9042,
            protocolVersion: .v4
        )
        if !config.user.isEmpty { configuration.username = config.user }
        if !config.password.isEmpty { configuration.password = config.password }

        let client = CassandraClient(configuration: configuration)

        do {
            _ = try await client.query("SELECT cluster_name FROM system.local")
        } catch {
            try? client.shutdown()
            throw DbError.connection(error.localizedDescription)
        }

        return ScyllaBackend(client: client)
    }

    deinit {
        try? client.shutdown()
    }
}
