import Foundation
import MySQLNIO
import NIOSSL
import NIOCore
import Logging

final class MySQLBackend: DatabaseBackend, @unchecked Sendable {
    let name = "MySQL"
    private let config: ConnectionConfig
    private let lock = NSLock()
    private var connections: [String: MySQLConnection] = [:]

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
        "REVOKE", "TRUNCATE", "EXPLAIN", "ANALYZE", "TRIGGER",
        "FUNCTION", "PROCEDURE", "IF", "THEN", "LOOP", "WHILE",
        "FOR", "FETCH", "CURSOR", "DECLARE", "EXECUTE",
        "BOOLEAN", "INTEGER", "BIGINT", "SMALLINT", "TEXT", "VARCHAR",
        "CHAR", "NUMERIC", "DECIMAL", "REAL", "FLOAT", "DOUBLE", "DATE",
        "TIME", "TIMESTAMP", "JSON", "SERIAL",
        "TRUE", "FALSE", "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "CAST", "OVER", "PARTITION", "ROW_NUMBER", "RANK",
        "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        "ENGINE", "AUTO_INCREMENT", "SHOW", "DESCRIBE", "USE", "DATABASES",
        "UNSIGNED", "TINYINT", "MEDIUMINT", "MEDIUMTEXT", "LONGTEXT",
        "BLOB", "DATETIME", "YEAR", "BINARY", "VARBINARY",
        "IF EXISTS", "IF NOT EXISTS",
    ]

    private init(config: ConnectionConfig) {
        self.config = config
    }

    deinit {
        // Empty the dictionary so Swift doesn't auto-destroy active connections.
        // Capture each conn in the close callback to keep it alive until the
        // channel is actually closed — MySQLConnection.deinit asserts !isActive.
        let conns = lock.withLock { () -> [MySQLConnection] in
            let values = Array(connections.values)
            connections.removeAll()
            return values
        }
        for conn in conns {
            conn.close().whenComplete { _ in _ = conn }
        }
    }

    static func connect(config: ConnectionConfig) async throws -> MySQLBackend {
        let backend = MySQLBackend(config: config)

        let conn = try await backend.openConnection(database: config.database)

        let rows = try await conn.simpleQuery("SELECT DATABASE()").get()
        let dbName = rows.first?.column("DATABASE()")?.string ?? config.database

        backend.lock.withLock { backend.connections[dbName] = conn }
        return backend
    }

    // MARK: - Connection management

    private func openConnection(database: String) async throws -> MySQLConnection {
        let addr: SocketAddress
        do {
            addr = try SocketAddress.makeAddressResolvingHost(config.host, port: Int(config.port) ?? 3306)
        } catch {
            throw DbError.connection(error.localizedDescription)
        }

        let pw = config.password.isEmpty ? nil : config.password
        let el = MultiThreadedEventLoopGroup.singleton.any()

        // MySQLNIO has no "prefer TLS" mode and its deinit asserts the channel
        // is closed, so a failed TLS attempt crashes. Connect without TLS first
        // (matching MySQL's default), then fall back to TLS for servers that
        // require encrypted connections.
        do {
            return try await MySQLConnection.connect(
                to: addr, username: config.user, database: database,
                password: pw, tlsConfiguration: nil, on: el
            ).get()
        } catch let plainError {
            do {
                var tls = TLSConfiguration.makeClientConfiguration()
                tls.certificateVerification = .none
                return try await MySQLConnection.connect(
                    to: addr, username: config.user, database: database,
                    password: pw, tlsConfiguration: tls, on: el
                ).get()
            } catch {
                throw DbError.connection(plainError.localizedDescription)
            }
        }
    }

    func connectionFor(database: String) async throws -> MySQLConnection {
        let existing: MySQLConnection? = lock.withLock {
            let conn = connections[database]
            if let conn, !conn.isClosed { return conn }
            return nil
        }
        if let existing { return existing }

        let conn = try await openConnection(database: database)
        lock.withLock { connections[database] = conn }
        return conn
    }

    func getAnyConnection() throws -> MySQLConnection {
        try lock.withLock {
            connections.values.first { !$0.isClosed }
        }.orThrow(DbError.connection("no connection available"))
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "`", with: "``")
        return "`\(escaped)`"
    }
}
