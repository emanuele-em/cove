import Foundation
import CDuckDB
import Synchronization

final class DuckDBBackend: DatabaseBackend, @unchecked Sendable {
    let name = "DuckDB"
    private let db: Mutex<duckdb_database?>
    private let conn: Mutex<duckdb_connection?>

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

    private init(db: consuming Mutex<duckdb_database?>, conn: consuming Mutex<duckdb_connection?>) {
        self.db = db
        self.conn = conn
    }

    deinit {
        conn.withLock { c in
            if c != nil { duckdb_disconnect(&c) }
        }
        db.withLock { d in
            if d != nil { duckdb_close(&d) }
        }
    }

    static func connect(config: ConnectionConfig) async throws -> DuckDBBackend {
        let path = config.database

        var database: duckdb_database?
        let openResult = path.withCString { pathPtr in
            duckdb_open(pathPtr, &database)
        }
        guard openResult == DuckDBSuccess, database != nil else {
            throw DbError.connection("failed to open DuckDB database: \(path)")
        }

        var connection: duckdb_connection?
        let connResult = duckdb_connect(database, &connection)
        guard connResult == DuckDBSuccess, connection != nil else {
            duckdb_close(&database)
            throw DbError.connection("failed to connect to DuckDB database")
        }

        nonisolated(unsafe) let dbVal = database
        nonisolated(unsafe) let connVal = connection
        let backend = DuckDBBackend(db: Mutex(dbVal), conn: Mutex(connVal))

        do {
            _ = try backend.runSQL("SELECT 1")
        } catch {
            throw DbError.connection("DuckDB connection test failed: \(error.localizedDescription)")
        }

        return backend
    }

    // MARK: - SQL execution

    func runSQL(_ sql: String) throws -> QueryResult {
        try conn.withLock { connection in
            guard let connection else { throw DbError.connection("database closed") }

            var result = duckdb_result()
            let status = sql.withCString { sqlPtr in
                duckdb_query(connection, sqlPtr, &result)
            }
            defer { duckdb_destroy_result(&result) }

            guard status == DuckDBSuccess else {
                let errMsg = duckdb_result_error(&result)
                let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
                throw DbError.query(msg)
            }

            let colCount = duckdb_column_count(&result)

            guard colCount > 0 else {
                let affected = UInt64(duckdb_rows_changed(&result))
                return QueryResult(columns: [], rows: [], rowsAffected: affected, totalCount: nil)
            }

            var columns: [ColumnInfo] = []
            for i in 0..<colCount {
                let namePtr = duckdb_column_name(&result, i)
                let name = namePtr.map { String(cString: $0) } ?? "?"
                let colType = duckdb_column_type(&result, i)
                let typeName = duckdbTypeName(colType)
                columns.append(ColumnInfo(name: name, typeName: typeName, isPrimaryKey: false))
            }

            let rowCount = duckdb_row_count(&result)
            var rows: [[String?]] = []
            for row in 0..<rowCount {
                var rowData: [String?] = []
                for col in 0..<colCount {
                    if duckdb_value_is_null(&result, col, row) {
                        rowData.append(nil)
                    } else {
                        let valPtr = duckdb_value_varchar(&result, col, row)
                        if let valPtr {
                            rowData.append(String(cString: valPtr))
                            duckdb_free(valPtr)
                        } else {
                            rowData.append(nil)
                        }
                    }
                }
                rows.append(rowData)
            }

            return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: nil)
        }
    }

    func execSQL(_ sql: String) throws {
        try conn.withLock { connection in
            guard let connection else { throw DbError.connection("database closed") }

            var result = duckdb_result()
            let status = sql.withCString { sqlPtr in
                duckdb_query(connection, sqlPtr, &result)
            }
            defer { duckdb_destroy_result(&result) }

            guard status == DuckDBSuccess else {
                let errMsg = duckdb_result_error(&result)
                let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
                throw DbError.query(msg)
            }
        }
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - Private helpers

    private func duckdbTypeName(_ type: duckdb_type) -> String {
        switch type {
        case DUCKDB_TYPE_BOOLEAN: "BOOLEAN"
        case DUCKDB_TYPE_TINYINT: "TINYINT"
        case DUCKDB_TYPE_SMALLINT: "SMALLINT"
        case DUCKDB_TYPE_INTEGER: "INTEGER"
        case DUCKDB_TYPE_BIGINT: "BIGINT"
        case DUCKDB_TYPE_UTINYINT: "UTINYINT"
        case DUCKDB_TYPE_USMALLINT: "USMALLINT"
        case DUCKDB_TYPE_UINTEGER: "UINTEGER"
        case DUCKDB_TYPE_UBIGINT: "UBIGINT"
        case DUCKDB_TYPE_FLOAT: "FLOAT"
        case DUCKDB_TYPE_DOUBLE: "DOUBLE"
        case DUCKDB_TYPE_TIMESTAMP: "TIMESTAMP"
        case DUCKDB_TYPE_DATE: "DATE"
        case DUCKDB_TYPE_TIME: "TIME"
        case DUCKDB_TYPE_INTERVAL: "INTERVAL"
        case DUCKDB_TYPE_HUGEINT: "HUGEINT"
        case DUCKDB_TYPE_UHUGEINT: "UHUGEINT"
        case DUCKDB_TYPE_VARCHAR: "VARCHAR"
        case DUCKDB_TYPE_BLOB: "BLOB"
        case DUCKDB_TYPE_DECIMAL: "DECIMAL"
        case DUCKDB_TYPE_TIMESTAMP_S: "TIMESTAMP_S"
        case DUCKDB_TYPE_TIMESTAMP_MS: "TIMESTAMP_MS"
        case DUCKDB_TYPE_TIMESTAMP_NS: "TIMESTAMP_NS"
        case DUCKDB_TYPE_UUID: "UUID"
        case DUCKDB_TYPE_LIST: "LIST"
        case DUCKDB_TYPE_STRUCT: "STRUCT"
        case DUCKDB_TYPE_MAP: "MAP"
        default: "UNKNOWN"
        }
    }
}
