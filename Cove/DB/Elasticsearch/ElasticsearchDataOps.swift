import Foundation

extension ElasticsearchBackend {

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult {
        guard path.count == 1 else {
            throw DbError.invalidPath(expected: 1, got: path.count)
        }

        let indexName = path[0]

        var searchBody: [String: Any] = [
            "from": Int(offset),
            "size": Int(limit),
            "track_total_hits": true,
        ]

        if let sort {
            let direction = sort.direction == .asc ? "asc" : "desc"
            if sort.column == "_id" {
                searchBody["sort"] = [["_id": ["order": direction]]]
            } else {
                searchBody["sort"] = [[sort.column: ["order": direction, "unmapped_type": "keyword"]]]
            }
        }

        let result = try await request(method: "POST", path: "/\(indexName)/_search", body: searchBody)

        guard let dict = result as? [String: Any],
              let hits = dict["hits"] as? [String: Any],
              let hitArray = hits["hits"] as? [[String: Any]] else {
            return QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
        }

        let totalCount: UInt64
        if let total = hits["total"] as? [String: Any],
           let value = total["value"] as? Int {
            totalCount = UInt64(value)
        } else if let total = hits["total"] as? Int {
            totalCount = UInt64(total)
        } else {
            totalCount = 0
        }

        guard !hitArray.isEmpty else {
            return QueryResult(
                columns: [ColumnInfo(name: "_id", typeName: "keyword", isPrimaryKey: true)],
                rows: [],
                rowsAffected: nil,
                totalCount: totalCount
            )
        }

        // Extract column names from union of all _source keys
        let keys = extractKeys(from: hitArray)
        let columns = keys.map { key in
            ColumnInfo(
                name: key,
                typeName: key == "_id" ? "keyword" : "auto",
                isPrimaryKey: key == "_id"
            )
        }

        // Fetch mapping for type info
        let mappingTypes = try? await fetchMappingTypes(index: indexName)

        let rows: [[String?]] = hitArray.map { hit in
            let id = hit["_id"] as? String
            let source = hit["_source"] as? [String: Any] ?? [:]
            return keys.map { key in
                if key == "_id" { return id }
                guard let val = source[key] else { return nil }
                return valueToString(val)
            }
        }

        // Update column types from mapping if available
        let typedColumns: [ColumnInfo]
        if let mappingTypes {
            typedColumns = keys.map { key in
                ColumnInfo(
                    name: key,
                    typeName: key == "_id" ? "keyword" : (mappingTypes[key] ?? "auto"),
                    isPrimaryKey: key == "_id"
                )
            }
        } else {
            typedColumns = columns
        }

        return QueryResult(
            columns: typedColumns,
            rows: rows,
            rowsAffected: nil,
            totalCount: totalCount
        )
    }

    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)

        let (method, path, body) = parseRESTCommand(trimmed, defaultIndex: database)

        let result = try await request(method: method, path: path, body: body)

        return formatResponse(result, path: path)
    }

    func updateCell(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) async throws {
        guard tablePath.count == 1 else {
            throw DbError.invalidPath(expected: 1, got: tablePath.count)
        }

        let indexName = tablePath[0]

        guard let docId = primaryKey.first(where: { $0.column == "_id" })?.value else {
            throw DbError.other("missing _id in primary key")
        }

        let parsedValue: Any = newValue.map { parseNewValue($0) } ?? NSNull()

        let updateBody: [String: Any] = [
            "doc": [column: parsedValue],
        ]

        _ = try await request(method: "POST", path: "/\(indexName)/_update/\(docId)", body: updateBody)
    }

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema {
        guard !database.isEmpty else { return .empty }

        let mappingTypes = try? await fetchMappingTypes(index: database)
        guard let mappingTypes, !mappingTypes.isEmpty else { return .empty }

        let columns = mappingTypes.map { CompletionColumn(name: $0.key, typeName: $0.value) }
        let table = CompletionTable(name: database, columns: columns.sorted { $0.name < $1.name })

        return CompletionSchema(
            schemas: [],
            tables: [database: [table]],
            functions: [],
            types: []
        )
    }

    // MARK: - Private helpers

    private func extractKeys(from hits: [[String: Any]]) -> [String] {
        var keyOrder: [String] = ["_id"]
        var keySet: Set<String> = ["_id"]

        for hit in hits {
            guard let source = hit["_source"] as? [String: Any] else { continue }
            for key in source.keys.sorted() where keySet.insert(key).inserted {
                keyOrder.append(key)
            }
        }

        return keyOrder
    }

    private func valueToString(_ value: Any) -> String? {
        switch value {
        case is NSNull:
            return nil
        case let str as String:
            return str
        case let num as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        case let dict as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "\(dict)"
        case let arr as [Any]:
            if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "\(arr)"
        default:
            return "\(value)"
        }
    }

    private func fetchMappingTypes(index: String) async throws -> [String: String] {
        let result = try await getJSON(path: "/\(index)/_mapping")

        guard let indexData = result[index] as? [String: Any],
              let mappings = indexData["mappings"] as? [String: Any],
              let properties = mappings["properties"] as? [String: Any] else {
            return [:]
        }

        var types: [String: String] = [:]
        for (key, val) in properties {
            if let fieldInfo = val as? [String: Any],
               let type = fieldInfo["type"] as? String {
                types[key] = type
            }
        }
        return types
    }

    private func parseRESTCommand(_ input: String, defaultIndex: String) -> (method: String, path: String, body: Any?) {
        let lines = input.components(separatedBy: "\n")
        let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let bodyLines = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let knownMethods = ["GET", "POST", "PUT", "DELETE", "HEAD", "PATCH"]
        let parts = firstLine.split(separator: " ", maxSplits: 1)

        let method: String
        let path: String
        let bodyStr: String

        if parts.count == 2, knownMethods.contains(String(parts[0]).uppercased()) {
            method = String(parts[0]).uppercased()
            path = String(parts[1])
            bodyStr = bodyLines
        } else if firstLine.hasPrefix("/") {
            // Just a path, no method
            method = bodyLines.isEmpty ? "GET" : "POST"
            path = firstLine
            bodyStr = bodyLines
        } else {
            // Assume it's a JSON body for search on the default index
            method = "POST"
            let idx = defaultIndex.isEmpty ? "_all" : defaultIndex
            path = "/\(idx)/_search"
            bodyStr = input
        }

        var body: Any?
        if !bodyStr.isEmpty, let data = bodyStr.data(using: .utf8) {
            body = try? JSONSerialization.jsonObject(with: data)
        }

        return (method, path, body)
    }

    private func formatResponse(_ result: Any, path: String) -> QueryResult {
        guard let dict = result as? [String: Any] else {
            let cols = [ColumnInfo(name: "Result", typeName: "text", isPrimaryKey: false)]
            return QueryResult(columns: cols, rows: [["\(result)"]], rowsAffected: nil, totalCount: nil)
        }

        // _search response
        if let hits = dict["hits"] as? [String: Any],
           let hitArray = hits["hits"] as? [[String: Any]] {
            let keys = extractKeys(from: hitArray)
            let columns = keys.map {
                ColumnInfo(name: $0, typeName: "auto", isPrimaryKey: $0 == "_id")
            }
            let rows: [[String?]] = hitArray.map { hit in
                let id = hit["_id"] as? String
                let source = hit["_source"] as? [String: Any] ?? [:]
                return keys.map { key in
                    if key == "_id" { return id }
                    guard let val = source[key] else { return nil }
                    return valueToString(val)
                }
            }

            let totalCount: UInt64?
            if let total = hits["total"] as? [String: Any], let v = total["value"] as? Int {
                totalCount = UInt64(v)
            } else if let total = hits["total"] as? Int {
                totalCount = UInt64(total)
            } else {
                totalCount = nil
            }

            return QueryResult(columns: columns, rows: rows, rowsAffected: nil, totalCount: totalCount)
        }

        // _count response
        if let count = dict["count"] as? Int {
            let cols = [ColumnInfo(name: "count", typeName: "integer", isPrimaryKey: false)]
            return QueryResult(columns: cols, rows: [[String(count)]], rowsAffected: nil, totalCount: nil)
        }

        // CRUD response (index, update, delete single doc)
        if let docResult = dict["result"] as? String {
            var rows: [[String?]] = [["result", docResult]]
            if let id = dict["_id"] as? String { rows.append(["_id", id]) }
            if let index = dict["_index"] as? String { rows.append(["_index", index]) }
            if let version = dict["_version"] as? Int { rows.append(["_version", String(version)]) }
            let cols = [
                ColumnInfo(name: "Property", typeName: "text", isPrimaryKey: false),
                ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
            ]
            return QueryResult(columns: cols, rows: rows, rowsAffected: 1, totalCount: nil)
        }

        // acknowledged response (create/delete index)
        if let ack = dict["acknowledged"] as? Bool {
            let cols = [ColumnInfo(name: "Result", typeName: "text", isPrimaryKey: false)]
            return QueryResult(columns: cols, rows: [[ack ? "acknowledged" : "not acknowledged"]], rowsAffected: nil, totalCount: nil)
        }

        // Generic: show as key-value pairs
        let cols = [
            ColumnInfo(name: "Property", typeName: "text", isPrimaryKey: false),
            ColumnInfo(name: "Value", typeName: "text", isPrimaryKey: false),
        ]
        let rows: [[String?]] = dict.sorted { $0.key < $1.key }.map { key, val in
            [key, valueToString(val)]
        }
        return QueryResult(columns: cols, rows: rows, rowsAffected: nil, totalCount: nil)
    }

    private func parseNewValue(_ string: String) -> Any {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        if trimmed == "null" { return NSNull() }
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }

        if let intVal = Int(trimmed) { return intVal }
        if let doubleVal = Double(trimmed), trimmed.contains(".") { return doubleVal }

        // Try JSON object/array
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            return parsed
        }

        return trimmed
    }
}
