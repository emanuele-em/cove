import Foundation
import CosmoMSSQL
import CosmoSQLCore

final class SQLServerBackend: DatabaseBackend, @unchecked Sendable {
    let name = "SQL Server"
    private let config: ConnectionConfig
    let initialDatabase: String
    private let lock = NSLock()
    private var pools: [String: MSSQLConnectionPool] = [:]

    let syntaxKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "AS",
        "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS",
        "ORDER", "BY", "GROUP", "HAVING", "DISTINCT",
        "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN",
        "COMMIT", "ROLLBACK", "TRANSACTION", "VALUES", "DEFAULT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT", "CHECK",
        "UNIQUE", "ASC", "DESC", "WITH", "RETURNING", "GRANT",
        "REVOKE", "TRUNCATE", "TRIGGER", "FUNCTION", "PROCEDURE",
        "IF", "WHILE", "DECLARE", "EXEC", "EXECUTE",
        "TOP", "OFFSET", "FETCH", "NEXT", "ROWS", "ONLY",
        "IDENTITY", "NVARCHAR", "VARCHAR", "CHAR", "NCHAR", "TEXT", "NTEXT",
        "INT", "BIGINT", "SMALLINT", "TINYINT", "BIT",
        "DECIMAL", "NUMERIC", "FLOAT", "REAL", "MONEY", "SMALLMONEY",
        "DATETIME", "DATETIME2", "DATE", "TIME", "DATETIMEOFFSET", "SMALLDATETIME",
        "UNIQUEIDENTIFIER", "VARBINARY", "IMAGE", "XML",
        "GETDATE", "GETUTCDATE", "NEWID", "ISNULL", "COALESCE",
        "CONVERT", "CAST", "TRY_CONVERT", "TRY_CAST",
        "COUNT", "SUM", "AVG", "MIN", "MAX",
        "OVER", "PARTITION", "ROW_NUMBER", "RANK", "DENSE_RANK",
        "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        "GO", "USE", "PRINT", "RAISERROR", "THROW",
        "TRUE", "FALSE",
    ]

    private init(config: ConnectionConfig) {
        self.config = config
        self.initialDatabase = config.database
    }

    deinit {
        let allPools = lock.withLock {
            let values = Array(pools.values)
            pools.removeAll()
            return values
        }
        for pool in allPools {
            Task { try? await pool.close() }
        }
    }

    static func connect(config: ConnectionConfig) async throws -> SQLServerBackend {
        let backend = SQLServerBackend(config: config)

        let pool = backend.makePool(database: config.database)
        backend.addPool(pool, key: config.database.isEmpty ? "master" : config.database)

        do {
            _ = try await pool.query("SELECT 1", [])
        } catch {
            try? await pool.close()
            throw DbError.connection(error.localizedDescription)
        }

        return backend
    }

    // MARK: - Pool management

    private func makePool(database: String) -> MSSQLConnectionPool {
        let port = Int(config.port) ?? 1433
        let mssqlConfig = MSSQLConnection.Configuration(
            host: config.host,
            port: port,
            database: database.isEmpty ? "master" : database,
            username: config.user,
            password: config.password,
            trustServerCertificate: true
        )
        return MSSQLConnectionPool(configuration: mssqlConfig, maxConnections: 5)
    }

    private func addPool(_ pool: MSSQLConnectionPool, key: String) {
        lock.withLock { pools[key] = pool }
    }

    func getAnyPool() throws -> MSSQLConnectionPool {
        try lock.withLock {
            pools.values.first
        }.orThrow(DbError.connection("no connection available"))
    }

    func poolFor(database: String) -> MSSQLConnectionPool {
        let existing: MSSQLConnectionPool? = lock.withLock { pools[database] }
        if let existing { return existing }

        let pool = makePool(database: database)
        addPool(pool, key: database)
        return pool
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "]", with: "]]")
        return "[\(escaped)]"
    }
}
