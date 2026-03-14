import Foundation
import MySQLNIO

extension MySQLBackend {
    private static let tintDatabase  = NodeTint(r: 0.00, g: 0.45, b: 0.68)
    private static let tintTable     = NodeTint(r: 0.90, g: 0.58, b: 0.15)
    private static let tintView      = NodeTint(r: 0.85, g: 0.75, b: 0.45)
    private static let tintGroup     = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintIndex     = NodeTint(r: 0.40, g: 0.69, b: 0.66)
    private static let tintFunction  = NodeTint(r: 0.69, g: 0.51, b: 0.80)
    private static let tintProcedure = NodeTint(r: 0.60, g: 0.40, b: 0.70)
    private static let tintEvent     = NodeTint(r: 0.55, g: 0.75, b: 0.52)
    private static let tintColumn    = NodeTint(r: 0.55, g: 0.66, b: 0.78)
    private static let tintKey       = NodeTint(r: 0.84, g: 0.72, b: 0.39)
    private static let tintTrigger   = NodeTint(r: 0.84, g: 0.49, b: 0.39)

    private static let systemDatabases = Set([
        "information_schema", "mysql", "performance_schema", "sys",
    ])

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 3 && ["Tables", "Views"].contains(path[1])
    }

    func isEditable(path: [String]) -> Bool {
        path.count == 3 && path[1] == "Tables"
    }

    func isStructureEditable(path: [String]) -> Bool {
        path.count >= 4 && path[1] == "Tables"
            && ["Indexes", "Constraints", "Triggers"].contains(path[3])
    }

    func structurePath(for tablePath: [String]) -> [String]? {
        guard tablePath.count == 3 else { return nil }
        return tablePath + ["Columns"]
    }

    // MARK: - Creation

    func creatableChildLabel(path: [String]) -> String? {
        switch path.count {
        case 0: "Database"
        case 2:
            switch path[1] {
            case "Tables": "Table"
            case "Views": "View"
            default: nil
            }
        default: nil
        }
    }

    private static let mysqlCharSets = [
        "utf8mb4", "utf8", "latin1", "ascii", "binary",
    ]

    private static let mysqlColumnTypes = [
        "BIGINT AUTO_INCREMENT", "INT", "BIGINT", "SMALLINT", "TINYINT",
        "VARCHAR(255)", "TEXT", "MEDIUMTEXT", "LONGTEXT",
        "BOOLEAN", "DATE", "DATETIME", "TIMESTAMP",
        "DECIMAL(10,2)", "FLOAT", "DOUBLE",
        "JSON", "BLOB",
    ]

    private static let mysqlEngines = ["InnoDB", "MyISAM"]

    func createFormFields(path: [String]) -> [CreateField] {
        switch path.count {
        case 0:
            return [
                CreateField(id: "name", label: "Name", defaultValue: "", placeholder: "my_database"),
                CreateField(id: "charset", label: "Character Set", defaultValue: "utf8mb4",
                            placeholder: "utf8mb4", options: Self.mysqlCharSets),
            ]
        case 2:
            switch path[1] {
            case "Tables":
                return [
                    CreateField(id: "name", label: "Table Name", defaultValue: "", placeholder: "my_table"),
                    CreateField(id: "column", label: "Column Name", defaultValue: "id", placeholder: "id"),
                    CreateField(id: "type", label: "Column Type", defaultValue: "BIGINT AUTO_INCREMENT",
                                placeholder: "BIGINT AUTO_INCREMENT", options: Self.mysqlColumnTypes),
                    CreateField(id: "engine", label: "Engine", defaultValue: "InnoDB",
                                placeholder: "InnoDB", options: Self.mysqlEngines),
                ]
            case "Views":
                return [
                    CreateField(id: "name", label: "View Name", defaultValue: "", placeholder: "my_view"),
                    CreateField(id: "query", label: "AS Query", defaultValue: "SELECT 1", placeholder: "SELECT ..."),
                ]
            default:
                return []
            }
        default:
            return []
        }
    }

    func generateCreateChildSQL(path: [String], values: [String: String]) -> String? {
        let name = values["name", default: ""].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let q = quoteIdentifier(name)

        switch path.count {
        case 0:
            var sql = "CREATE DATABASE \(q)"
            let charset = values["charset", default: ""].trimmingCharacters(in: .whitespaces)
            if !charset.isEmpty {
                sql += " CHARACTER SET \(charset) COLLATE \(charset)_unicode_ci"
            }
            return sql
        case 2:
            let db = quoteIdentifier(path[0])
            switch path[1] {
            case "Tables":
                let col = values["column", default: "id"]
                let type = values["type", default: "BIGINT AUTO_INCREMENT"]
                let engine = values["engine", default: "InnoDB"]
                return "CREATE TABLE \(db).\(q) (\(quoteIdentifier(col)) \(type) PRIMARY KEY) ENGINE=\(engine)"
            case "Views":
                let query = values["query", default: "SELECT 1"]
                return "CREATE VIEW \(db).\(q) AS \(query)"
            default:
                return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Deletion

    func isDeletable(path: [String]) -> Bool {
        switch path.count {
        case 1: true
        case 3: ["Tables", "Views"].contains(path[1])
        default: false
        }
    }

    func generateDropSQL(path: [String]) -> String? {
        switch path.count {
        case 1:
            return "DROP DATABASE \(quoteIdentifier(path[0]))"
        case 3:
            let fqn = "\(quoteIdentifier(path[0])).\(quoteIdentifier(path[2]))"
            switch path[1] {
            case "Tables": return "DROP TABLE \(fqn)"
            case "Views":  return "DROP VIEW \(fqn)"
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Tree navigation

    func listChildren(path: [String]) async throws -> [HierarchyNode] {
        switch path.count {
        case 0:
            let conn = try getAnyConnection()
            let sql = """
                SELECT SCHEMA_NAME FROM information_schema.SCHEMATA \
                WHERE SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema','sys') \
                ORDER BY SCHEMA_NAME
                """
            return try await queryNodeList(
                conn: conn, sql: sql,
                columnName: "SCHEMA_NAME",
                icon: "cylinder.split.1x2", tint: Self.tintDatabase, expandable: true
            )

        case 1:
            return [
                HierarchyNode(name: "Tables", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Views", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Functions", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Procedures", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Events", icon: "folder", tint: Self.tintGroup, isExpandable: true),
            ]

        case 2:
            let conn = try await connectionFor(database: path[0])
            let db = escapeSQLString(path[0])
            switch path[1] {
            case "Tables":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='\(db)' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME",
                    columnName: "TABLE_NAME",
                    icon: "tablecells", tint: Self.tintTable, expandable: true
                )
            case "Views":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='\(db)' AND TABLE_TYPE='VIEW' ORDER BY TABLE_NAME",
                    columnName: "TABLE_NAME",
                    icon: "eye", tint: Self.tintView, expandable: true
                )
            case "Functions":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='\(db)' AND ROUTINE_TYPE='FUNCTION' ORDER BY ROUTINE_NAME",
                    columnName: "ROUTINE_NAME",
                    icon: "function", tint: Self.tintFunction, expandable: false
                )
            case "Procedures":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='\(db)' AND ROUTINE_TYPE='PROCEDURE' ORDER BY ROUTINE_NAME",
                    columnName: "ROUTINE_NAME",
                    icon: "gearshape.2", tint: Self.tintProcedure, expandable: false
                )
            case "Events":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT EVENT_NAME FROM information_schema.EVENTS WHERE EVENT_SCHEMA='\(db)' ORDER BY EVENT_NAME",
                    columnName: "EVENT_NAME",
                    icon: "clock", tint: Self.tintEvent, expandable: false
                )
            default:
                throw DbError.other("unknown group: \(path[1])")
            }

        case 3:
            switch path[1] {
            case "Tables":
                return [
                    HierarchyNode(name: "Columns", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                    HierarchyNode(name: "Indexes", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                    HierarchyNode(name: "Constraints", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                    HierarchyNode(name: "Triggers", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                ]
            case "Views":
                return [
                    HierarchyNode(name: "Columns", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                ]
            default:
                return []
            }

        case 4:
            let conn = try await connectionFor(database: path[0])
            let db = escapeSQLString(path[0])
            let table = escapeSQLString(path[2])
            switch path[3] {
            case "Columns":
                return try await fetchTreeColumns(conn: conn, database: db, table: table)
            case "Indexes":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT DISTINCT INDEX_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='\(db)' AND TABLE_NAME='\(table)' ORDER BY INDEX_NAME",
                    columnName: "INDEX_NAME",
                    icon: "arrow.up.arrow.down", tint: Self.tintIndex, expandable: false
                )
            case "Constraints":
                return try await fetchTreeConstraints(conn: conn, database: db, table: table)
            case "Triggers":
                return try await queryNodeList(
                    conn: conn,
                    sql: "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE EVENT_OBJECT_SCHEMA='\(db)' AND EVENT_OBJECT_TABLE='\(table)' ORDER BY TRIGGER_NAME",
                    columnName: "TRIGGER_NAME",
                    icon: "bolt.fill", tint: Self.tintTrigger, expandable: false
                )
            default:
                return []
            }

        default:
            return []
        }
    }

    // MARK: - Node details

    func fetchNodeDetails(path: [String]) async throws -> QueryResult {
        guard path.count >= 1 else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        let conn = try await connectionFor(database: path[0])
        let db = escapeSQLString(path[0])

        let sql: String
        switch path.count {
        case 1, 2:
            sql = databaseDetailSQL(database: db, group: path.count == 2 ? path[1] : nil)
        case 3:
            sql = tableDetailSQL(database: db, table: escapeSQLString(path[2]))
        case 4:
            sql = subGroupDetailSQL(database: db, table: escapeSQLString(path[2]), subGroup: path[3])
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        return try await runQuery(conn: conn, sql: sql)
    }

    // MARK: - Private helpers

    private func escapeSQLString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func queryNodeList(
        conn: MySQLConnection,
        sql: String,
        columnName: String,
        icon: String,
        tint: NodeTint,
        expandable: Bool
    ) async throws -> [HierarchyNode] {
        let rows: [MySQLRow]
        do {
            rows = try await conn.simpleQuery(sql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        return rows.compactMap { row in
            guard let name = row.column(columnName)?.string else { return nil }
            return HierarchyNode(name: name, icon: icon, tint: tint, isExpandable: expandable)
        }
    }

    private func fetchTreeColumns(
        conn: MySQLConnection,
        database: String,
        table: String
    ) async throws -> [HierarchyNode] {
        let columns = try await fetchColumnInfo(conn: conn, database: database, table: table)
        return columns.map { col in
            HierarchyNode(
                name: "\(col.name) : \(col.typeName)",
                icon: col.isPrimaryKey ? "key.fill" : "circle.fill",
                tint: col.isPrimaryKey ? Self.tintKey : Self.tintColumn,
                isExpandable: false
            )
        }
    }

    private func fetchTreeConstraints(
        conn: MySQLConnection,
        database: String,
        table: String
    ) async throws -> [HierarchyNode] {
        let sql = """
            SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE \
            FROM information_schema.TABLE_CONSTRAINTS \
            WHERE TABLE_SCHEMA='\(database)' AND TABLE_NAME='\(table)' \
            ORDER BY CONSTRAINT_NAME
            """
        let rows: [MySQLRow]
        do {
            rows = try await conn.simpleQuery(sql).get()
        } catch {
            throw DbError.query(error.localizedDescription)
        }
        return rows.compactMap { row in
            guard let name = row.column("CONSTRAINT_NAME")?.string,
                  let conType = row.column("CONSTRAINT_TYPE")?.string else { return nil }
            let typeLabel = conType.lowercased()
            let icon = switch conType {
            case "PRIMARY KEY": "key.fill"
            case "FOREIGN KEY": "link"
            default: "checkmark.circle"
            }
            return HierarchyNode(
                name: "\(name) (\(typeLabel))",
                icon: icon,
                tint: Self.tintKey,
                isExpandable: false
            )
        }
    }

    private func databaseDetailSQL(database: String, group: String?) -> String {
        guard let group else {
            return """
                SELECT TABLE_NAME AS 'Name', \
                TABLE_TYPE AS 'Type', \
                ENGINE AS 'Engine', \
                TABLE_ROWS AS 'Rows (est.)', \
                ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024, 2) AS 'Size (KB)', \
                TABLE_COLLATION AS 'Collation' \
                FROM information_schema.TABLES \
                WHERE TABLE_SCHEMA='\(database)' \
                ORDER BY TABLE_TYPE, TABLE_NAME
                """
        }
        switch group {
        case "Tables":
            return """
                SELECT TABLE_NAME AS 'Table', \
                ENGINE AS 'Engine', \
                TABLE_ROWS AS 'Rows (est.)', \
                ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024, 2) AS 'Size (KB)', \
                TABLE_COLLATION AS 'Collation', \
                TABLE_COMMENT AS 'Comment' \
                FROM information_schema.TABLES \
                WHERE TABLE_SCHEMA='\(database)' AND TABLE_TYPE='BASE TABLE' \
                ORDER BY TABLE_NAME
                """
        case "Views":
            return """
                SELECT TABLE_NAME AS 'View', \
                CHECK_OPTION AS 'Check Option', \
                IS_UPDATABLE AS 'Updatable' \
                FROM information_schema.VIEWS \
                WHERE TABLE_SCHEMA='\(database)' \
                ORDER BY TABLE_NAME
                """
        case "Functions":
            return """
                SELECT ROUTINE_NAME AS 'Function', \
                DTD_IDENTIFIER AS 'Returns', \
                ROUTINE_COMMENT AS 'Comment' \
                FROM information_schema.ROUTINES \
                WHERE ROUTINE_SCHEMA='\(database)' AND ROUTINE_TYPE='FUNCTION' \
                ORDER BY ROUTINE_NAME
                """
        case "Procedures":
            return """
                SELECT ROUTINE_NAME AS 'Procedure', \
                ROUTINE_COMMENT AS 'Comment' \
                FROM information_schema.ROUTINES \
                WHERE ROUTINE_SCHEMA='\(database)' AND ROUTINE_TYPE='PROCEDURE' \
                ORDER BY ROUTINE_NAME
                """
        case "Events":
            return """
                SELECT EVENT_NAME AS 'Event', \
                EVENT_TYPE AS 'Type', \
                STATUS AS 'Status', \
                EVENT_COMMENT AS 'Comment' \
                FROM information_schema.EVENTS \
                WHERE EVENT_SCHEMA='\(database)' \
                ORDER BY EVENT_NAME
                """
        default:
            return "SELECT 1 AS `Info` WHERE false"
        }
    }

    private func tableDetailSQL(database: String, table: String) -> String {
        """
        SELECT TABLE_NAME AS 'Table', \
        ENGINE AS 'Engine', \
        TABLE_ROWS AS 'Rows (est.)', \
        ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024, 2) AS 'Size (KB)', \
        TABLE_COLLATION AS 'Collation', \
        TABLE_COMMENT AS 'Comment' \
        FROM information_schema.TABLES \
        WHERE TABLE_SCHEMA='\(database)' AND TABLE_NAME='\(table)'
        """
    }

    private func subGroupDetailSQL(database: String, table: String, subGroup: String) -> String {
        switch subGroup {
        case "Columns":
            return """
                SELECT COLUMN_NAME AS 'Column', \
                COLUMN_TYPE AS 'Type', \
                IS_NULLABLE AS 'Nullable', \
                COLUMN_DEFAULT AS 'Default', \
                COLUMN_KEY AS 'Key', \
                EXTRA AS 'Extra' \
                FROM information_schema.COLUMNS \
                WHERE TABLE_SCHEMA='\(database)' AND TABLE_NAME='\(table)' \
                ORDER BY ORDINAL_POSITION
                """
        case "Indexes":
            return """
                SELECT INDEX_NAME AS 'Index', \
                CASE NON_UNIQUE WHEN 0 THEN 'YES' ELSE 'NO' END AS 'Unique', \
                GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ') AS 'Columns', \
                INDEX_TYPE AS 'Type' \
                FROM information_schema.STATISTICS \
                WHERE TABLE_SCHEMA='\(database)' AND TABLE_NAME='\(table)' \
                GROUP BY INDEX_NAME, NON_UNIQUE, INDEX_TYPE \
                ORDER BY INDEX_NAME
                """
        case "Constraints":
            return """
                SELECT CONSTRAINT_NAME AS 'Constraint', \
                CONSTRAINT_TYPE AS 'Type' \
                FROM information_schema.TABLE_CONSTRAINTS \
                WHERE TABLE_SCHEMA='\(database)' AND TABLE_NAME='\(table)' \
                ORDER BY CONSTRAINT_NAME
                """
        case "Triggers":
            return """
                SELECT TRIGGER_NAME AS 'Trigger', \
                ACTION_TIMING AS 'Timing', \
                EVENT_MANIPULATION AS 'Event', \
                ACTION_STATEMENT AS 'Statement' \
                FROM information_schema.TRIGGERS \
                WHERE EVENT_OBJECT_SCHEMA='\(database)' AND EVENT_OBJECT_TABLE='\(table)' \
                ORDER BY TRIGGER_NAME, EVENT_MANIPULATION
                """
        default:
            return "SELECT 1 AS `Info` WHERE false"
        }
    }
}
