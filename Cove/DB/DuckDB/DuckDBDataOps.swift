import Foundation

extension DuckDBBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        guard path.count == 4 else {
            throw DbError.invalidPath(expected: 4, got: path.count)
        }

        let catalog = path[0]
        let schema = path[1]
        let table = path[3]
        let fqn = "\(quoteIdentifier(catalog)).\(quoteIdentifier(schema)).\(quoteIdentifier(table))"

        let columns = try await fetchColumnInfo(catalog: catalog, schema: schema, table: table)

        var orderClause = ""
        if let sort {
            let dir = sort.direction == .asc ? "ASC" : "DESC"
            orderClause = " ORDER BY \(quoteIdentifier(sort.column)) \(dir)"
        }

        let dataSql = "SELECT * FROM \(fqn)\(orderClause) LIMIT \(limit) OFFSET \(offset)"
        let dataResult = try await runQuery(dataSql)

        let countSql = "SELECT COUNT(*) FROM \(fqn)"
        let countResult = try await runQuery(countSql)
        let totalCount = countResult.rows.first?.first.flatMap { $0.flatMap { UInt64($0) } } ?? 0

        return QueryResult(
            columns: columns,
            rows: dataResult.rows,
            rowsAffected: nil,
            totalCount: totalCount
        )
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        try await runQuery(sql)
    }

    func updateCell(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) async throws {
        guard tablePath.count == 4 else {
            throw DbError.invalidPath(expected: 4, got: tablePath.count)
        }
        guard !isReadOnly else {
            throw DbError.other("DuckDB over SSH is read-only for now")
        }

        let sql = generateUpdateSQL(tablePath: tablePath, primaryKey: primaryKey, column: column, newValue: newValue)
        _ = try await runExec(sql)
    }

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema {
        let schemaResult = try await runQuery(
            "SELECT schema_name FROM duckdb_schemas() WHERE schema_name NOT IN ('information_schema', 'pg_catalog') ORDER BY schema_name"
        )
        let schemas = schemaResult.rows.compactMap { $0.first ?? nil }

        let colResult = try await runQuery(
            "SELECT schema_name, table_name, column_name, data_type FROM duckdb_columns() WHERE schema_name NOT IN ('information_schema', 'pg_catalog') ORDER BY schema_name, table_name, column_index"
        )
        var tableMap: [String: [String: [CompletionColumn]]] = [:]
        for row in colResult.rows {
            guard row.count >= 4,
                  let schema = row[0],
                  let tableName = row[1],
                  let colName = row[2],
                  let dataType = row[3] else { continue }
            tableMap[schema, default: [:]][tableName, default: []].append(
                CompletionColumn(name: colName, typeName: dataType)
            )
        }

        var tables: [String: [CompletionTable]] = [:]
        for (schema, tblMap) in tableMap {
            tables[schema] = tblMap.map { CompletionTable(name: $0.key, columns: $0.value) }
                .sorted { $0.name < $1.name }
        }

        let funcResult = try await runQuery(
            "SELECT DISTINCT function_name FROM duckdb_functions() WHERE schema_name NOT IN ('information_schema', 'pg_catalog') AND function_type = 'scalar' AND NOT internal ORDER BY function_name"
        )
        let functions = funcResult.rows.compactMap { $0.first ?? nil }

        return CompletionSchema(schemas: schemas, tables: tables, functions: functions, types: [])
    }

    func fetchColumnInfo(catalog: String, schema: String, table: String) async throws -> [ColumnInfo] {
        let catQ = quoteIdentifier(catalog)
        let sql = """
            SELECT c.column_name, c.data_type, \
            CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN 1 ELSE 0 END AS is_pk \
            FROM \(catQ).information_schema.columns c \
            LEFT JOIN \(catQ).information_schema.key_column_usage kcu \
            ON c.table_schema = kcu.table_schema AND c.table_name = kcu.table_name AND c.column_name = kcu.column_name \
            LEFT JOIN \(catQ).information_schema.table_constraints tc \
            ON kcu.constraint_name = tc.constraint_name AND kcu.table_schema = tc.table_schema \
            AND tc.constraint_type = 'PRIMARY KEY' \
            WHERE c.table_schema = '\(schema)' AND c.table_name = '\(table)' \
            ORDER BY c.ordinal_position
            """
        let result = try await runQuery(sql)
        return result.rows.compactMap { row in
            guard row.count >= 3,
                  let name = row[0],
                  let typeName = row[1] else { return nil }
            let isPK = row[2] == "1"
            return ColumnInfo(name: name, typeName: typeName, isPrimaryKey: isPK)
        }
    }
}
