import Foundation

// Path structure (same as SQLite/ScyllaDB):
// []                                → schemas
// [schema]                          → groups (Tables, Views, …)
// [schema, group]                   → items in group
// [schema, "Tables", table]         → sub-groups (Columns, Indexes, …)
// [schema, "Tables", table, subgrp] → elements

extension DuckDBBackend {
    private static let tintSchema   = NodeTint(r: 0.773, g: 0.525, b: 0.753)
    private static let tintTable    = NodeTint(r: 0.420, g: 0.624, b: 0.800)
    private static let tintView     = NodeTint(r: 0.863, g: 0.863, b: 0.667)
    private static let tintGroup    = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintIndex    = NodeTint(r: 0.400, g: 0.694, b: 0.659)
    private static let tintSequence = NodeTint(r: 0.529, g: 0.753, b: 0.518)
    private static let tintFunction = NodeTint(r: 0.694, g: 0.506, b: 0.804)
    private static let tintType     = NodeTint(r: 0.878, g: 0.647, b: 0.412)
    private static let tintColumn   = NodeTint(r: 0.545, g: 0.659, b: 0.780)
    private static let tintKey      = NodeTint(r: 0.835, g: 0.718, b: 0.392)

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 3 && ["Tables", "Views"].contains(path[1])
    }

    func isEditable(path: [String]) -> Bool {
        path.count == 3 && path[1] == "Tables"
    }

    func isStructureEditable(path: [String]) -> Bool {
        path.count >= 4 && path[1] == "Tables" && path[3] == "Indexes"
    }

    // MARK: - Creation

    func creatableChildLabel(path: [String]) -> String? {
        switch path.count {
        case 0: "Schema"
        case 2:
            switch path[1] {
            case "Tables": "Table"
            case "Views": "View"
            case "Sequences": "Sequence"
            default: nil
            }
        default: nil
        }
    }

    private static let duckdbColumnTypes = [
        "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "HUGEINT",
        "VARCHAR", "TEXT", "CHAR(255)",
        "BOOLEAN",
        "DOUBLE", "FLOAT", "DECIMAL(18,2)",
        "DATE", "TIMESTAMP", "TIME", "INTERVAL",
        "UUID", "BLOB", "JSON",
    ]

    func createFormFields(path: [String]) -> [CreateField] {
        switch path.count {
        case 0:
            return [
                CreateField(id: "name", label: "Name", defaultValue: "", placeholder: "my_schema"),
            ]
        case 2:
            switch path[1] {
            case "Tables":
                return [
                    CreateField(id: "name", label: "Table Name", defaultValue: "", placeholder: "my_table"),
                    CreateField(id: "column", label: "Column Name", defaultValue: "id", placeholder: "id"),
                    CreateField(id: "type", label: "Column Type", defaultValue: "INTEGER", placeholder: "INTEGER",
                                options: Self.duckdbColumnTypes),
                ]
            case "Views":
                return [
                    CreateField(id: "name", label: "View Name", defaultValue: "", placeholder: "my_view"),
                    CreateField(id: "query", label: "AS Query", defaultValue: "SELECT 1", placeholder: "SELECT ..."),
                ]
            case "Sequences":
                return [
                    CreateField(id: "name", label: "Sequence Name", defaultValue: "", placeholder: "my_sequence"),
                    CreateField(id: "start", label: "Start Value", defaultValue: "1", placeholder: "1"),
                    CreateField(id: "increment", label: "Increment By", defaultValue: "1", placeholder: "1"),
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
            return "CREATE SCHEMA \(q)"
        case 2:
            let fqn = "\(quoteIdentifier(path[0])).\(q)"
            switch path[1] {
            case "Tables":
                let col = values["column", default: "id"]
                let type = values["type", default: "INTEGER"]
                return "CREATE TABLE \(fqn) (\(quoteIdentifier(col)) \(type) PRIMARY KEY)"
            case "Views":
                let query = values["query", default: "SELECT 1"]
                return "CREATE VIEW \(fqn) AS \(query)"
            case "Sequences":
                var sql = "CREATE SEQUENCE \(fqn)"
                let start = values["start", default: ""].trimmingCharacters(in: .whitespaces)
                if !start.isEmpty { sql += " START WITH \(start)" }
                let inc = values["increment", default: ""].trimmingCharacters(in: .whitespaces)
                if !inc.isEmpty { sql += " INCREMENT BY \(inc)" }
                return sql
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
        case 1: true          // schema
        case 3: ["Tables", "Views", "Sequences"].contains(path[1])
        default: false
        }
    }

    func generateDropSQL(path: [String]) -> String? {
        switch path.count {
        case 1:
            return "DROP SCHEMA \(quoteIdentifier(path[0])) CASCADE"
        case 3:
            let fqn = "\(quoteIdentifier(path[0])).\(quoteIdentifier(path[2]))"
            switch path[1] {
            case "Tables":    return "DROP TABLE \(fqn)"
            case "Views":     return "DROP VIEW \(fqn)"
            case "Sequences": return "DROP SEQUENCE \(fqn)"
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
            let result = try runSQL(
                "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'pg_catalog') ORDER BY schema_name"
            )
            return result.rows.compactMap { row in
                guard let name = row.first ?? nil else { return nil }
                return HierarchyNode(name: name, icon: "square.grid.2x2", tint: Self.tintSchema, isExpandable: true)
            }

        case 1:
            return [
                HierarchyNode(name: "Tables", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Views", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Sequences", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Functions", icon: "folder", tint: Self.tintGroup, isExpandable: true),
            ]

        case 2:
            let schema = path[0]
            switch path[1] {
            case "Tables":
                return try queryNodeList(
                    sql: "SELECT table_name FROM information_schema.tables WHERE table_schema = '\(schema)' AND table_type = 'BASE TABLE' ORDER BY table_name",
                    icon: "tablecells", tint: Self.tintTable, expandable: true
                )
            case "Views":
                return try queryNodeList(
                    sql: "SELECT table_name FROM information_schema.tables WHERE table_schema = '\(schema)' AND table_type = 'VIEW' ORDER BY table_name",
                    icon: "eye", tint: Self.tintView, expandable: true
                )
            case "Sequences":
                return try queryNodeList(
                    sql: "SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = '\(schema)' ORDER BY sequence_name",
                    icon: "number", tint: Self.tintSequence, expandable: false
                )
            case "Functions":
                return try queryNodeList(
                    sql: "SELECT DISTINCT function_name FROM duckdb_functions() WHERE schema_name = '\(schema)' AND function_type = 'scalar' AND NOT internal ORDER BY function_name",
                    icon: "function", tint: Self.tintFunction, expandable: false
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
                ]
            case "Views":
                return [
                    HierarchyNode(name: "Columns", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                ]
            default:
                return []
            }

        case 4:
            let schema = path[0]
            let relation = path[2]
            switch path[3] {
            case "Columns":
                return try fetchTreeColumns(schema: schema, relation: relation)
            case "Indexes":
                return try queryNodeList(
                    sql: "SELECT DISTINCT index_name FROM duckdb_indexes() WHERE schema_name = '\(schema)' AND table_name = '\(relation)' ORDER BY index_name",
                    icon: "arrow.up.arrow.down", tint: Self.tintIndex, expandable: false
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

        let schema = path[0]

        let sql: String
        switch path.count {
        case 2, 3:
            sql = groupDetailSQL(schema: schema, group: path[1])
        case 4:
            sql = subGroupDetailSQL(schema: schema, relation: path[2], subGroup: path[3])
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        return try runSQL(sql)
    }

    // MARK: - Private helpers

    private func queryNodeList(
        sql: String,
        icon: String,
        tint: NodeTint,
        expandable: Bool
    ) throws -> [HierarchyNode] {
        let result = try runSQL(sql)
        return result.rows.compactMap { row in
            guard let name = row.first ?? nil else { return nil }
            return HierarchyNode(name: name, icon: icon, tint: tint, isExpandable: expandable)
        }
    }

    private func fetchTreeColumns(schema: String, relation: String) throws -> [HierarchyNode] {
        let columns = try fetchColumnInfo(schema: schema, table: relation)
        return columns.map { col in
            HierarchyNode(
                name: "\(col.name) : \(col.typeName)",
                icon: col.isPrimaryKey ? "key.fill" : "circle.fill",
                tint: col.isPrimaryKey ? Self.tintKey : Self.tintColumn,
                isExpandable: false
            )
        }
    }

    private func groupDetailSQL(schema: String, group: String) -> String {
        switch group {
        case "Tables":
            return """
                SELECT table_name AS "Table" \
                FROM information_schema.tables \
                WHERE table_schema = '\(schema)' AND table_type = 'BASE TABLE' \
                ORDER BY table_name
                """
        case "Views":
            return """
                SELECT table_name AS "View" \
                FROM information_schema.tables \
                WHERE table_schema = '\(schema)' AND table_type = 'VIEW' \
                ORDER BY table_name
                """
        case "Sequences":
            return """
                SELECT sequence_name AS "Sequence", \
                start_value AS "Start", \
                increment AS "Increment", \
                minimum_value AS "Min", \
                maximum_value AS "Max" \
                FROM information_schema.sequences \
                WHERE sequence_schema = '\(schema)' \
                ORDER BY sequence_name
                """
        default:
            return "SELECT 1 AS \"Info\" WHERE false"
        }
    }

    private func subGroupDetailSQL(schema: String, relation: String, subGroup: String) -> String {
        switch subGroup {
        case "Columns":
            return """
                SELECT column_name AS "Column", \
                data_type AS "Type", \
                is_nullable AS "Nullable", \
                column_default AS "Default" \
                FROM information_schema.columns \
                WHERE table_schema = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY ordinal_position
                """
        case "Indexes":
            return """
                SELECT index_name AS "Index", \
                is_unique AS "Unique", \
                is_primary AS "Primary" \
                FROM duckdb_indexes() \
                WHERE schema_name = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY index_name
                """
        default:
            return "SELECT 1 AS \"Info\" WHERE false"
        }
    }
}
