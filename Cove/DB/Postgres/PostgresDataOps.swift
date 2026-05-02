import PostgresNIO

private struct PostgresSourceColumn {
    let schema: String
    let table: String
    let name: String
    let typeName: String
    let isPrimaryKey: Bool
}

extension PostgresBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        guard path.count == 4 else {
            throw DbError.invalidPath(expected: 4, got: path.count)
        }

        let client = try await clientFor(database: path[0])
        let schema = path[1]
        let table = path[3]
        let fqn = "\"\(schema)\".\"\(table)\""

        let columns = try await fetchColumnInfo(client: client, schema: schema, table: table)

        var orderClause = ""
        if let sort {
            let dir = sort.direction == .asc ? "ASC" : "DESC"
            orderClause = " ORDER BY \"\(sort.column)\" \(dir)"
        }

        let dataSql = "SELECT * FROM \(fqn)\(orderClause) LIMIT \(limit) OFFSET \(offset)"
        var rows: [[String?]] = []
        do {
            let dataRows = try await client.query(PostgresQuery(stringLiteral: dataSql))
            for try await row in dataRows {
                rows.append(decodeRowCells(row))
            }
        } catch let error as PSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(String(describing: error))
        }

        let countSql = "SELECT COUNT(*) FROM \(fqn)"
        var totalCount: Int64 = 0
        do {
            let countRows = try await client.query(PostgresQuery(stringLiteral: countSql))
            for try await row in countRows {
                totalCount = try row.decode(Int64.self, context: .default)
            }
        } catch let error as PSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(String(describing: error))
        }

        return QueryResult(
            columns: columns,
            rows: rows,
            rowsAffected: nil,
            totalCount: UInt64(totalCount)
        )
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        let client = try await clientFor(database: database)
        return try await runQuery(client: client, sql: sql, database: database)
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

        let client = try await clientFor(database: tablePath[0])
        let sql = generateUpdateSQL(tablePath: tablePath, primaryKey: primaryKey, column: column, newValue: newValue)
        do {
            _ = try await client.query(PostgresQuery(stringLiteral: sql))
        } catch let error as PSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(String(describing: error))
        }
    }

    // MARK: - Shared helpers

    func runQuery(client: PostgresClient, sql: String, database: String? = nil) async throws -> QueryResult {
        let stream: PostgresRowSequence
        do {
            stream = try await client.query(PostgresQuery(stringLiteral: sql))
        } catch let error as PSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(String(describing: error))
        }

        let resultColumns = Array(stream.columns)
        var allRows: [[String?]] = []

        do {
            for try await row in stream {
                allRows.append(decodeRowCells(row))
            }
        } catch let error as PSQLError {
            throw DbError.query(error.serverMessage)
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(String(describing: error))
        }

        if resultColumns.isEmpty {
            return QueryResult(columns: [], rows: [], rowsAffected: 0, totalCount: nil)
        }

        var columnInfos = resultColumns.map {
            ColumnInfo(name: $0.name, typeName: String(describing: $0.dataType), isPrimaryKey: false)
        }
        var editableTablePath: [String]?
        if let database,
           let editableResult = try await inferEditableResult(
               client: client,
               database: database,
               resultColumns: resultColumns
           ) {
            columnInfos = editableResult.columns
            editableTablePath = editableResult.tablePath
        }

        return QueryResult(
            columns: columnInfos,
            rows: allRows,
            rowsAffected: nil,
            totalCount: nil,
            editableTablePath: editableTablePath
        )
    }

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema {
        let client = try await clientFor(database: database)

        let schemaSQL = """
            SELECT schema_name FROM information_schema.schemata \
            WHERE schema_name NOT IN ('pg_toast', 'pg_catalog', 'information_schema') \
            ORDER BY schema_name
            """
        let schemaRows = try await client.query(PostgresQuery(stringLiteral: schemaSQL))
        var schemas: [String] = []
        for try await row in schemaRows {
            schemas.append(try row.decode(String.self, context: .default))
        }

        let colSQL = """
            SELECT table_schema, table_name, column_name, data_type \
            FROM information_schema.columns \
            WHERE table_schema NOT IN ('pg_toast', 'pg_catalog', 'information_schema') \
            ORDER BY table_schema, table_name, ordinal_position
            """
        let colRows = try await client.query(PostgresQuery(stringLiteral: colSQL))
        var tableMap: [String: [String: [CompletionColumn]]] = [:]
        for try await row in colRows {
            let (schema, tableName, colName, dataType) = try row.decode(
                (String, String, String, String).self, context: .default
            )
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
            SELECT DISTINCT p.proname FROM pg_proc p \
            JOIN pg_namespace n ON p.pronamespace = n.oid \
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') \
            AND p.prokind IN ('f', 'p') \
            ORDER BY p.proname
            """
        let funcRows = try await client.query(PostgresQuery(stringLiteral: funcSQL))
        var functions: [String] = []
        for try await row in funcRows {
            functions.append(try row.decode(String.self, context: .default))
        }

        let typeSQL = """
            SELECT DISTINCT t.typname FROM pg_type t \
            JOIN pg_namespace n ON t.typnamespace = n.oid \
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') \
            AND t.typtype IN ('e', 'c', 'd') \
            ORDER BY t.typname
            """
        let typeRows = try await client.query(PostgresQuery(stringLiteral: typeSQL))
        var types: [String] = []
        for try await row in typeRows {
            types.append(try row.decode(String.self, context: .default))
        }

        return CompletionSchema(schemas: schemas, tables: tables, functions: functions, types: types)
    }

    func fetchColumnInfo(
        client: PostgresClient,
        schema: String,
        table: String
    ) async throws -> [ColumnInfo] {
        let sql = """
            SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod), \
            COALESCE(( \
                SELECT true FROM pg_constraint pc \
                WHERE pc.conrelid = c.oid \
                AND pc.contype = 'p' \
                AND a.attnum = ANY(pc.conkey) \
            ), false) as is_pk \
            FROM pg_attribute a \
            JOIN pg_class c ON a.attrelid = c.oid \
            JOIN pg_namespace n ON c.relnamespace = n.oid \
            WHERE n.nspname = '\(schema)' AND c.relname = '\(table)' \
            AND a.attnum > 0 AND NOT a.attisdropped \
            ORDER BY a.attnum
            """
        let rows = try await client.query(PostgresQuery(stringLiteral: sql))
        var columns: [ColumnInfo] = []
        for try await row in rows {
            let (name, typeName, isPK) = try row.decode((String, String, Bool).self, context: .default)
            columns.append(ColumnInfo(name: name, typeName: typeName, isPrimaryKey: isPK))
        }
        return columns
    }

    private func inferEditableResult(
        client: PostgresClient,
        database: String,
        resultColumns: [PostgresColumn]
    ) async throws -> (tablePath: [String], columns: [ColumnInfo])? {
        guard let tableOID = resultColumns.first?.tableOID, tableOID > 0 else { return nil }
        guard resultColumns.allSatisfy({
            $0.tableOID == tableOID && $0.columnAttributeNumber > 0
        }) else { return nil }

        let sourceColumns = try await fetchSourceColumns(client: client, tableOID: tableOID)
        guard let first = sourceColumns[resultColumns[0].columnAttributeNumber] else { return nil }
        let resultAttnums = Set(resultColumns.map(\.columnAttributeNumber))
        let primaryKeyAttnums = Set(sourceColumns.compactMap { entry in
            entry.value.isPrimaryKey ? entry.key : nil
        })
        guard !primaryKeyAttnums.isEmpty,
              primaryKeyAttnums.isSubset(of: resultAttnums) else {
            return nil
        }

        var columns: [ColumnInfo] = []
        columns.reserveCapacity(resultColumns.count)
        for resultColumn in resultColumns {
            guard let source = sourceColumns[resultColumn.columnAttributeNumber] else { return nil }
            columns.append(ColumnInfo(
                name: resultColumn.name,
                typeName: source.typeName,
                isPrimaryKey: source.isPrimaryKey,
                sourceColumnName: source.name
            ))
        }

        return (tablePath: [database, first.schema, "Tables", first.table], columns: columns)
    }

    private func fetchSourceColumns(
        client: PostgresClient,
        tableOID: Int32
    ) async throws -> [Int16: PostgresSourceColumn] {
        let sql = """
            SELECT n.nspname, c.relname, a.attnum, a.attname, \
            pg_catalog.format_type(a.atttypid, a.atttypmod), \
            COALESCE(( \
                SELECT true FROM pg_constraint pc \
                WHERE pc.conrelid = c.oid \
                AND pc.contype = 'p' \
                AND a.attnum = ANY(pc.conkey) \
            ), false) as is_pk \
            FROM pg_class c \
            JOIN pg_namespace n ON c.relnamespace = n.oid \
            JOIN pg_attribute a ON a.attrelid = c.oid \
            WHERE c.oid = \(tableOID) \
            AND a.attnum > 0 AND NOT a.attisdropped \
            ORDER BY a.attnum
            """

        let rows = try await client.query(PostgresQuery(stringLiteral: sql))
        var columns: [Int16: PostgresSourceColumn] = [:]
        for try await row in rows {
            let (schema, table, attnum, name, typeName, isPK) = try row.decode(
                (String, String, Int16, String, String, Bool).self,
                context: .default
            )
            columns[attnum] = PostgresSourceColumn(
                schema: schema,
                table: table,
                name: name,
                typeName: typeName,
                isPrimaryKey: isPK
            )
        }
        return columns
    }
}
