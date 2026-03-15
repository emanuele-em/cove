import Foundation
import RediStack

// Path structure:
// []                                    → databases (db0..dbN, non-empty + db0)
// ["0"]                                 → type groups: Strings, Hashes, Lists, Sets, Sorted Sets, Streams
// ["0", "Strings"]                      → keys of that type
// ["0", "Hashes", "user:profile:1001"]  → hash fields / key contents

extension RedisBackend {
    private static let tintDatabase   = NodeTint(r: 0.835, g: 0.310, b: 0.310)
    private static let tintGroup      = NodeTint(r: 0.60, g: 0.60, b: 0.60)
    private static let tintHash       = NodeTint(r: 0.878, g: 0.647, b: 0.412)

    // MARK: - Capability queries

    func isDataBrowsable(path: [String]) -> Bool {
        path.count == 2 || path.count == 3
    }

    func isEditable(path: [String]) -> Bool {
        guard path.count == 3 else { return false }
        let group = path[1]
        return group == "Strings" || group == "Hashes" || group == "Lists"
    }

    func isStructureEditable(path: [String]) -> Bool {
        false
    }

    func structurePath(for tablePath: [String]) -> [String]? {
        guard tablePath.count == 3 else { return nil }
        return tablePath
    }

    // MARK: - Creation

    private static let typeNames = ["Strings", "Hashes", "Lists", "Sets", "Sorted Sets", "Streams"]

    func creatableChildLabel(path: [String]) -> String? {
        switch path.count {
        case 1: "Key"
        case 2: "Key"
        default: nil
        }
    }

    func createFormFields(path: [String]) -> [CreateField] {
        switch path.count {
        case 1:
            return [
                CreateField(id: "type", label: "Type", defaultValue: "Strings", placeholder: "Strings",
                            options: Self.typeNames),
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:key"),
                CreateField(id: "value", label: "Value", defaultValue: "", placeholder: "value"),
            ]
        case 2:
            return fieldsForType(path[1])
        default:
            return []
        }
    }

    func generateCreateChildSQL(path: [String], values: [String: String]) -> String? {
        let key = values["key", default: ""].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }

        let group: String
        switch path.count {
        case 1: group = values["type", default: "Strings"]
        case 2: group = path[1]
        default: return nil
        }

        return generateCreateCommand(group: group, key: key, values: values)
    }

    // MARK: - Deletion

    func isDeletable(path: [String]) -> Bool {
        path.count == 1 || path.count == 3
    }

    func generateDropSQL(path: [String]) -> String? {
        switch path.count {
        case 1: "FLUSHDB"
        case 3: "DEL \(path[2])"
        default: nil
        }
    }

    // MARK: - Create helpers

    private func fieldsForType(_ group: String) -> [CreateField] {
        switch group {
        case "Strings":
            return [
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:key"),
                CreateField(id: "value", label: "Value", defaultValue: "", placeholder: "value"),
            ]
        case "Hashes":
            return [
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:hash"),
                CreateField(id: "field", label: "Field", defaultValue: "", placeholder: "field"),
                CreateField(id: "value", label: "Value", defaultValue: "", placeholder: "value"),
            ]
        case "Lists":
            return [
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:list"),
                CreateField(id: "value", label: "Value", defaultValue: "", placeholder: "value"),
            ]
        case "Sets":
            return [
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:set"),
                CreateField(id: "member", label: "Member", defaultValue: "", placeholder: "member"),
            ]
        case "Sorted Sets":
            return [
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:zset"),
                CreateField(id: "member", label: "Member", defaultValue: "", placeholder: "member"),
                CreateField(id: "score", label: "Score", defaultValue: "0", placeholder: "0"),
            ]
        case "Streams":
            return [
                CreateField(id: "key", label: "Key", defaultValue: "", placeholder: "my:stream"),
                CreateField(id: "field", label: "Field", defaultValue: "", placeholder: "field"),
                CreateField(id: "value", label: "Value", defaultValue: "", placeholder: "value"),
            ]
        default:
            return []
        }
    }

    private func generateCreateCommand(group: String, key: String, values: [String: String]) -> String? {
        switch group {
        case "Strings":
            let val = values["value", default: ""]
            return "SET \(key) \(val)"
        case "Hashes":
            let field = values["field", default: ""]
            let val = values["value", default: ""]
            return "HSET \(key) \(field) \(val)"
        case "Lists":
            let val = values["value", default: ""]
            return "RPUSH \(key) \(val)"
        case "Sets":
            let member = values["member", default: ""]
            return "SADD \(key) \(member)"
        case "Sorted Sets":
            let member = values["member", default: ""]
            let score = values["score", default: "0"]
            return "ZADD \(key) \(score) \(member)"
        case "Streams":
            let field = values["field", default: ""]
            let val = values["value", default: ""]
            return "XADD \(key) * \(field) \(val)"
        default:
            return nil
        }
    }

    // MARK: - Tree navigation

    func listChildren(path: [String]) async throws -> [HierarchyNode] {
        switch path.count {
        case 0:
            return try await listDatabases()
        case 1:
            return Self.typeGroups.map { group in
                HierarchyNode(name: group.name, icon: "folder", tint: Self.tintGroup, isExpandable: true)
            }
        case 2:
            return try await listKeysForType(path: path)
        case 3:
            return try await listKeyChildren(path: path)
        default:
            return []
        }
    }

    // MARK: - Node details

    func fetchNodeDetails(path: [String]) async throws -> QueryResult {
        guard path.count == 3 else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        let db = Int(path[0]) ?? 0
        let key = path[2]

        let typeResp = try await sendCommand("TYPE", [key], db: db)
        let typeName = typeResp.string ?? "unknown"

        let ttlResp = try await sendCommand("TTL", [key], db: db)
        let ttl = ttlResp.int.map { $0 == -1 ? "none" : $0 == -2 ? "expired" : "\($0)s" } ?? "?"

        var encodingStr = "?"
        if let encResp = try? await sendCommand("OBJECT", ["ENCODING", key], db: db) {
            encodingStr = encResp.string ?? "?"
        }

        var memoryStr = "?"
        if let memResp = try? await sendCommand("MEMORY", ["USAGE", key], db: db) {
            if let bytes = memResp.int {
                memoryStr = formatBytes(bytes)
            }
        }

        var sizeStr = "?"
        switch typeName {
        case "string":
            if let resp = try? await sendCommand("STRLEN", [key], db: db) { sizeStr = "\(resp.int ?? 0) bytes" }
        case "hash":
            if let resp = try? await sendCommand("HLEN", [key], db: db) { sizeStr = "\(resp.int ?? 0) fields" }
        case "list":
            if let resp = try? await sendCommand("LLEN", [key], db: db) { sizeStr = "\(resp.int ?? 0) elements" }
        case "set":
            if let resp = try? await sendCommand("SCARD", [key], db: db) { sizeStr = "\(resp.int ?? 0) members" }
        case "zset":
            if let resp = try? await sendCommand("ZCARD", [key], db: db) { sizeStr = "\(resp.int ?? 0) members" }
        case "stream":
            if let resp = try? await sendCommand("XLEN", [key], db: db) { sizeStr = "\(resp.int ?? 0) entries" }
        default:
            break
        }

        let cols = [
            ColumnInfo(name: "Property", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
        ]
        let rows: [[String?]] = [
            ["Type", typeName],
            ["TTL", ttl],
            ["Encoding", encodingStr],
            ["Memory", memoryStr],
            ["Size", sizeStr],
        ]
        return QueryResult(columns: cols, rows: rows, rowsAffected: nil, totalCount: nil)
    }

    // MARK: - Private helpers

    private func listDatabases() async throws -> [HierarchyNode] {
        let defaultDb = Int(config.database) ?? 0
        let pool = try poolFor(db: defaultDb)

        var dbCount = 16
        if let configResp = try? await pool.send(command: "CONFIG", with: [RESPValue(from: "GET"), RESPValue(from: "databases")]).get(),
           let arr = configResp.array, arr.count == 2,
           let countStr = arr[1].string,
           let count = Int(countStr) {
            dbCount = count
        }

        var nodes: [HierarchyNode] = []
        for i in 0..<dbCount {
            let dbPool = try poolFor(db: i)
            let sizeResp = try await dbPool.send(command: "DBSIZE", with: []).get()
            let size = sizeResp.int ?? 0

            if size > 0 || i == 0 {
                nodes.append(HierarchyNode(
                    name: "\(i)",
                    icon: "cylinder.split.1x2",
                    tint: Self.tintDatabase,
                    isExpandable: true
                ))
            }
        }
        return nodes
    }

    private func listKeysForType(path: [String]) async throws -> [HierarchyNode] {
        let db = Int(path[0]) ?? 0
        let groupName = path[1]
        guard let group = Self.typeGroups.first(where: { $0.name == groupName }) else { return [] }

        let redisType = group.redisType
        var allKeys: [String] = []
        var cursor = "0"
        let maxKeys = 500

        repeat {
            let resp = try await sendCommand("SCAN", [cursor, "TYPE", redisType, "COUNT", "500"], db: db)
            guard let arr = resp.array, arr.count == 2 else { break }
            cursor = arr[0].string ?? "0"
            if let keys = arr[1].array {
                for k in keys {
                    if let name = k.string { allKeys.append(name) }
                }
            }
        } while cursor != "0" && allKeys.count < maxKeys

        allKeys.sort()
        if allKeys.count > maxKeys { allKeys = Array(allKeys.prefix(maxKeys)) }

        let isExpandable = ["hash", "list", "set", "zset", "stream"].contains(redisType)

        return allKeys.map { key in
            HierarchyNode(
                name: key,
                icon: group.icon,
                tint: group.tint,
                isExpandable: isExpandable
            )
        }
    }

    private func listKeyChildren(path: [String]) async throws -> [HierarchyNode] {
        let db = Int(path[0]) ?? 0
        let group = path[1]
        let key = path[2]

        switch group {
        case "Hashes":
            let resp = try await sendCommand("HKEYS", [key], db: db)
            guard let arr = resp.array else { return [] }
            return arr.compactMap { $0.string }.sorted().map { field in
                HierarchyNode(name: field, icon: "number.square", tint: Self.tintHash, isExpandable: false)
            }
        default:
            return []
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
