import OracleNIO

extension OracleBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        guard path.count == 3 else {
            throw DbError.invalidPath(expected: 3, got: path.count)
        }

        let schema = path[0]
        let table = path[2]
        let fqn = "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"

        return try await client.withConnection { conn in
            let columns = try await self.fetchColumnInfo(conn: &conn, schema: schema, table: table)

            var orderClause = ""
            if let sort {
                let dir = sort.direction == .asc ? "ASC" : "DESC"
                orderClause = " ORDER BY \(self.quoteIdentifier(sort.column)) \(dir)"
            }

            let dataSql = "SELECT * FROM \(fqn)\(orderClause) OFFSET \(offset) ROWS FETCH NEXT \(limit) ROWS ONLY"
            var rows: [[String?]] = []
            do {
                let dataRows = try await conn.execute(OracleStatement(unsafeSQL: dataSql))
                for try await row in dataRows {
                    rows.append(self.decodeRowCells(row))
                }
            } catch let error as OracleSQLError {
                throw DbError.query(error.serverMessage)
            }

            let countSql = "SELECT COUNT(*) FROM \(fqn)"
            var totalCount: Int64 = 0
            do {
                let countRows = try await conn.execute(OracleStatement(unsafeSQL: countSql))
                for try await row in countRows.decode(Int.self) {
                    totalCount = Int64(row)
                }
            } catch let error as OracleSQLError {
                throw DbError.query(error.serverMessage)
            }

            return QueryResult(
                columns: columns,
                rows: rows,
                rowsAffected: nil,
                totalCount: UInt64(totalCount)
            )
        }
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        try await client.withConnection { conn in
            try await self.runQuery(conn: &conn, sql: sql)
        }
    }

    func updateCell(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) async throws {
        guard tablePath.count == 3 else {
            throw DbError.invalidPath(expected: 3, got: tablePath.count)
        }

        let sql = generateUpdateSQL(
            tablePath: tablePath, primaryKey: primaryKey,
            column: column, newValue: newValue
        )
        do {
            try await client.withConnection { conn in
                try await conn.execute(OracleStatement(unsafeSQL: sql))
            }
        } catch let error as OracleSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(error.localizedDescription)
        }
    }

    // MARK: - Shared helpers

    func runQuery(conn: inout OracleClient.PooledConnection, sql: String) async throws -> QueryResult {
        let stream: OracleRowSequence
        do {
            stream = try await conn.execute(OracleStatement(unsafeSQL: sql))
        } catch let error as OracleSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(error.localizedDescription)
        }

        var columnInfos: [ColumnInfo] = []
        var allRows: [[String?]] = []
        var columnsExtracted = false

        do {
            for try await row in stream {
                if !columnsExtracted {
                    for cell in row {
                        columnInfos.append(ColumnInfo(
                            name: cell.columnName,
                            typeName: String(describing: cell.dataType),
                            isPrimaryKey: false
                        ))
                    }
                    columnsExtracted = true
                }
                allRows.append(decodeRowCells(row))
            }
        } catch let error as OracleSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(error.localizedDescription)
        }

        if columnInfos.isEmpty {
            return QueryResult(columns: [], rows: [], rowsAffected: 0, totalCount: nil)
        }

        return QueryResult(columns: columnInfos, rows: allRows, rowsAffected: nil, totalCount: nil)
    }

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema {
        try await client.withConnection { conn in
            let schemaSQL = """
                SELECT username FROM all_users \
                ORDER BY username
                """
            let schemaRows = try await conn.execute(OracleStatement(unsafeSQL: schemaSQL))
            let systemSchemas = OracleBackend.systemSchemas
            var schemas: [String] = []
            for try await row in schemaRows.decode(String.self) {
                if !systemSchemas.contains(row) {
                    schemas.append(row)
                }
            }

            let colSQL = """
                SELECT owner, table_name, column_name, data_type \
                FROM all_tab_columns \
                ORDER BY owner, table_name, column_id
                """
            let colRows = try await conn.execute(OracleStatement(unsafeSQL: colSQL))
            var tableMap: [String: [String: [CompletionColumn]]] = [:]
            for try await (schema, tableName, colName, dataType) in colRows.decode((String, String, String, String).self) {
                guard !systemSchemas.contains(schema) else { continue }
                tableMap[schema, default: [:]][tableName, default: []].append(
                    CompletionColumn(name: colName, typeName: dataType)
                )
            }

            var tables: [String: [CompletionTable]] = [:]
            for (schema, tblMap) in tableMap {
                tables[schema] = tblMap.map { CompletionTable(name: $0.key, columns: $0.value) }
                    .sorted { $0.name < $1.name }
            }

            let funcSQL = """
                SELECT DISTINCT object_name FROM all_procedures \
                WHERE object_type IN ('FUNCTION', 'PROCEDURE') \
                AND procedure_name IS NULL \
                ORDER BY object_name
                """
            let funcRows = try await conn.execute(OracleStatement(unsafeSQL: funcSQL))
            var functions: [String] = []
            for try await row in funcRows.decode(String.self) {
                functions.append(row)
            }

            let typeSQL = """
                SELECT DISTINCT type_name FROM all_types \
                ORDER BY type_name
                """
            let typeRows = try await conn.execute(OracleStatement(unsafeSQL: typeSQL))
            var types: [String] = []
            for try await row in typeRows.decode(String.self) {
                types.append(row)
            }

            return CompletionSchema(schemas: schemas, tables: tables, functions: functions, types: types)
        }
    }

    func fetchColumnInfo(
        conn: inout OracleClient.PooledConnection,
        schema: String,
        table: String
    ) async throws -> [ColumnInfo] {
        let sql = """
            SELECT c.column_name, \
            c.data_type || \
            CASE \
                WHEN c.data_precision IS NOT NULL THEN '(' || c.data_precision || \
                    CASE WHEN c.data_scale > 0 THEN ',' || c.data_scale ELSE '' END || ')' \
                WHEN c.char_length > 0 THEN '(' || c.char_length || ')' \
                ELSE '' \
            END AS full_type, \
            CASE WHEN EXISTS ( \
                SELECT 1 FROM all_cons_columns cc \
                JOIN all_constraints con ON cc.constraint_name = con.constraint_name AND cc.owner = con.owner \
                WHERE con.constraint_type = 'P' AND con.owner = '\(schema)' \
                AND con.table_name = '\(table)' AND cc.column_name = c.column_name \
            ) THEN 1 ELSE 0 END AS is_pk \
            FROM all_tab_columns c \
            WHERE c.owner = '\(schema)' AND c.table_name = '\(table)' \
            ORDER BY c.column_id
            """
        let rows = try await conn.execute(OracleStatement(unsafeSQL: sql))
        var columns: [ColumnInfo] = []
        for try await (name, typeName, isPK) in rows.decode((String, String, Int).self) {
            columns.append(ColumnInfo(name: name, typeName: typeName, isPrimaryKey: isPK != 0))
        }
        return columns
    }
}
