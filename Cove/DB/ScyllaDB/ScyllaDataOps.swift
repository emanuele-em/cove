import CassandraClient

extension ScyllaBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        guard path.count == 3 else {
            throw DbError.invalidPath(expected: 3, got: path.count)
        }

        let ks = path[0]
        let table = path[2]
        let fqn = "\"\(ks)\".\"\(table)\""

        let columnMeta = try await fetchColumnInfo(keyspace: ks, table: table)
        let typeMap = Dictionary(uniqueKeysWithValues: columnMeta.map { ($0.name, $0) })

        // CQL has no OFFSET — fetch offset+limit rows and skip in memory
        let fetchCount = Int(offset) + Int(limit)
        let cql = "SELECT * FROM \(fqn) LIMIT \(fetchCount)"

        var allRows: [[String?]] = []
        var orderedColumns: [ColumnInfo] = []
        do {
            let rows = try await client.query(cql)
            let colCount = rows.columnsCount
            let colNames = try rows.columnNames()

            // Align column info to result order and build type list
            orderedColumns = colNames.map {
                typeMap[$0] ?? ColumnInfo(name: $0, typeName: "", isPrimaryKey: false)
            }
            let types = orderedColumns.map(\.typeName)

            for row in rows {
                var vals: [String?] = []
                for i in 0..<colCount {
                    vals.append(decodeColumn(row.column(i), cqlType: types[i]))
                }
                allRows.append(vals)
            }
        } catch {
            throw DbError.query(error.localizedDescription)
        }

        let pageRows = Array(allRows.dropFirst(Int(offset)).prefix(Int(limit)))

        var totalCount: Int64 = 0
        do {
            let countRows = try await client.query("SELECT COUNT(*) FROM \(fqn)")
            for row in countRows {
                totalCount = row.column(0)?.int64 ?? 0
            }
        } catch {
            // COUNT(*) can be slow on large tables; leave as 0
        }

        return QueryResult(
            columns: orderedColumns,
            rows: pageRows,
            rowsAffected: nil,
            totalCount: UInt64(totalCount)
        )
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        do {
            let ks: String? = database.isEmpty ? nil : database
            return try await client.withSession(keyspace: ks) { session in
                let rows = try await session.query(sql)
                return try self.buildQueryResult(rows: rows)
            }
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.query(error.localizedDescription)
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

        let cql = generateUpdateSQL(
            tablePath: tablePath, primaryKey: primaryKey,
            column: column, newValue: newValue
        )
        do {
            try await client.run(cql)
        } catch {
            throw DbError.query(error.localizedDescription)
        }
    }

    // MARK: - Shared helpers

    func buildQueryResult(rows: CassandraClient.Rows) throws -> QueryResult {
        let colCount = rows.columnsCount
        if colCount == 0 {
            return QueryResult(columns: [], rows: [], rowsAffected: 0, totalCount: nil)
        }

        let columnNames = try rows.columnNames()
        let columnInfos = columnNames.map {
            ColumnInfo(name: $0, typeName: "", isPrimaryKey: false)
        }

        var allRows: [[String?]] = []
        for row in rows {
            var vals: [String?] = []
            for i in 0..<colCount {
                vals.append(decodeColumnUntyped(row.column(i)))
            }
            allRows.append(vals)
        }

        return QueryResult(columns: columnInfos, rows: allRows, rowsAffected: nil, totalCount: nil)
    }

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema {
        let ksRows = try await client.query("SELECT keyspace_name FROM system_schema.keyspaces")
        var schemas: [String] = []
        let systemKS = Self.systemKeyspaces
        for row in ksRows {
            guard let name = row.column("keyspace_name")?.string,
                  !systemKS.contains(name) else { continue }
            schemas.append(name)
        }
        schemas.sort()
        let schemaSet = Set(schemas)

        let colRows = try await client.query(
            "SELECT keyspace_name, table_name, column_name, type FROM system_schema.columns"
        )
        var tableMap: [String: [String: [CompletionColumn]]] = [:]
        for row in colRows {
            guard let ks = row.column("keyspace_name")?.string,
                  schemaSet.contains(ks),
                  let tableName = row.column("table_name")?.string,
                  let colName = row.column("column_name")?.string,
                  let colType = row.column("type")?.string else { continue }
            tableMap[ks, default: [:]][tableName, default: []].append(
                CompletionColumn(name: colName, typeName: colType)
            )
        }

        var tables: [String: [CompletionTable]] = [:]
        for (ks, tblMap) in tableMap {
            tables[ks] = tblMap.map { CompletionTable(name: $0.key, columns: $0.value.sorted { $0.name < $1.name }) }
                .sorted { $0.name < $1.name }
        }

        let funcRows = try await client.query("SELECT function_name FROM system_schema.functions")
        var functions = Set<String>()
        for row in funcRows {
            if let name = row.column("function_name")?.string { functions.insert(name) }
        }

        return CompletionSchema(
            schemas: schemas, tables: tables,
            functions: functions.sorted(), types: []
        )
    }

    func fetchColumnInfo(keyspace: String, table: String) async throws -> [ColumnInfo] {
        let rows = try await client.query(
            "SELECT column_name, type, kind, position FROM system_schema.columns WHERE keyspace_name = '\(keyspace)' AND table_name = '\(table)'"
        )

        struct ColMeta {
            let name: String
            let type: String
            let kind: String
            let position: Int32
        }

        var cols: [ColMeta] = []
        for row in rows {
            guard let name = row.column("column_name")?.string,
                  let type = row.column("type")?.string,
                  let kind = row.column("kind")?.string,
                  let position = row.column("position")?.int32 else { continue }
            cols.append(ColMeta(name: name, type: type, kind: kind, position: position))
        }

        cols.sort { a, b in
            let order = ["partition_key": 0, "clustering": 1, "static": 2, "regular": 3]
            let ao = order[a.kind] ?? 4
            let bo = order[b.kind] ?? 4
            if ao != bo { return ao < bo }
            if ao <= 1 { return a.position < b.position }
            return a.name < b.name
        }

        return cols.map { col in
            ColumnInfo(
                name: col.name,
                typeName: col.type,
                isPrimaryKey: col.kind == "partition_key" || col.kind == "clustering"
            )
        }
    }

}
