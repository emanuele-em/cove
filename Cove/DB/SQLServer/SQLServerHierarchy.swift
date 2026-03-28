import CosmoMSSQL
import CosmoSQLCore

// Path structure (same as PostgreSQL):
// []                                     → databases
// [db]                                   → schemas
// [db, schema]                           → groups (Tables, Views, …)
// [db, schema, group]                    → items in group
// [db, schema, "Tables", table]          → sub-groups (Columns, Indexes, …)
// [db, schema, "Tables", table, subgrp]  → elements

extension SQLServerBackend {
    private static let tintDatabase = NodeTint(r: 0.357, g: 0.608, b: 0.835)
    private static let tintSchema   = NodeTint(r: 0.773, g: 0.525, b: 0.753)
    private static let tintTable    = NodeTint(r: 0.420, g: 0.624, b: 0.800)
    private static let tintView     = NodeTint(r: 0.863, g: 0.863, b: 0.667)
    private static let tintGroup    = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintIndex    = NodeTint(r: 0.400, g: 0.694, b: 0.659)
    private static let tintFunction = NodeTint(r: 0.694, g: 0.506, b: 0.804)
    private static let tintProcedure = NodeTint(r: 0.600, g: 0.450, b: 0.750)
    private static let tintType     = NodeTint(r: 0.878, g: 0.647, b: 0.412)
    private static let tintColumn   = NodeTint(r: 0.545, g: 0.659, b: 0.780)
    private static let tintKey      = NodeTint(r: 0.835, g: 0.718, b: 0.392)
    private static let tintTrigger  = NodeTint(r: 0.835, g: 0.490, b: 0.392)

    static let systemSchemas: Set<String> = [
        "guest", "INFORMATION_SCHEMA", "sys",
        "db_owner", "db_accessadmin", "db_securityadmin", "db_ddladmin",
        "db_backupoperator", "db_datareader", "db_datawriter",
        "db_denydatareader", "db_denydatawriter",
    ]

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 4 && ["Tables", "Views"].contains(path[2])
    }

    func isEditable(path: [String]) -> Bool {
        path.count == 4 && path[2] == "Tables"
    }

    func isStructureEditable(path: [String]) -> Bool {
        path.count >= 5 && path[2] == "Tables"
            && ["Indexes", "Constraints", "Triggers"].contains(path[4])
    }

    // MARK: - Creation

    func creatableChildLabel(path: [String]) -> String? {
        switch path.count {
        case 0: "Database"
        case 1: "Schema"
        case 3:
            switch path[2] {
            case "Tables": "Table"
            case "Views": "View"
            default: nil
            }
        default: nil
        }
    }

    private static let mssqlColumnTypes = [
        "int", "bigint", "smallint", "tinyint",
        "nvarchar(255)", "varchar(255)", "char(10)", "nchar(10)",
        "bit",
        "decimal(18,2)", "numeric(18,2)", "money", "float", "real",
        "date", "datetime2", "datetimeoffset", "time",
        "uniqueidentifier",
        "varbinary(MAX)", "xml", "nvarchar(MAX)",
    ]

    func createFormFields(path: [String]) -> [CreateField] {
        switch path.count {
        case 0:
            return [
                CreateField(id: "name", label: "Name", defaultValue: "", placeholder: "my_database"),
            ]
        case 1:
            return [
                CreateField(id: "name", label: "Name", defaultValue: "", placeholder: "my_schema"),
            ]
        case 3:
            switch path[2] {
            case "Tables":
                return [
                    CreateField(id: "name", label: "Table Name", defaultValue: "", placeholder: "my_table"),
                    CreateField(id: "column", label: "Column Name", defaultValue: "id", placeholder: "id"),
                    CreateField(id: "type", label: "Column Type", defaultValue: "int", placeholder: "int",
                                options: Self.mssqlColumnTypes),
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
            return "CREATE DATABASE \(q)"
        case 1:
            return "CREATE SCHEMA \(q)"
        case 3:
            let fqn = "\(quoteIdentifier(path[1])).\(q)"
            switch path[2] {
            case "Tables":
                let col = values["column", default: "id"]
                let type = values["type", default: "int"]
                return "CREATE TABLE \(fqn) (\(quoteIdentifier(col)) \(type) PRIMARY KEY)"
            case "Views":
                let query = values["query", default: "SELECT 1"]
                return "CREATE VIEW \(fqn) AS \(query)"
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
        case 1: true          // database
        case 2: true          // schema
        case 4:               // table/view
            ["Tables", "Views"].contains(path[2])
        default: false
        }
    }

    func generateDropSQL(path: [String]) -> String? {
        switch path.count {
        case 1:
            return "DROP DATABASE \(quoteIdentifier(path[0]))"
        case 2:
            return "DROP SCHEMA \(quoteIdentifier(path[1]))"
        case 4:
            let fqn = "\(quoteIdentifier(path[1])).\(quoteIdentifier(path[3]))"
            switch path[2] {
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
            if !initialDatabase.isEmpty {
                return [HierarchyNode(name: initialDatabase, icon: "cylinder.split.1x2", tint: Self.tintDatabase, isExpandable: true)]
            }
            let pool = try getAnyPool()
            let rows = try await pool.query(
                "SELECT name FROM sys.databases ORDER BY name", []
            )
            return rows.compactMap { row in
                guard let name = row.values[0].asString() else { return nil }
                return HierarchyNode(name: name, icon: "cylinder.split.1x2", tint: Self.tintDatabase, isExpandable: true)
            }

        case 1:
            let pool = poolFor(database: path[0])
            let rows = try await pool.query(
                "SELECT s.name FROM sys.schemas s WHERE s.schema_id < 16384 ORDER BY s.name", []
            )
            return rows.compactMap { row in
                guard let name = row.values[0].asString(),
                      !Self.systemSchemas.contains(name) else { return nil }
                return HierarchyNode(name: name, icon: "square.grid.2x2", tint: Self.tintSchema, isExpandable: true)
            }

        case 2:
            return [
                HierarchyNode(name: "Tables", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Views", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Functions", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Procedures", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Types", icon: "folder", tint: Self.tintGroup, isExpandable: true),
            ]

        case 3:
            let pool = poolFor(database: path[0])
            let schema = path[1]
            switch path[2] {
            case "Tables":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '\(schema)' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME",
                    icon: "tablecells", tint: Self.tintTable, expandable: true
                )
            case "Views":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '\(schema)' AND TABLE_TYPE = 'VIEW' ORDER BY TABLE_NAME",
                    icon: "eye", tint: Self.tintView, expandable: true
                )
            case "Functions":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT name FROM sys.objects WHERE schema_id = SCHEMA_ID('\(schema)') AND type IN ('FN','IF','TF') ORDER BY name",
                    icon: "function", tint: Self.tintFunction, expandable: false
                )
            case "Procedures":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT name FROM sys.procedures WHERE schema_id = SCHEMA_ID('\(schema)') ORDER BY name",
                    icon: "function", tint: Self.tintProcedure, expandable: false
                )
            case "Types":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT name FROM sys.types WHERE schema_id = SCHEMA_ID('\(schema)') AND is_user_defined = 1 ORDER BY name",
                    icon: "textformat", tint: Self.tintType, expandable: false
                )
            default:
                throw DbError.other("unknown group: \(path[2])")
            }

        case 4:
            switch path[2] {
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

        case 5:
            let pool = poolFor(database: path[0])
            let schema = path[1]
            let relation = path[3]
            switch path[4] {
            case "Columns":
                return try await fetchTreeColumns(pool: pool, schema: schema, relation: relation)
            case "Indexes":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT i.name FROM sys.indexes i JOIN sys.objects o ON i.object_id = o.object_id JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE s.name = '\(schema)' AND o.name = '\(relation)' AND i.name IS NOT NULL ORDER BY i.name",
                    icon: "arrow.up.arrow.down", tint: Self.tintIndex, expandable: false
                )
            case "Constraints":
                return try await fetchTreeConstraints(pool: pool, schema: schema, relation: relation)
            case "Triggers":
                return try await queryNodeList(
                    pool: pool,
                    sql: "SELECT t.name FROM sys.triggers t JOIN sys.objects o ON t.parent_id = o.object_id JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE s.name = '\(schema)' AND o.name = '\(relation)' ORDER BY t.name",
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
        guard path.count >= 2 else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        let pool = poolFor(database: path[0])

        let sql: String
        switch path.count {
        case 2:
            sql = schemaDetailSQL(schema: path[1])
        case 3, 4:
            sql = groupDetailSQL(schema: path[1], group: path[2])
        case 5, 6:
            sql = subGroupDetailSQL(schema: path[1], relation: path[3], subGroup: path[4])
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        return try await runQuery(pool: pool, sql: sql)
    }

    // MARK: - Private helpers

    private func queryNodeList(
        pool: MSSQLConnectionPool,
        sql: String,
        icon: String,
        tint: NodeTint,
        expandable: Bool
    ) async throws -> [HierarchyNode] {
        let rows = try await pool.query(sql, [])
        return rows.compactMap { row in
            guard let name = row.values[0].asString() else { return nil }
            return HierarchyNode(name: name, icon: icon, tint: tint, isExpandable: expandable)
        }
    }

    private func fetchTreeColumns(
        pool: MSSQLConnectionPool,
        schema: String,
        relation: String
    ) async throws -> [HierarchyNode] {
        let columns = try await fetchColumnInfo(pool: pool, schema: schema, table: relation)
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
        pool: MSSQLConnectionPool,
        schema: String,
        relation: String
    ) async throws -> [HierarchyNode] {
        let sql = """
            SELECT o.name, o.type \
            FROM sys.objects o \
            JOIN sys.objects parent ON o.parent_object_id = parent.object_id \
            JOIN sys.schemas s ON parent.schema_id = s.schema_id \
            WHERE s.name = '\(schema)' AND parent.name = '\(relation)' \
            AND o.type IN ('PK','F','UQ','C') \
            ORDER BY o.name
            """
        let rows = try await pool.query(sql, [])
        return rows.compactMap { row in
            guard let name = row["name"].asString(),
                  let contype = row["type"].asString()?.trimmingCharacters(in: .whitespaces) else { return nil }
            let typeLabel = switch contype {
            case "PK": "primary key"
            case "F": "foreign key"
            case "UQ": "unique"
            case "C": "check"
            default: contype
            }
            let icon = switch contype {
            case "PK": "key.fill"
            case "F": "link"
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

    private func schemaDetailSQL(schema: String) -> String {
        """
        SELECT o.name AS [Name], \
        CASE o.type \
            WHEN 'U' THEN 'Table' WHEN 'V' THEN 'View' \
            WHEN 'P' THEN 'Procedure' WHEN 'FN' THEN 'Function' \
        END AS [Type] \
        FROM sys.objects o \
        JOIN sys.schemas s ON o.schema_id = s.schema_id \
        WHERE s.name = '\(schema)' \
        AND o.type IN ('U', 'V', 'P', 'FN', 'IF', 'TF') \
        ORDER BY o.type, o.name
        """
    }

    private func groupDetailSQL(schema: String, group: String) -> String {
        switch group {
        case "Tables":
            return """
                SELECT t.TABLE_NAME AS [Table], \
                (SELECT SUM(p.rows) FROM sys.partitions p \
                JOIN sys.objects o ON p.object_id = o.object_id \
                JOIN sys.schemas s ON o.schema_id = s.schema_id \
                WHERE s.name = t.TABLE_SCHEMA AND o.name = t.TABLE_NAME AND p.index_id IN (0,1)) AS [Rows (est.)] \
                FROM INFORMATION_SCHEMA.TABLES t \
                WHERE t.TABLE_SCHEMA = '\(schema)' AND t.TABLE_TYPE = 'BASE TABLE' \
                ORDER BY t.TABLE_NAME
                """
        case "Views":
            return """
                SELECT TABLE_NAME AS [View] \
                FROM INFORMATION_SCHEMA.TABLES \
                WHERE TABLE_SCHEMA = '\(schema)' AND TABLE_TYPE = 'VIEW' \
                ORDER BY TABLE_NAME
                """
        case "Functions":
            return """
                SELECT name AS [Function], \
                CASE type WHEN 'FN' THEN 'Scalar' WHEN 'IF' THEN 'Inline Table' WHEN 'TF' THEN 'Table' END AS [Type], \
                create_date AS [Created] \
                FROM sys.objects \
                WHERE schema_id = SCHEMA_ID('\(schema)') AND type IN ('FN','IF','TF') \
                ORDER BY name
                """
        case "Procedures":
            return """
                SELECT name AS [Procedure], \
                create_date AS [Created], \
                modify_date AS [Modified] \
                FROM sys.procedures \
                WHERE schema_id = SCHEMA_ID('\(schema)') \
                ORDER BY name
                """
        case "Types":
            return """
                SELECT name AS [Type], \
                CASE WHEN is_table_type = 1 THEN 'Table Type' ELSE 'Type' END AS [Kind] \
                FROM sys.types \
                WHERE schema_id = SCHEMA_ID('\(schema)') AND is_user_defined = 1 \
                ORDER BY name
                """
        default:
            return "SELECT 1 AS [Info] WHERE 1=0"
        }
    }

    private func subGroupDetailSQL(schema: String, relation: String, subGroup: String) -> String {
        switch subGroup {
        case "Columns":
            return """
                SELECT COLUMN_NAME AS [Column], \
                DATA_TYPE + \
                CASE \
                    WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN '(' + \
                        CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX' \
                        ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR) END + ')' \
                    WHEN NUMERIC_PRECISION IS NOT NULL THEN '(' + CAST(NUMERIC_PRECISION AS VARCHAR) + \
                        CASE WHEN NUMERIC_SCALE > 0 THEN ',' + CAST(NUMERIC_SCALE AS VARCHAR) ELSE '' END + ')' \
                    ELSE '' \
                END AS [Type], \
                IS_NULLABLE AS [Nullable], \
                COLUMN_DEFAULT AS [Default] \
                FROM INFORMATION_SCHEMA.COLUMNS \
                WHERE TABLE_SCHEMA = '\(schema)' AND TABLE_NAME = '\(relation)' \
                ORDER BY ORDINAL_POSITION
                """
        case "Indexes":
            return """
                SELECT i.name AS [Index], \
                i.type_desc AS [Type], \
                CASE WHEN i.is_unique = 1 THEN 'YES' ELSE 'NO' END AS [Unique], \
                CASE WHEN i.is_primary_key = 1 THEN 'YES' ELSE 'NO' END AS [Primary] \
                FROM sys.indexes i \
                JOIN sys.objects o ON i.object_id = o.object_id \
                JOIN sys.schemas s ON o.schema_id = s.schema_id \
                WHERE s.name = '\(schema)' AND o.name = '\(relation)' AND i.name IS NOT NULL \
                ORDER BY i.name
                """
        case "Constraints":
            return """
                SELECT o.name AS [Constraint], \
                CASE o.type \
                    WHEN 'PK' THEN 'PRIMARY KEY' \
                    WHEN 'F' THEN 'FOREIGN KEY' \
                    WHEN 'UQ' THEN 'UNIQUE' \
                    WHEN 'C' THEN 'CHECK' \
                END AS [Type] \
                FROM sys.objects o \
                JOIN sys.objects parent ON o.parent_object_id = parent.object_id \
                JOIN sys.schemas s ON parent.schema_id = s.schema_id \
                WHERE s.name = '\(schema)' AND parent.name = '\(relation)' \
                AND o.type IN ('PK','F','UQ','C') \
                ORDER BY o.name
                """
        case "Triggers":
            return """
                SELECT t.name AS [Trigger], \
                CASE WHEN t.is_instead_of_trigger = 1 THEN 'INSTEAD OF' ELSE 'AFTER' END AS [Type], \
                CASE WHEN t.is_disabled = 1 THEN 'Disabled' ELSE 'Enabled' END AS [Status] \
                FROM sys.triggers t \
                JOIN sys.objects o ON t.parent_id = o.object_id \
                JOIN sys.schemas s ON o.schema_id = s.schema_id \
                WHERE s.name = '\(schema)' AND o.name = '\(relation)' \
                ORDER BY t.name
                """
        default:
            return "SELECT 1 AS [Info] WHERE 1=0"
        }
    }
}
