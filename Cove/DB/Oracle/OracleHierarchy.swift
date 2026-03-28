import OracleNIO

// Path structure:
// []                                → schemas
// [schema]                          → groups (Tables, Views, …)
// [schema, group]                   → items in group
// [schema, "Tables", table]         → sub-groups (Columns, Indexes, …)
// [schema, "Tables", table, subgrp] → elements

extension OracleBackend {
    private static let tintSchema    = NodeTint(r: 0.773, g: 0.525, b: 0.753)
    private static let tintTable     = NodeTint(r: 0.420, g: 0.624, b: 0.800)
    private static let tintView      = NodeTint(r: 0.863, g: 0.863, b: 0.667)
    private static let tintMatView   = NodeTint(r: 0.749, g: 0.824, b: 0.600)
    private static let tintGroup     = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintIndex     = NodeTint(r: 0.400, g: 0.694, b: 0.659)
    private static let tintSequence  = NodeTint(r: 0.529, g: 0.753, b: 0.518)
    private static let tintFunction  = NodeTint(r: 0.694, g: 0.506, b: 0.804)
    private static let tintProcedure = NodeTint(r: 0.600, g: 0.450, b: 0.750)
    private static let tintPackage   = NodeTint(r: 0.500, g: 0.600, b: 0.800)
    private static let tintType      = NodeTint(r: 0.878, g: 0.647, b: 0.412)
    private static let tintColumn    = NodeTint(r: 0.545, g: 0.659, b: 0.780)
    private static let tintKey       = NodeTint(r: 0.835, g: 0.718, b: 0.392)
    private static let tintTrigger   = NodeTint(r: 0.835, g: 0.490, b: 0.392)

    static let systemSchemas: Set<String> = [
        "SYS", "SYSTEM", "AUDSYS", "DBSFWUSER", "DBSNMP", "OUTLN",
        "GSMADMIN_INTERNAL", "GSMCATUSER", "GSMUSER", "ANONYMOUS",
        "XDB", "WMSYS", "OJVMSYS", "CTXSYS", "ORDDATA", "ORDSYS",
        "MDSYS", "OLAPSYS", "DVSYS", "DVF", "LBACSYS", "XS$NULL",
        "APPQOSSYS", "DIP", "REMOTE_SCHEDULER_AGENT", "SYSBACKUP",
        "SYSDG", "SYSKM", "SYSRAC", "SYS$UMF", "DGPDB_INT",
        "GGSYS", "GGSHAREDCAP", "BAASSYS", "VECSYS",
        "GSMROOTUSER", "OPS$ORACLE", "PDBADMIN",
    ]

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 3 && ["Tables", "Views", "Materialized Views"].contains(path[1])
    }

    func isEditable(path: [String]) -> Bool {
        path.count == 3 && path[1] == "Tables"
    }

    func isStructureEditable(path: [String]) -> Bool {
        path.count >= 4 && path[1] == "Tables"
            && ["Indexes", "Constraints", "Triggers"].contains(path[3])
    }

    // MARK: - Creation

    func creatableChildLabel(path: [String]) -> String? {
        switch path.count {
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

    private static let oracleColumnTypes = [
        "NUMBER", "INTEGER", "BINARY_FLOAT", "BINARY_DOUBLE",
        "VARCHAR2(255)", "CHAR(1)", "NVARCHAR2(255)", "NCHAR(1)",
        "CLOB", "NCLOB", "BLOB", "RAW(2000)",
        "DATE", "TIMESTAMP", "TIMESTAMP WITH TIME ZONE",
    ]

    func createFormFields(path: [String]) -> [CreateField] {
        guard path.count == 2 else { return [] }
        switch path[1] {
        case "Tables":
            return [
                CreateField(id: "name", label: "Table Name", defaultValue: "", placeholder: "MY_TABLE"),
                CreateField(id: "column", label: "Column Name", defaultValue: "ID", placeholder: "ID"),
                CreateField(id: "type", label: "Column Type", defaultValue: "NUMBER", placeholder: "NUMBER",
                            options: Self.oracleColumnTypes),
            ]
        case "Views":
            return [
                CreateField(id: "name", label: "View Name", defaultValue: "", placeholder: "MY_VIEW"),
                CreateField(id: "query", label: "AS Query", defaultValue: "SELECT 1 FROM DUAL", placeholder: "SELECT ..."),
            ]
        case "Sequences":
            return [
                CreateField(id: "name", label: "Sequence Name", defaultValue: "", placeholder: "MY_SEQUENCE"),
                CreateField(id: "start", label: "Start Value", defaultValue: "1", placeholder: "1"),
                CreateField(id: "increment", label: "Increment By", defaultValue: "1", placeholder: "1"),
            ]
        default:
            return []
        }
    }

    func generateCreateChildSQL(path: [String], values: [String: String]) -> String? {
        guard path.count == 2 else { return nil }
        let name = values["name", default: ""].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let q = quoteIdentifier(name)
        let fqn = "\(quoteIdentifier(path[0])).\(q)"

        switch path[1] {
        case "Tables":
            let col = values["column", default: "ID"]
            let type = values["type", default: "NUMBER"]
            return "CREATE TABLE \(fqn) (\(quoteIdentifier(col)) \(type) PRIMARY KEY)"
        case "Views":
            let query = values["query", default: "SELECT 1 FROM DUAL"]
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
    }

    // MARK: - Deletion

    func isDeletable(path: [String]) -> Bool {
        switch path.count {
        case 3:
            ["Tables", "Views", "Materialized Views", "Sequences"].contains(path[1])
        default: false
        }
    }

    func generateDropSQL(path: [String]) -> String? {
        guard path.count == 3 else { return nil }
        let fqn = "\(quoteIdentifier(path[0])).\(quoteIdentifier(path[2]))"
        switch path[1] {
        case "Tables":             return "DROP TABLE \(fqn) CASCADE CONSTRAINTS"
        case "Views":              return "DROP VIEW \(fqn)"
        case "Materialized Views": return "DROP MATERIALIZED VIEW \(fqn)"
        case "Sequences":          return "DROP SEQUENCE \(fqn)"
        default: return nil
        }
    }

    // MARK: - Tree navigation

    func listChildren(path: [String]) async throws -> [HierarchyNode] {
        switch path.count {
        case 0:
            let all = try await queryNodeList(
                sql: "SELECT username FROM all_users ORDER BY username",
                icon: "square.grid.2x2", tint: Self.tintSchema, expandable: true
            )
            return all.filter { !Self.systemSchemas.contains($0.name) }

        case 1:
            return [
                HierarchyNode(name: "Tables", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Views", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Materialized Views", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Sequences", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Functions", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Procedures", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Packages", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Types", icon: "folder", tint: Self.tintGroup, isExpandable: true),
            ]

        case 2:
            let schema = path[0]
            switch path[1] {
            case "Tables":
                return try await queryNodeList(
                    sql: "SELECT table_name FROM all_tables WHERE owner = '\(schema)' ORDER BY table_name",
                    icon: "tablecells", tint: Self.tintTable, expandable: true
                )
            case "Views":
                return try await queryNodeList(
                    sql: "SELECT view_name FROM all_views WHERE owner = '\(schema)' ORDER BY view_name",
                    icon: "eye", tint: Self.tintView, expandable: true
                )
            case "Materialized Views":
                return try await queryNodeList(
                    sql: "SELECT mview_name FROM all_mviews WHERE owner = '\(schema)' ORDER BY mview_name",
                    icon: "eye.fill", tint: Self.tintMatView, expandable: true
                )
            case "Sequences":
                return try await queryNodeList(
                    sql: "SELECT sequence_name FROM all_sequences WHERE sequence_owner = '\(schema)' ORDER BY sequence_name",
                    icon: "number", tint: Self.tintSequence, expandable: false
                )
            case "Functions":
                return try await queryNodeList(
                    sql: "SELECT object_name FROM all_procedures WHERE owner = '\(schema)' AND object_type = 'FUNCTION' AND procedure_name IS NULL ORDER BY object_name",
                    icon: "function", tint: Self.tintFunction, expandable: false
                )
            case "Procedures":
                return try await queryNodeList(
                    sql: "SELECT object_name FROM all_procedures WHERE owner = '\(schema)' AND object_type = 'PROCEDURE' AND procedure_name IS NULL ORDER BY object_name",
                    icon: "function", tint: Self.tintProcedure, expandable: false
                )
            case "Packages":
                return try await queryNodeList(
                    sql: "SELECT object_name FROM all_objects WHERE owner = '\(schema)' AND object_type = 'PACKAGE' ORDER BY object_name",
                    icon: "shippingbox", tint: Self.tintPackage, expandable: false
                )
            case "Types":
                return try await queryNodeList(
                    sql: "SELECT type_name FROM all_types WHERE owner = '\(schema)' ORDER BY type_name",
                    icon: "textformat", tint: Self.tintType, expandable: false
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
            case "Materialized Views":
                return [
                    HierarchyNode(name: "Columns", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                    HierarchyNode(name: "Indexes", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                ]
            default:
                return []
            }

        case 4:
            let schema = path[0]
            let relation = path[2]
            switch path[3] {
            case "Columns":
                return try await fetchTreeColumns(schema: schema, relation: relation)
            case "Indexes":
                return try await queryNodeList(
                    sql: "SELECT index_name FROM all_indexes WHERE owner = '\(schema)' AND table_name = '\(relation)' ORDER BY index_name",
                    icon: "arrow.up.arrow.down", tint: Self.tintIndex, expandable: false
                )
            case "Constraints":
                return try await fetchTreeConstraints(schema: schema, relation: relation)
            case "Triggers":
                return try await queryNodeList(
                    sql: "SELECT trigger_name FROM all_triggers WHERE owner = '\(schema)' AND table_name = '\(relation)' ORDER BY trigger_name",
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

        let schema = path[0]

        return try await client.withConnection { conn in
            let sql: String
            switch path.count {
            case 2:
                sql = self.groupDetailSQL(schema: schema, group: path[1])
            case 3:
                sql = self.groupDetailSQL(schema: schema, group: path[1])
            case 4:
                sql = self.subGroupDetailSQL(schema: schema, relation: path[2], subGroup: path[3])
            default:
                return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
            }

            return try await self.runQuery(conn: &conn, sql: sql)
        }
    }

    // MARK: - Private helpers

    private func queryNodeList(
        sql: String,
        icon: String,
        tint: NodeTint,
        expandable: Bool
    ) async throws -> [HierarchyNode] {
        try await client.withConnection { conn in
            let rows = try await conn.execute(OracleStatement(unsafeSQL: sql))
            var nodes: [HierarchyNode] = []
            for try await row in rows.decode(String.self) {
                nodes.append(HierarchyNode(name: row, icon: icon, tint: tint, isExpandable: expandable))
            }
            return nodes
        }
    }

    private func fetchTreeColumns(
        schema: String,
        relation: String
    ) async throws -> [HierarchyNode] {
        try await client.withConnection { conn in
            let columns = try await self.fetchColumnInfo(conn: &conn, schema: schema, table: relation)
            return columns.map { col in
                HierarchyNode(
                    name: "\(col.name) : \(col.typeName)",
                    icon: col.isPrimaryKey ? "key.fill" : "circle.fill",
                    tint: col.isPrimaryKey ? Self.tintKey : Self.tintColumn,
                    isExpandable: false
                )
            }
        }
    }

    private func fetchTreeConstraints(
        schema: String,
        relation: String
    ) async throws -> [HierarchyNode] {
        try await client.withConnection { conn in
            let sql = """
                SELECT constraint_name, constraint_type \
                FROM all_constraints \
                WHERE owner = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY constraint_name
                """
            let rows = try await conn.execute(OracleStatement(unsafeSQL: sql))
            var nodes: [HierarchyNode] = []
            for try await (name, contype) in rows.decode((String, String).self) {
                let typeLabel = switch contype {
                case "P": "primary key"
                case "R": "foreign key"
                case "U": "unique"
                case "C": "check"
                default: contype
                }
                let icon = switch contype {
                case "P": "key.fill"
                case "R": "link"
                default: "checkmark.circle"
                }
                nodes.append(HierarchyNode(
                    name: "\(name) (\(typeLabel))",
                    icon: icon,
                    tint: Self.tintKey,
                    isExpandable: false
                ))
            }
            return nodes
        }
    }

    private func groupDetailSQL(schema: String, group: String) -> String {
        switch group {
        case "Tables":
            return """
                SELECT table_name AS "Table", \
                num_rows AS "Rows (est.)", \
                blocks AS "Blocks", \
                avg_row_len AS "Avg Row Len" \
                FROM all_tables \
                WHERE owner = '\(schema)' \
                ORDER BY table_name
                """
        case "Views":
            return """
                SELECT view_name AS "View", \
                text_length AS "Text Length" \
                FROM all_views \
                WHERE owner = '\(schema)' \
                ORDER BY view_name
                """
        case "Materialized Views":
            return """
                SELECT mview_name AS "Materialized View", \
                refresh_mode AS "Refresh Mode", \
                refresh_method AS "Refresh Method", \
                last_refresh_date AS "Last Refresh" \
                FROM all_mviews \
                WHERE owner = '\(schema)' \
                ORDER BY mview_name
                """
        case "Sequences":
            return """
                SELECT sequence_name AS "Sequence", \
                min_value AS "Min", \
                max_value AS "Max", \
                increment_by AS "Increment", \
                last_number AS "Last Number" \
                FROM all_sequences \
                WHERE sequence_owner = '\(schema)' \
                ORDER BY sequence_name
                """
        case "Functions":
            return """
                SELECT object_name AS "Function", \
                status AS "Status", \
                created AS "Created" \
                FROM all_objects \
                WHERE owner = '\(schema)' AND object_type = 'FUNCTION' \
                ORDER BY object_name
                """
        case "Procedures":
            return """
                SELECT object_name AS "Procedure", \
                status AS "Status", \
                created AS "Created" \
                FROM all_objects \
                WHERE owner = '\(schema)' AND object_type = 'PROCEDURE' \
                ORDER BY object_name
                """
        case "Packages":
            return """
                SELECT object_name AS "Package", \
                status AS "Status", \
                created AS "Created" \
                FROM all_objects \
                WHERE owner = '\(schema)' AND object_type = 'PACKAGE' \
                ORDER BY object_name
                """
        case "Types":
            return """
                SELECT type_name AS "Type", \
                typecode AS "Kind", \
                attributes AS "Attributes", \
                methods AS "Methods" \
                FROM all_types \
                WHERE owner = '\(schema)' \
                ORDER BY type_name
                """
        default:
            return "SELECT 1 AS \"Info\" FROM DUAL WHERE 1=0"
        }
    }

    private func subGroupDetailSQL(schema: String, relation: String, subGroup: String) -> String {
        switch subGroup {
        case "Columns":
            return """
                SELECT column_name AS "Column", \
                data_type || \
                CASE \
                    WHEN data_precision IS NOT NULL THEN '(' || data_precision || \
                        CASE WHEN data_scale > 0 THEN ',' || data_scale ELSE '' END || ')' \
                    WHEN char_length > 0 THEN '(' || char_length || ')' \
                    ELSE '' \
                END AS "Type", \
                CASE WHEN nullable = 'N' THEN 'NO' ELSE 'YES' END AS "Nullable", \
                data_default AS "Default" \
                FROM all_tab_columns \
                WHERE owner = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY column_id
                """
        case "Indexes":
            return """
                SELECT index_name AS "Index", \
                index_type AS "Type", \
                uniqueness AS "Uniqueness", \
                status AS "Status" \
                FROM all_indexes \
                WHERE owner = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY index_name
                """
        case "Constraints":
            return """
                SELECT constraint_name AS "Constraint", \
                CASE constraint_type \
                    WHEN 'P' THEN 'PRIMARY KEY' \
                    WHEN 'R' THEN 'FOREIGN KEY' \
                    WHEN 'U' THEN 'UNIQUE' \
                    WHEN 'C' THEN 'CHECK' \
                END AS "Type", \
                search_condition AS "Definition", \
                status AS "Status" \
                FROM all_constraints \
                WHERE owner = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY constraint_name
                """
        case "Triggers":
            return """
                SELECT trigger_name AS "Trigger", \
                trigger_type AS "Type", \
                triggering_event AS "Event", \
                status AS "Status" \
                FROM all_triggers \
                WHERE owner = '\(schema)' AND table_name = '\(relation)' \
                ORDER BY trigger_name
                """
        default:
            return "SELECT 1 AS \"Info\" FROM DUAL WHERE 1=0"
        }
    }
}
