import Foundation
import Darwin

final class DuckDBBackend: DatabaseBackend, @unchecked Sendable {
    let name = "DuckDB"

    let syntaxKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "SCHEMA",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "AS",
        "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS",
        "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "DISTINCT",
        "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN",
        "COMMIT", "ROLLBACK", "TRANSACTION", "VALUES", "DEFAULT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT", "CHECK",
        "UNIQUE", "ASC", "DESC", "WITH", "RECURSIVE", "RETURNING",
        "TRIGGER", "FUNCTION", "MACRO", "SEQUENCE", "TYPE",
        "BOOLEAN", "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "HUGEINT",
        "FLOAT", "DOUBLE", "REAL", "DECIMAL", "NUMERIC",
        "VARCHAR", "TEXT", "CHAR", "BLOB", "DATE", "TIME", "TIMESTAMP",
        "INTERVAL", "UUID", "JSON", "LIST", "MAP", "STRUCT",
        "TRUE", "FALSE", "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "CAST", "OVER", "PARTITION", "ROW_NUMBER", "RANK",
        "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        "COPY", "EXPORT", "IMPORT", "PIVOT", "UNPIVOT", "QUALIFY",
        "SAMPLE", "USING", "REPLACE", "EXCLUDE", "ATTACH", "DETACH",
    ]

    private let execution: any FileBackendExecution

    private init(execution: any FileBackendExecution) {
        self.execution = execution
    }

    static func connect(config: ConnectionConfig) async throws -> DuckDBBackend {
        let execution: any FileBackendExecution
        if let sshConfig = config.sshTunnel {
            execution = try await RemoteCLIExecution.connect(binaryName: "duckdb", path: config.database, sshConfig: sshConfig)
        } else {
            let libPaths = ["/opt/homebrew/lib/libduckdb.dylib", "/usr/local/lib/libduckdb.dylib"]
            guard libPaths.contains(where: { dlopen($0, RTLD_LAZY | RTLD_GLOBAL) != nil }) else {
                throw DbError.connection("libduckdb not found — run: brew install duckdb")
            }
            execution = try DuckDBLocalExecution.connect(path: config.database)
        }
        return DuckDBBackend(execution: execution)
    }

    var isReadOnly: Bool {
        execution.isReadOnly
    }

    func runQuery(_ sql: String) async throws -> QueryResult {
        try await execution.query(sql)
    }

    func runExec(_ sql: String) async throws -> UInt64? {
        try await execution.execute(sql)
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
