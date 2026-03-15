import Foundation
import PostgresNIO
import Logging

final class PostgresBackend: DatabaseBackend, @unchecked Sendable {
    let name = "PostgreSQL"
    private let config: ConnectionConfig
    private let lock = NSLock()
    private var clients: [String: PostgresClient] = [:]
    private var runningTasks: [String: Task<Void, any Error>] = [:]

    let syntaxKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "AS",
        "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS",
        "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "DISTINCT",
        "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN",
        "COMMIT", "ROLLBACK", "TRANSACTION", "VALUES", "DEFAULT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT", "CHECK",
        "UNIQUE", "ASC", "DESC", "WITH", "RECURSIVE", "RETURNING", "GRANT",
        "REVOKE", "TRUNCATE", "EXPLAIN", "ANALYZE", "VACUUM", "TRIGGER",
        "FUNCTION", "PROCEDURE", "IF", "THEN", "ELSIF", "LOOP", "WHILE",
        "FOR", "FETCH", "CURSOR", "DECLARE", "EXECUTE", "PERFORM",
        "BOOLEAN", "INTEGER", "BIGINT", "SMALLINT", "TEXT", "VARCHAR",
        "CHAR", "NUMERIC", "DECIMAL", "REAL", "FLOAT", "DOUBLE", "DATE",
        "TIME", "TIMESTAMP", "INTERVAL", "UUID", "JSON", "JSONB", "SERIAL",
        "BIGSERIAL", "TRUE", "FALSE", "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "CAST", "OVER", "PARTITION", "ROW_NUMBER", "RANK",
        "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
    ]

    private init(config: ConnectionConfig) {
        self.config = config
    }

    static func connect(config: ConnectionConfig) async throws -> PostgresBackend {
        let backend = PostgresBackend(config: config)

        let client = backend.makeClient(database: config.database)
        backend.addClient(client, key: "__default__")

        let rows = try await client.query("SELECT current_database()")
        var dbName = "postgres"
        for try await row in rows {
            dbName = try row.decode(String.self, context: .default)
        }

        backend.lock.withLock {
            backend.clients[dbName] = client
            if let task = backend.runningTasks.removeValue(forKey: "__default__") {
                backend.runningTasks[dbName] = task
            }
            backend.clients.removeValue(forKey: "__default__")
        }

        return backend
    }

    // MARK: - Pool management

    private func makeClient(database: String) -> PostgresClient {
        let port = Int(config.port) ?? 5432
        let pgConfig = PostgresClient.Configuration(
            host: config.host,
            port: port,
            username: config.user,
            password: config.password.isEmpty ? nil : config.password,
            database: database.isEmpty ? nil : database,
            tls: .disable
        )
        return PostgresClient(configuration: pgConfig)
    }

    private func addClient(_ client: PostgresClient, key: String) {
        lock.withLock {
            clients[key] = client
            if runningTasks[key] == nil {
                let task = Task { try await client.run() }
                runningTasks[key] = task
            }
        }
    }

    func getAnyClient() throws -> PostgresClient {
        try lock.withLock {
            clients.values.first
        }.orThrow(DbError.connection("no connection available"))
    }

    func clientFor(database: String) async throws -> PostgresClient {
        let existing: PostgresClient? = lock.withLock { clients[database] }
        if let existing { return existing }

        let client = makeClient(database: database)
        addClient(client, key: database)
        return client
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Helpers

extension PSQLError {
    var serverMessage: String {
        if let msg = serverInfo?[.message] {
            return msg
        }
        return String(reflecting: self)
    }
}

extension Optional {
    func orThrow(_ error: @autoclosure () -> some Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
