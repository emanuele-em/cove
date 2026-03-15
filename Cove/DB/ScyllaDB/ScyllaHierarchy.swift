import CassandraClient

// Path structure:
// []                               → keyspaces
// [ks]                             → groups (Tables, Materialized Views, …)
// [ks, group]                      → items in group
// [ks, "Tables", table]            → sub-groups (Columns, Indexes)
// [ks, "Tables", table, subgroup]  → elements

extension ScyllaBackend {
    private static let tintKeyspace = NodeTint(r: 0.357, g: 0.608, b: 0.835)
    private static let tintTable    = NodeTint(r: 0.420, g: 0.624, b: 0.800)
    private static let tintView     = NodeTint(r: 0.863, g: 0.863, b: 0.667)
    private static let tintGroup    = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintIndex    = NodeTint(r: 0.400, g: 0.694, b: 0.659)
    private static let tintFunction = NodeTint(r: 0.694, g: 0.506, b: 0.804)
    private static let tintType     = NodeTint(r: 0.878, g: 0.647, b: 0.412)
    private static let tintColumn   = NodeTint(r: 0.545, g: 0.659, b: 0.780)
    private static let tintKey      = NodeTint(r: 0.835, g: 0.718, b: 0.392)
    private static let tintAggregate = NodeTint(r: 0.529, g: 0.753, b: 0.518)

    static let systemKeyspaces: Set<String> = [
        "system", "system_schema", "system_traces", "system_auth",
        "system_distributed", "system_distributed_everywhere",
        "system_virtual_schema",
    ]

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 3 && ["Tables", "Materialized Views"].contains(path[1])
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
        case 0: "Keyspace"
        case 2:
            switch path[1] {
            case "Tables": "Table"
            default: nil
            }
        default: nil
        }
    }

    private static let cqlReplicationClasses = [
        "SimpleStrategy", "NetworkTopologyStrategy",
    ]

    private static let cqlColumnTypes = [
        "bigint", "int", "smallint", "tinyint", "varint",
        "text", "ascii", "varchar",
        "boolean", "uuid", "timeuuid",
        "float", "double", "decimal",
        "date", "timestamp", "time", "duration",
        "blob", "inet", "counter",
    ]

    func createFormFields(path: [String]) -> [CreateField] {
        switch path.count {
        case 0:
            return [
                CreateField(id: "name", label: "Name", defaultValue: "", placeholder: "my_keyspace"),
                CreateField(id: "class", label: "Replication Class", defaultValue: "SimpleStrategy",
                            placeholder: "SimpleStrategy", options: Self.cqlReplicationClasses),
                CreateField(id: "rf", label: "Replication Factor", defaultValue: "1", placeholder: "1"),
            ]
        case 2 where path[1] == "Tables":
            return [
                CreateField(id: "name", label: "Table Name", defaultValue: "", placeholder: "my_table"),
                CreateField(id: "column", label: "Column Name", defaultValue: "id", placeholder: "id"),
                CreateField(id: "type", label: "Column Type", defaultValue: "bigint", placeholder: "bigint",
                            options: Self.cqlColumnTypes),
            ]
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
            let cls = values["class", default: "SimpleStrategy"]
            let rf = values["rf", default: "1"]
            return "CREATE KEYSPACE \(q) WITH replication = {'class': '\(cls)', 'replication_factor': \(rf)}"
        case 2 where path[1] == "Tables":
            let col = values["column", default: "id"]
            let type = values["type", default: "bigint"]
            return "CREATE TABLE \(quoteIdentifier(path[0])).\(q) (\(quoteIdentifier(col)) \(type) PRIMARY KEY)"
        default:
            return nil
        }
    }

    // MARK: - Deletion

    func isDeletable(path: [String]) -> Bool {
        switch path.count {
        case 1: true                                                       // keyspace
        case 3: ["Tables", "Materialized Views"].contains(path[1])         // table / view
        default: false
        }
    }

    func generateDropSQL(path: [String]) -> String? {
        switch path.count {
        case 1:
            return "DROP KEYSPACE \(quoteIdentifier(path[0]))"
        case 3:
            let fqn = "\(quoteIdentifier(path[0])).\(quoteIdentifier(path[2]))"
            switch path[1] {
            case "Tables":             return "DROP TABLE \(fqn)"
            case "Materialized Views": return "DROP MATERIALIZED VIEW \(fqn)"
            default: return nil
            }
        default:
            return nil
        }
    }

    private func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - Tree navigation

    func listChildren(path: [String]) async throws -> [HierarchyNode] {
        switch path.count {
        case 0:
            let rows = try await client.query(
                "SELECT keyspace_name FROM system_schema.keyspaces"
            )
            var nodes: [HierarchyNode] = []
            for row in rows {
                guard let name = row.column("keyspace_name")?.string else { continue }
                if Self.systemKeyspaces.contains(name) { continue }
                nodes.append(HierarchyNode(
                    name: name, icon: "cylinder.split.1x2",
                    tint: Self.tintKeyspace, isExpandable: true
                ))
            }
            return nodes.sorted { $0.name < $1.name }

        case 1:
            return [
                HierarchyNode(name: "Tables", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Materialized Views", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Types", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Functions", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                HierarchyNode(name: "Aggregates", icon: "folder", tint: Self.tintGroup, isExpandable: true),
            ]

        case 2:
            let ks = path[0]
            switch path[1] {
            case "Tables":
                return try await queryNodeList(
                    cql: "SELECT table_name FROM system_schema.tables WHERE keyspace_name = '\(ks)'",
                    nameColumn: "table_name",
                    icon: "tablecells", tint: Self.tintTable, expandable: true
                )
            case "Materialized Views":
                return try await queryNodeList(
                    cql: "SELECT view_name FROM system_schema.views WHERE keyspace_name = '\(ks)'",
                    nameColumn: "view_name",
                    icon: "eye.fill", tint: Self.tintView, expandable: true
                )
            case "Types":
                return try await queryNodeList(
                    cql: "SELECT type_name FROM system_schema.types WHERE keyspace_name = '\(ks)'",
                    nameColumn: "type_name",
                    icon: "textformat", tint: Self.tintType, expandable: false
                )
            case "Functions":
                return try await fetchFunctionNodes(keyspace: ks)
            case "Aggregates":
                return try await fetchAggregateNodes(keyspace: ks)
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
            case "Materialized Views":
                return [
                    HierarchyNode(name: "Columns", icon: "folder", tint: Self.tintGroup, isExpandable: true),
                ]
            default:
                return []
            }

        case 4:
            let ks = path[0]
            let table = path[2]
            switch path[3] {
            case "Columns":
                return try await fetchTreeColumns(keyspace: ks, table: table)
            case "Indexes":
                return try await queryNodeList(
                    cql: "SELECT index_name FROM system_schema.indexes WHERE keyspace_name = '\(ks)' AND table_name = '\(table)'",
                    nameColumn: "index_name",
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

        let ks = path[0]

        switch path.count {
        case 2:
            return try await groupDetail(keyspace: ks, group: path[1])
        case 3:
            return try await itemDetail(keyspace: ks, group: path[1], name: path[2])
        case 4:
            return try await subGroupDetail(keyspace: ks, table: path[2], subGroup: path[3])
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }
    }

    // MARK: - Private helpers

    private func queryNodeList(
        cql: String,
        nameColumn: String,
        icon: String,
        tint: NodeTint,
        expandable: Bool
    ) async throws -> [HierarchyNode] {
        let rows = try await client.query(cql)
        var nodes: [HierarchyNode] = []
        for row in rows {
            guard let name = row.column(nameColumn)?.string else { continue }
            nodes.append(HierarchyNode(name: name, icon: icon, tint: tint, isExpandable: expandable))
        }
        return nodes.sorted { $0.name < $1.name }
    }

    private func fetchFunctionNodes(keyspace: String) async throws -> [HierarchyNode] {
        let rows = try await client.query(
            "SELECT function_name, argument_types FROM system_schema.functions WHERE keyspace_name = '\(keyspace)'"
        )
        var nodes: [HierarchyNode] = []
        for row in rows {
            guard let funcName = row.column("function_name")?.string else { continue }
            let argTypes = row.column("argument_types")?.stringArray ?? []
            let displayName = "\(funcName)(\(argTypes.joined(separator: ", ")))"
            nodes.append(HierarchyNode(
                name: displayName, icon: "function",
                tint: Self.tintFunction, isExpandable: false
            ))
        }
        return nodes.sorted { $0.name < $1.name }
    }

    private func fetchAggregateNodes(keyspace: String) async throws -> [HierarchyNode] {
        let rows = try await client.query(
            "SELECT aggregate_name, argument_types FROM system_schema.aggregates WHERE keyspace_name = '\(keyspace)'"
        )
        var nodes: [HierarchyNode] = []
        for row in rows {
            guard let aggName = row.column("aggregate_name")?.string else { continue }
            let argTypes = row.column("argument_types")?.stringArray ?? []
            let displayName = "\(aggName)(\(argTypes.joined(separator: ", ")))"
            nodes.append(HierarchyNode(
                name: displayName, icon: "sum",
                tint: Self.tintAggregate, isExpandable: false
            ))
        }
        return nodes.sorted { $0.name < $1.name }
    }

    private func fetchTreeColumns(keyspace: String, table: String) async throws -> [HierarchyNode] {
        let columns = try await fetchColumnInfo(keyspace: keyspace, table: table)
        return columns.map { col in
            HierarchyNode(
                name: "\(col.name) : \(col.typeName)",
                icon: col.isPrimaryKey ? "key.fill" : "circle.fill",
                tint: col.isPrimaryKey ? Self.tintKey : Self.tintColumn,
                isExpandable: false
            )
        }
    }

    private func groupDetail(keyspace: String, group: String) async throws -> QueryResult {
        switch group {
        case "Tables":
            let rows = try await client.query(
                "SELECT table_name, comment FROM system_schema.tables WHERE keyspace_name = '\(keyspace)'"
            )
            let cols = [
                ColumnInfo(name: "Table", typeName: "text", isPrimaryKey: false),
                ColumnInfo(name: "Comment", typeName: "text", isPrimaryKey: false),
            ]
            var resultRows: [[String?]] = []
            for row in rows {
                resultRows.append([
                    row.column("table_name")?.string,
                    row.column("comment")?.string,
                ])
            }
            resultRows.sort { ($0[0] ?? "") < ($1[0] ?? "") }
            return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
        case "Materialized Views":
            let rows = try await client.query(
                "SELECT view_name FROM system_schema.views WHERE keyspace_name = '\(keyspace)'"
            )
            let cols = [ColumnInfo(name: "View", typeName: "text", isPrimaryKey: false)]
            var resultRows: [[String?]] = []
            for row in rows {
                resultRows.append([row.column("view_name")?.string])
            }
            resultRows.sort { ($0[0] ?? "") < ($1[0] ?? "") }
            return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }
    }

    private func itemDetail(keyspace: String, group: String, name: String) async throws -> QueryResult {
        switch group {
        case "Types":
            return try await typeDetail(keyspace: keyspace, typeName: name)
        case "Functions":
            let baseName = name.prefix(while: { $0 != "(" })
            return try await functionDetail(keyspace: keyspace, functionName: String(baseName))
        case "Aggregates":
            let baseName = name.prefix(while: { $0 != "(" })
            return try await aggregateDetail(keyspace: keyspace, aggregateName: String(baseName))
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }
    }

    private func typeDetail(keyspace: String, typeName: String) async throws -> QueryResult {
        let rows = try await client.query(
            "SELECT type_name, field_names, field_types FROM system_schema.types WHERE keyspace_name = '\(keyspace)' AND type_name = '\(typeName)'"
        )
        let cols = [
            ColumnInfo(name: "Field", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Type", typeName: "text", isPrimaryKey: false),
        ]
        var resultRows: [[String?]] = []
        for row in rows {
            let names = row.column("field_names")?.stringArray ?? []
            let types = row.column("field_types")?.stringArray ?? []
            for (n, t) in zip(names, types) {
                resultRows.append([n, t])
            }
        }
        return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
    }

    private func functionDetail(keyspace: String, functionName: String) async throws -> QueryResult {
        let rows = try await client.query(
            "SELECT function_name, return_type, language, body, called_on_null_input FROM system_schema.functions WHERE keyspace_name = '\(keyspace)' AND function_name = '\(functionName)'"
        )
        let cols = [
            ColumnInfo(name: "Name", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Returns", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Language", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Body", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Called on NULL", typeName: "text", isPrimaryKey: false),
        ]
        var resultRows: [[String?]] = []
        for row in rows {
            resultRows.append([
                row.column("function_name")?.string,
                row.column("return_type")?.string,
                row.column("language")?.string,
                row.column("body")?.string,
                row.column("called_on_null_input")?.bool.map(String.init),
            ])
        }
        return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
    }

    private func aggregateDetail(keyspace: String, aggregateName: String) async throws -> QueryResult {
        let rows = try await client.query(
            "SELECT aggregate_name, state_func, state_type, final_func, return_type FROM system_schema.aggregates WHERE keyspace_name = '\(keyspace)' AND aggregate_name = '\(aggregateName)'"
        )
        let cols = [
            ColumnInfo(name: "Name", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "State Function", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "State Type", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Final Function", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Returns", typeName: "text", isPrimaryKey: false),
        ]
        var resultRows: [[String?]] = []
        for row in rows {
            resultRows.append([
                row.column("aggregate_name")?.string,
                row.column("state_func")?.string,
                row.column("state_type")?.string,
                row.column("final_func")?.string,
                row.column("return_type")?.string,
            ])
        }
        return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
    }

    private func subGroupDetail(keyspace: String, table: String, subGroup: String) async throws -> QueryResult {
        switch subGroup {
        case "Columns":
            return try await columnDetail(keyspace: keyspace, table: table)
        case "Indexes":
            return try await indexDetail(keyspace: keyspace, table: table)
        default:
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }
    }

    private func columnDetail(keyspace: String, table: String) async throws -> QueryResult {
        let rows = try await client.query(
            "SELECT column_name, type, kind, position FROM system_schema.columns WHERE keyspace_name = '\(keyspace)' AND table_name = '\(table)'"
        )
        let cols = [
            ColumnInfo(name: "Column", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Type", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Kind", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Position", typeName: "int", isPrimaryKey: false),
        ]
        var resultRows: [[String?]] = []
        for row in rows {
            resultRows.append([
                row.column("column_name")?.string,
                row.column("type")?.string,
                row.column("kind")?.string,
                row.column("position")?.int32.map(String.init),
            ])
        }
        resultRows.sort { a, b in
            let order = ["partition_key": 0, "clustering": 1, "static": 2, "regular": 3]
            let ao = order[a[2] ?? ""] ?? 4
            let bo = order[b[2] ?? ""] ?? 4
            if ao != bo { return ao < bo }
            return (a[0] ?? "") < (b[0] ?? "")
        }
        return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
    }

    private func indexDetail(keyspace: String, table: String) async throws -> QueryResult {
        let rows = try await client.query(
            "SELECT index_name, kind FROM system_schema.indexes WHERE keyspace_name = '\(keyspace)' AND table_name = '\(table)'"
        )
        let cols = [
            ColumnInfo(name: "Index", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Kind", typeName: "text", isPrimaryKey: false),
        ]
        var resultRows: [[String?]] = []
        for row in rows {
            resultRows.append([
                row.column("index_name")?.string,
                row.column("kind")?.string,
            ])
        }
        return QueryResult(columns: cols, rows: resultRows, rowsAffected: nil, totalCount: nil)
    }
}
