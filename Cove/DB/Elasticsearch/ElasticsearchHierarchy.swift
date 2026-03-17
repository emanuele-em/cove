import Foundation

// Path structure:
// []                           -> indices (filter system indices starting with .)
// ["my-index"]                 -> groups: Mappings, Aliases, Settings
// ["my-index", "Mappings"]     -> field names with types (leaf)
// ["my-index", "Aliases"]      -> alias names (leaf)
// ["my-index", "Settings"]     -> settings entries (leaf)

extension ElasticsearchBackend {
    private static let tintIndex    = NodeTint(r: 0.200, g: 0.600, b: 0.800)
    private static let tintGroup    = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintField    = NodeTint(r: 0.500, g: 0.700, b: 0.400)
    private static let tintAlias    = NodeTint(r: 0.700, g: 0.550, b: 0.350)
    private static let tintSetting  = NodeTint(r: 0.600, g: 0.400, b: 0.700)

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 1
    }

    func isEditable(path: [String]) -> Bool {
        path.count == 1
    }

    func isStructureEditable(path: [String]) -> Bool {
        false
    }

    func structurePath(for tablePath: [String]) -> [String]? {
        guard tablePath.count == 1 else { return nil }
        return tablePath + ["Mappings"]
    }

    // MARK: - Creation

    func creatableChildLabel(path: [String]) -> String? {
        switch path.count {
        case 0: "Index"
        default: nil
        }
    }

    func createFormFields(path: [String]) -> [CreateField] {
        guard path.isEmpty else { return [] }
        return [
            CreateField(id: "name", label: "Index Name", defaultValue: "", placeholder: "my-index"),
            CreateField(id: "shards", label: "Number of Shards", defaultValue: "1", placeholder: "1"),
            CreateField(id: "replicas", label: "Number of Replicas", defaultValue: "0", placeholder: "0"),
        ]
    }

    func generateCreateChildSQL(path: [String], values: [String: String]) -> String? {
        guard path.isEmpty else { return nil }
        let name = values["name", default: ""].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let shards = values["shards", default: "1"]
        let replicas = values["replicas", default: "0"]

        return "PUT /\(name)\n{\"settings\": {\"number_of_shards\": \(shards), \"number_of_replicas\": \(replicas)}}"
    }

    // MARK: - Deletion

    func isDeletable(path: [String]) -> Bool {
        path.count == 1
    }

    func generateDropSQL(path: [String]) -> String? {
        guard path.count == 1 else { return nil }
        return "DELETE /\(path[0])"
    }

    // MARK: - Tree navigation

    func listChildren(path: [String]) async throws -> [HierarchyNode] {
        switch path.count {
        case 0:
            return try await listIndices()
        case 1:
            return listGroups()
        case 2:
            return try await listGroupChildren(path: path)
        default:
            return []
        }
    }

    // MARK: - Node details

    func fetchNodeDetails(path: [String]) async throws -> QueryResult {
        guard path.count == 1 else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        let indexName = path[0]
        let catResult = try await request(
            method: "GET",
            path: "/_cat/indices/\(indexName)?format=json"
        )

        guard let entries = catResult as? [[String: Any]], let info = entries.first else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        var rows: [[String?]] = [["Index", indexName]]

        let fields: [(String, String)] = [
            ("health", "Health"),
            ("status", "Status"),
            ("docs.count", "Document Count"),
            ("store.size", "Store Size"),
            ("pri", "Primary Shards"),
            ("rep", "Replica Shards"),
            ("pri.store.size", "Primary Store Size"),
        ]

        for (key, label) in fields {
            if let val = info[key] {
                rows.append([label, "\(val)"])
            }
        }

        let cols = [
            ColumnInfo(name: "Property", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
        ]
        return QueryResult(columns: cols, rows: rows, rowsAffected: nil, totalCount: nil)
    }

    // MARK: - Private helpers

    private func listIndices() async throws -> [HierarchyNode] {
        let result = try await request(
            method: "GET",
            path: "/_cat/indices?format=json&h=index,health,status,docs.count,store.size"
        )

        guard let entries = result as? [[String: Any]] else { return [] }

        return entries
            .compactMap { entry -> (String, String)? in
                guard let name = entry["index"] as? String,
                      !name.hasPrefix(".") else { return nil }
                let health = entry["health"] as? String ?? ""
                return (name, health)
            }
            .sorted { $0.0 < $1.0 }
            .map { name, _ in
                HierarchyNode(
                    name: name,
                    icon: "tablecells",
                    tint: Self.tintIndex,
                    isExpandable: true
                )
            }
    }

    private func listGroups() -> [HierarchyNode] {
        [
            HierarchyNode(name: "Mappings", icon: "list.bullet.rectangle", tint: Self.tintGroup, isExpandable: true),
            HierarchyNode(name: "Aliases", icon: "arrow.triangle.branch", tint: Self.tintGroup, isExpandable: true),
            HierarchyNode(name: "Settings", icon: "gearshape", tint: Self.tintGroup, isExpandable: true),
        ]
    }

    private func listGroupChildren(path: [String]) async throws -> [HierarchyNode] {
        let indexName = path[0]
        let group = path[1]

        switch group {
        case "Mappings":
            return try await listMappings(index: indexName)
        case "Aliases":
            return try await listAliases(index: indexName)
        case "Settings":
            return try await listSettings(index: indexName)
        default:
            return []
        }
    }

    private func listMappings(index: String) async throws -> [HierarchyNode] {
        let result = try await getJSON(path: "/\(index)/_mapping")

        guard let indexData = result[index] as? [String: Any],
              let mappings = indexData["mappings"] as? [String: Any],
              let properties = mappings["properties"] as? [String: Any] else {
            return []
        }

        return properties.keys.sorted().map { fieldName in
            let typeStr: String
            if let fieldInfo = properties[fieldName] as? [String: Any],
               let type = fieldInfo["type"] as? String {
                typeStr = type
            } else {
                typeStr = "object"
            }
            return HierarchyNode(
                name: "\(fieldName) (\(typeStr))",
                icon: "textformat",
                tint: Self.tintField,
                isExpandable: false
            )
        }
    }

    private func listAliases(index: String) async throws -> [HierarchyNode] {
        let result = try await getJSON(path: "/\(index)/_alias")

        guard let indexData = result[index] as? [String: Any],
              let aliases = indexData["aliases"] as? [String: Any] else {
            return []
        }

        if aliases.isEmpty {
            return [HierarchyNode(name: "(no aliases)", icon: "minus.circle", tint: Self.tintAlias, isExpandable: false)]
        }

        return aliases.keys.sorted().map { aliasName in
            HierarchyNode(
                name: aliasName,
                icon: "arrow.triangle.branch",
                tint: Self.tintAlias,
                isExpandable: false
            )
        }
    }

    private func listSettings(index: String) async throws -> [HierarchyNode] {
        let result = try await getJSON(path: "/\(index)/_settings")

        guard let indexData = result[index] as? [String: Any],
              let settings = indexData["settings"] as? [String: Any],
              let indexSettings = settings["index"] as? [String: Any] else {
            return []
        }

        let interestingKeys = [
            "number_of_shards", "number_of_replicas",
            "creation_date", "uuid", "provided_name",
            "refresh_interval", "max_result_window",
        ]

        var nodes: [HierarchyNode] = []
        for key in interestingKeys {
            if let val = indexSettings[key] {
                nodes.append(HierarchyNode(
                    name: "\(key): \(val)",
                    icon: "gearshape",
                    tint: Self.tintSetting,
                    isExpandable: false
                ))
            }
        }

        return nodes
    }
}
