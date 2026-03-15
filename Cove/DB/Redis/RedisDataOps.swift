import Foundation
import RediStack

extension RedisBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        let db = Int(path[0]) ?? 0

        switch path.count {
        case 2:
            return try await fetchKeyList(path: path, db: db, limit: limit, offset: offset)
        case 3:
            return try await fetchKeyData(path: path, db: db, limit: limit, offset: offset)
        default:
            throw DbError.invalidPath(expected: 2, got: path.count)
        }
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        let db = Int(database) ?? 0
        let parsed = Self.parseRedisCommand(sql)
        guard !parsed.command.isEmpty else {
            throw DbError.query("empty command")
        }

        do {
            let resp = try await sendCommand(parsed.command, parsed.args, db: db)
            return formatCommandResult(resp)
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
        let db = Int(tablePath[0]) ?? 0
        let group = tablePath.count >= 2 ? tablePath[1] : ""
        let newVal = newValue ?? ""

        switch group {
        case "Strings" where tablePath.count == 2:
            let key = primaryKey.first(where: { $0.column == "Key" })?.value ?? ""
            _ = try await sendCommand("SET", [key, newVal], db: db)

        case "Hashes" where tablePath.count == 3:
            let key = tablePath[2]
            let field = primaryKey.first(where: { $0.column == "Field" })?.value ?? ""
            _ = try await sendCommand("HSET", [key, field, newVal], db: db)

        case "Lists" where tablePath.count == 3:
            let key = tablePath[2]
            let index = primaryKey.first(where: { $0.column == "Index" })?.value ?? "0"
            _ = try await sendCommand("LSET", [key, index, newVal], db: db)

        default:
            throw DbError.other("editing not supported for \(group)")
        }
    }

    // MARK: - Key list (path count 2)

    private func fetchKeyList(
        path: [String],
        db: Int,
        limit: UInt32,
        offset: UInt32
    ) async throws -> QueryResult {
        let groupName = path[1]
        guard let group = Self.typeGroups.first(where: { $0.name == groupName }) else {
            throw DbError.other("unknown type group: \(groupName)")
        }

        let redisType = group.redisType
        var allKeys: [String] = []
        var cursor = "0"
        let maxScan = Int(offset) + Int(limit) + 500

        repeat {
            let resp = try await sendCommand("SCAN", [cursor, "TYPE", redisType, "COUNT", "500"], db: db)
            guard let arr = resp.array, arr.count == 2 else { break }
            cursor = arr[0].string ?? "0"
            if let keys = arr[1].array {
                for k in keys {
                    if let name = k.string { allKeys.append(name) }
                }
            }
        } while cursor != "0" && allKeys.count < maxScan

        allKeys.sort()
        let page = Array(allKeys.dropFirst(Int(offset)).prefix(Int(limit)))

        var rows: [[String?]] = []
        for key in page {
            let sizeStr = try await keySize(key: key, type: redisType, db: db)
            let ttlResp = try await sendCommand("TTL", [key], db: db)
            let ttl = ttlResp.int.map { $0 == -1 ? "none" : "\($0)s" } ?? "?"
            rows.append([key, sizeStr, ttl])
        }

        let columns = [
            ColumnInfo(name: "Key", typeName: "text", isPrimaryKey: true),
            ColumnInfo(name: "Value/Size", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "TTL", typeName: "text", isPrimaryKey: false),
        ]

        return QueryResult(
            columns: columns,
            rows: rows,
            rowsAffected: nil,
            totalCount: UInt64(allKeys.count)
        )
    }

    private func keySize(key: String, type: String, db: Int) async throws -> String {
        switch type {
        case "string":
            let resp = try await sendCommand("GET", [key], db: db)
            let val = resp.string ?? ""
            return val.count > 50 ? String(val.prefix(50)) + "..." : val
        case "hash":
            let resp = try await sendCommand("HLEN", [key], db: db)
            return "\(resp.int ?? 0) fields"
        case "list":
            let resp = try await sendCommand("LLEN", [key], db: db)
            return "\(resp.int ?? 0) elements"
        case "set":
            let resp = try await sendCommand("SCARD", [key], db: db)
            return "\(resp.int ?? 0) members"
        case "zset":
            let resp = try await sendCommand("ZCARD", [key], db: db)
            return "\(resp.int ?? 0) members"
        case "stream":
            let resp = try await sendCommand("XLEN", [key], db: db)
            return "\(resp.int ?? 0) entries"
        default:
            return "?"
        }
    }

    // MARK: - Key data (path count 3)

    private func fetchKeyData(
        path: [String],
        db: Int,
        limit: UInt32,
        offset: UInt32
    ) async throws -> QueryResult {
        let group = path[1]
        let key = path[2]

        switch group {
        case "Strings":
            return try await fetchStringData(key: key, db: db)
        case "Hashes":
            return try await fetchHashData(key: key, db: db, limit: limit, offset: offset)
        case "Lists":
            return try await fetchListData(key: key, db: db, limit: limit, offset: offset)
        case "Sets":
            return try await fetchSetData(key: key, db: db, limit: limit, offset: offset)
        case "Sorted Sets":
            return try await fetchZSetData(key: key, db: db, limit: limit, offset: offset)
        case "Streams":
            return try await fetchStreamData(key: key, db: db, limit: limit, offset: offset)
        default:
            throw DbError.other("unknown type group: \(group)")
        }
    }

    private func fetchStringData(key: String, db: Int) async throws -> QueryResult {
        let resp = try await sendCommand("GET", [key], db: db)
        let value = resp.string ?? formatRESPValue(resp)

        let ttlResp = try await sendCommand("TTL", [key], db: db)
        let ttl = ttlResp.int.map { $0 == -1 ? "none" : "\($0)s" } ?? "?"

        let columns = [
            ColumnInfo(name: "Key", typeName: "text", isPrimaryKey: true),
            ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "TTL", typeName: "text", isPrimaryKey: false),
        ]
        return QueryResult(columns: columns, rows: [[key, value, ttl]], rowsAffected: nil, totalCount: 1)
    }

    private func fetchHashData(key: String, db: Int, limit: UInt32, offset: UInt32) async throws -> QueryResult {
        var allPairs: [(String, String)] = []
        var cursor = "0"

        repeat {
            let resp = try await sendCommand("HSCAN", [key, cursor, "COUNT", "500"], db: db)
            guard let arr = resp.array, arr.count == 2 else { break }
            cursor = arr[0].string ?? "0"
            if let entries = arr[1].array {
                var i = 0
                while i + 1 < entries.count {
                    let field = entries[i].string ?? ""
                    let value = entries[i + 1].string ?? ""
                    allPairs.append((field, value))
                    i += 2
                }
            }
        } while cursor != "0"

        allPairs.sort { $0.0 < $1.0 }
        let page = Array(allPairs.dropFirst(Int(offset)).prefix(Int(limit)))

        let columns = [
            ColumnInfo(name: "Field", typeName: "text", isPrimaryKey: true),
            ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
        ]
        let rows = page.map { [$0.0 as String?, $0.1 as String?] }

        return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: UInt64(allPairs.count))
    }

    private func fetchListData(key: String, db: Int, limit: UInt32, offset: UInt32) async throws -> QueryResult {
        let start = Int(offset)
        let end = start + Int(limit) - 1
        let resp = try await sendCommand("LRANGE", [key, String(start), String(end)], db: db)
        let elements = resp.array ?? []

        let lenResp = try await sendCommand("LLEN", [key], db: db)
        let totalCount = UInt64(lenResp.int ?? 0)

        let columns = [
            ColumnInfo(name: "Index", typeName: "int", isPrimaryKey: true),
            ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
        ]
        let rows: [[String?]] = elements.enumerated().map { i, elem in
            [String(start + i), elem.string ?? formatRESPValue(elem)]
        }

        return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: totalCount)
    }

    private func fetchSetData(key: String, db: Int, limit: UInt32, offset: UInt32) async throws -> QueryResult {
        var allMembers: [String] = []
        var cursor = "0"

        repeat {
            let resp = try await sendCommand("SSCAN", [key, cursor, "COUNT", "500"], db: db)
            guard let arr = resp.array, arr.count == 2 else { break }
            cursor = arr[0].string ?? "0"
            if let members = arr[1].array {
                for m in members {
                    if let s = m.string { allMembers.append(s) }
                }
            }
        } while cursor != "0"

        allMembers.sort()
        let page = Array(allMembers.dropFirst(Int(offset)).prefix(Int(limit)))

        let columns = [
            ColumnInfo(name: "Member", typeName: "text", isPrimaryKey: true),
        ]
        let rows = page.map { [$0 as String?] }

        return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: UInt64(allMembers.count))
    }

    private func fetchZSetData(key: String, db: Int, limit: UInt32, offset: UInt32) async throws -> QueryResult {
        var allPairs: [(String, String)] = []
        var cursor = "0"

        repeat {
            let resp = try await sendCommand("ZSCAN", [key, cursor, "COUNT", "500"], db: db)
            guard let arr = resp.array, arr.count == 2 else { break }
            cursor = arr[0].string ?? "0"
            if let entries = arr[1].array {
                var i = 0
                while i + 1 < entries.count {
                    let member = entries[i].string ?? ""
                    let score = entries[i + 1].string ?? "0"
                    allPairs.append((member, score))
                    i += 2
                }
            }
        } while cursor != "0"

        allPairs.sort { $0.0 < $1.0 }
        let page = Array(allPairs.dropFirst(Int(offset)).prefix(Int(limit)))

        let columns = [
            ColumnInfo(name: "Member", typeName: "text", isPrimaryKey: true),
            ColumnInfo(name: "Score", typeName: "text", isPrimaryKey: false),
        ]
        let rows = page.map { [$0.0 as String?, $0.1 as String?] }

        return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: UInt64(allPairs.count))
    }

    private func fetchStreamData(key: String, db: Int, limit: UInt32, offset: UInt32) async throws -> QueryResult {
        // XRANGE returns all entries; we paginate by ID using offset
        let resp = try await sendCommand("XRANGE", [key, "-", "+", "COUNT", String(Int(offset) + Int(limit))], db: db)
        guard let entries = resp.array else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        let lenResp = try await sendCommand("XLEN", [key], db: db)
        let totalCount = UInt64(lenResp.int ?? 0)

        // Collect all field names across entries for dynamic columns
        var fieldOrder: [String] = []
        var fieldSet = Set<String>()
        var parsed: [(id: String, fields: [String: String])] = []

        for entry in entries {
            guard let entryArr = entry.array, entryArr.count == 2 else { continue }
            let id = entryArr[0].string ?? ""
            var fieldMap: [String: String] = [:]
            if let fieldVals = entryArr[1].array {
                var i = 0
                while i + 1 < fieldVals.count {
                    let field = fieldVals[i].string ?? ""
                    let value = fieldVals[i + 1].string ?? ""
                    fieldMap[field] = value
                    if fieldSet.insert(field).inserted {
                        fieldOrder.append(field)
                    }
                    i += 2
                }
            }
            parsed.append((id: id, fields: fieldMap))
        }

        let page = Array(parsed.dropFirst(Int(offset)).prefix(Int(limit)))

        var columns = [ColumnInfo(name: "ID", typeName: "text", isPrimaryKey: true)]
        columns += fieldOrder.map { ColumnInfo(name: $0, typeName: "text", isPrimaryKey: false) }

        let rows: [[String?]] = page.map { entry in
            var row: [String?] = [entry.id]
            for field in fieldOrder {
                row.append(entry.fields[field])
            }
            return row
        }

        return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: totalCount)
    }

    // MARK: - Query result formatting

    private func formatCommandResult(_ resp: RESPValue) -> QueryResult {
        if resp.isNull {
            return QueryResult(columns: [], rows: [], rowsAffected: 0, totalCount: nil)
        }

        if let items = resp.array {
            if items.isEmpty {
                return QueryResult(columns: [], rows: [], rowsAffected: 0, totalCount: nil)
            }

            // Check if it looks like key-value pairs (even count, alternating string keys)
            if items.count >= 2 && items.count % 2 == 0,
               items.enumerated().allSatisfy({ $0.offset % 2 == 1 || $0.element.string != nil }) {
                let cols = [
                    ColumnInfo(name: "Key", typeName: "text", isPrimaryKey: false),
                    ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
                ]
                var rows: [[String?]] = []
                var i = 0
                while i + 1 < items.count {
                    rows.append([items[i].string, formatRESPValue(items[i + 1])])
                    i += 2
                }
                return QueryResult(columns: cols, rows: rows, rowsAffected: nil, totalCount: nil)
            }

            let cols = [ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false)]
            let rows = items.map { [formatRESPValue($0) as String?] }
            return QueryResult(columns: cols, rows: rows, rowsAffected: nil, totalCount: nil)
        }

        if let n = resp.int {
            let cols = [ColumnInfo(name: "Result", typeName: "integer", isPrimaryKey: false)]
            return QueryResult(columns: cols, rows: [[String(n)]], rowsAffected: UInt64(n), totalCount: nil)
        }

        if let err = resp.error {
            let cols = [ColumnInfo(name: "Error", typeName: "text", isPrimaryKey: false)]
            return QueryResult(columns: cols, rows: [[err.message]], rowsAffected: nil, totalCount: nil)
        }

        let str = formatRESPValue(resp)
        let cols = [ColumnInfo(name: "Result", typeName: "text", isPrimaryKey: false)]
        return QueryResult(columns: cols, rows: [[str]], rowsAffected: nil, totalCount: nil)
    }

}
