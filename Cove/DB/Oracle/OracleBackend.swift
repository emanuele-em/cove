import Foundation
import OracleNIO
import Logging

final class OracleBackend: DatabaseBackend, @unchecked Sendable {
    let name = "Oracle"
    let client: OracleClient
    private let runningTask: Task<Void, Never>

    let syntaxKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "SCHEMA",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "AS",
        "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS",
        "ORDER", "BY", "GROUP", "HAVING", "DISTINCT",
        "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN",
        "COMMIT", "ROLLBACK", "VALUES", "DEFAULT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT", "CHECK",
        "UNIQUE", "ASC", "DESC", "WITH", "RETURNING", "GRANT",
        "REVOKE", "TRUNCATE", "TRIGGER", "FUNCTION", "PROCEDURE",
        "IF", "LOOP", "WHILE", "FOR", "FETCH", "CURSOR", "DECLARE", "EXECUTE",
        "NUMBER", "VARCHAR2", "NVARCHAR2", "CHAR", "NCHAR", "CLOB", "NCLOB",
        "BLOB", "DATE", "TIMESTAMP", "INTERVAL", "RAW", "BOOLEAN",
        "BINARY_FLOAT", "BINARY_DOUBLE", "INTEGER", "FLOAT",
        "TRUE", "FALSE", "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "CAST", "OVER", "PARTITION", "ROW_NUMBER", "RANK",
        "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        "SYSDATE", "SYSTIMESTAMP", "ROWNUM", "ROWID", "DUAL",
        "NVL", "NVL2", "DECODE", "TO_DATE", "TO_CHAR", "TO_NUMBER", "TRUNC",
        "MINUS", "CONNECT", "START", "LEVEL", "PRIOR",
        "PIVOT", "UNPIVOT", "MERGE", "USING", "MATCHED",
        "PACKAGE", "BODY", "REPLACE", "FORCE", "PURGE",
        "MATERIALIZED", "SEQUENCE", "SYNONYM", "TYPE",
        "OFFSET", "ROWS", "ONLY", "NEXT",
    ]

    private init(client: OracleClient, runningTask: Task<Void, Never>) {
        self.client = client
        self.runningTask = runningTask
    }

    static func connect(config: ConnectionConfig) async throws -> OracleBackend {
        let port = Int(config.port) ?? 1521
        let oraConfig = OracleConnection.Configuration(
            host: config.host,
            port: port,
            service: .serviceName(config.database),
            username: config.user,
            password: config.password
        )

        let client = OracleClient(configuration: oraConfig)
        let task = Task { await client.run() }

        do {
            try await client.withConnection { conn in
                try await conn.execute(OracleStatement(unsafeSQL: "SELECT 1 FROM DUAL"))
            }
        } catch {
            task.cancel()
            throw DbError.connection(error.localizedDescription)
        }

        return OracleBackend(client: client, runningTask: task)
    }

    deinit {
        runningTask.cancel()
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension OracleSQLError {
    var serverMessage: String {
        serverInfo?.message ?? String(describing: self)
    }
}
