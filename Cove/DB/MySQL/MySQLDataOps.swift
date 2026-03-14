import Foundation
import MySQLNIO

extension MySQLBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        guard path.count == 3 else {
            throw DbError.invalidPath(expected: 3, got: path.count)
        }

        let conn = try await connectionFor(database: path[0])
        let table = path[2]
        let fqn = fqnFrom(path)

        let columns = try await fetchColumnInfo(conn: conn, database: path[0], table: table)

        var orderClause = ""
        if let sort {
            let dir = sort.direction == .asc ? "ASC" : "DESC"
            orderClause = " ORDER BY \(quoteIdentifier(sort.column)) \(dir)"
        }

        let dataSql = "SELECT * FROM \(fqn)\(orderClause) LIMIT \(limit) OFFSET \(offset)"
        let dataRows: [MySQLRow]
        do {
            dataRows = try await conn.simpleQuery(dataSql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        let rows = dataRows.map { decodeRow($0) }

        let countSql = "SELECT COUNT(*) AS cnt FROM \(fqn)"
        let countRows: [MySQLRow]
        do {
            countRows = try await conn.simpleQuery(countSql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        let totalCount = countRows.first?.column("cnt")?.int.map(UInt64.init) ?? 0

        return QueryResult(
            columns: columns,
            rows: rows,
            rowsAffected: nil,
            totalCount: totalCount
        )
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        let conn = try await connectionFor(database: database)
        return try await runQuery(conn: conn, sql: sql)
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

        let conn = try await connectionFor(database: tablePath[0])
        let sql = generateUpdateSQL(tablePath: tablePath, primaryKey: primaryKey, column: column, newValue: newValue)
        do {
            _ = try await conn.simpleQuery(sql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
    }

    // MARK: - Shared helpers

    func runQuery(conn: MySQLConnection, sql: String) async throws -> QueryResult {
        let rows: [MySQLRow]
        do {
            rows = try await conn.simpleQuery(sql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }

        guard let first = rows.first else {
            return QueryResult(columns: [], rows: [], rowsAffected: 0, totalCount: nil)
        }

        let columnInfos = columnInfoFromRow(first)
        let allRows = rows.map { decodeRow($0) }

        return QueryResult(columns: columnInfos, rows: allRows, rowsAffected: nil, totalCount: nil)
    }

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema {
        let conn = try await connectionFor(database: database)

        let schemaSQL = """
            SELECT SCHEMA_NAME FROM information_schema.SCHEMATA \
            WHERE SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema','sys') \
            ORDER BY SCHEMA_NAME
            """
        let schemaRows: [MySQLRow]
        do {
            schemaRows = try await conn.simpleQuery(schemaSQL).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        let schemas = schemaRows.compactMap { $0.column("SCHEMA_NAME")?.string }

        let colSQL = """
            SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE \
            FROM information_schema.COLUMNS \
            WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys') \
            ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION
            """
        let colRows: [MySQLRow]
        do {
            colRows = try await conn.simpleQuery(colSQL).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }

        var tableMap: [String: [String: [CompletionColumn]]] = [:]
        for row in colRows {
            guard let schema = row.column("TABLE_SCHEMA")?.string,
                  let tableName = row.column("TABLE_NAME")?.string,
                  let colName = row.column("COLUMN_NAME")?.string,
                  let dataType = row.column("DATA_TYPE")?.string else { continue }
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
            SELECT DISTINCT ROUTINE_NAME \
            FROM information_schema.ROUTINES \
            WHERE ROUTINE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys') \
            AND ROUTINE_TYPE='FUNCTION' \
            ORDER BY ROUTINE_NAME
            """
        let funcRows: [MySQLRow]
        do {
            funcRows = try await conn.simpleQuery(funcSQL).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        let functions = funcRows.compactMap { $0.column("ROUTINE_NAME")?.string }

        return CompletionSchema(schemas: schemas, tables: tables, functions: functions, types: [])
    }

    func fetchColumnInfo(
        conn: MySQLConnection,
        database: String,
        table: String
    ) async throws -> [ColumnInfo] {
        let db = database.replacingOccurrences(of: "'", with: "''")
        let tbl = table.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_KEY \
            FROM information_schema.COLUMNS \
            WHERE TABLE_SCHEMA = '\(db)' AND TABLE_NAME = '\(tbl)' \
            ORDER BY ORDINAL_POSITION
            """
        let rows: [MySQLRow]
        do {
            rows = try await conn.simpleQuery(sql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        return rows.compactMap { row in
            guard let name = row.column("COLUMN_NAME")?.string,
                  let typeName = row.column("COLUMN_TYPE")?.string else { return nil }
            let isPK = row.column("COLUMN_KEY")?.string == "PRI"
            return ColumnInfo(name: name, typeName: typeName, isPrimaryKey: isPK)
        }
    }
}
