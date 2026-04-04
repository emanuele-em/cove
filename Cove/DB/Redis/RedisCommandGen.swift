import Foundation

extension RedisBackend {

    func generateUpdateSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) -> String {
        guard tablePath.count >= 2 else { return "-- invalid path" }
        let group = tablePath[1]
        let newVal = newValue ?? ""

        switch group {
        case "Strings":
            let key = primaryKey.first(where: { $0.column == "Key" })?.value ?? ""
            return "SET \(key) \(newVal)"

        case "Hashes":
            if tablePath.count == 3 {
                let key = tablePath[2]
                let field = primaryKey.first(where: { $0.column == "Field" })?.value ?? ""
                return "HSET \(key) \(field) \(newVal)"
            }
            let key = primaryKey.first(where: { $0.column == "Key" })?.value ?? ""
            return "SET \(key) \(newVal)"

        case "Lists":
            if tablePath.count == 3 {
                let key = tablePath[2]
                let index = primaryKey.first(where: { $0.column == "Index" })?.value ?? "0"
                return "LSET \(key) \(index) \(newVal)"
            }
            return "-- unsupported"

        default:
            return "-- unsupported update for \(group)"
        }
    }

    func generateInsertSQL(
        tablePath: [String],
        columns: [String],
        values: [String?]
    ) -> String {
        guard tablePath.count >= 2 else { return "-- invalid path" }
        let group = tablePath[1]
        let valueMap = Dictionary(uniqueKeysWithValues: zip(columns, values))

        switch group {
        case "Strings":
            let key = valueMap["Key"] ?? ""
            let val = valueMap["Value"] ?? ""
            return "SET \(key ?? "") \(val ?? "")"

        case "Hashes":
            if tablePath.count == 3 {
                let key = tablePath[2]
                let field = valueMap["Field"] ?? ""
                let val = valueMap["Value"] ?? ""
                return "HSET \(key) \(field ?? "") \(val ?? "")"
            }
            return "-- unsupported"

        case "Lists":
            if tablePath.count == 3 {
                let key = tablePath[2]
                let val = valueMap["Value"] ?? ""
                return "RPUSH \(key) \(val ?? "")"
            }
            return "-- unsupported"

        case "Sets":
            if tablePath.count == 3 {
                let key = tablePath[2]
                let member = valueMap["Member"] ?? ""
                return "SADD \(key) \(member ?? "")"
            }
            return "-- unsupported"

        case "Sorted Sets":
            if tablePath.count == 3 {
                let key = tablePath[2]
                let member = valueMap["Member"] ?? ""
                let score = valueMap["Score"] ?? ""
                return "ZADD \(key) \(score ?? "0") \(member ?? "")"
            }
            return "-- unsupported"

        case "Streams":
            if tablePath.count == 3 {
                let key = tablePath[2]
                var fields: [String] = []
                for (col, val) in zip(columns, values) where col != "ID" {
                    fields.append(col)
                    fields.append(val ?? "")
                }
                return "XADD \(key) * \(fields.joined(separator: " "))"
            }
            return "-- unsupported"

        default:
            return "-- unsupported insert for \(group)"
        }
    }

    func generateDeleteSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)]
    ) -> String {
        guard tablePath.count >= 2 else { return "-- invalid path" }
        let group = tablePath[1]

        if tablePath.count == 2 {
            let key = primaryKey.first(where: { $0.column == "Key" })?.value ?? ""
            return "DEL \(key)"
        }

        let key = tablePath[2]
        switch group {
        case "Strings":
            return "DEL \(key)"
        case "Hashes":
            let field = primaryKey.first(where: { $0.column == "Field" })?.value ?? ""
            return "HDEL \(key) \(field)"
        case "Lists":
            let val = primaryKey.first(where: { $0.column == "Value" })?.value ?? ""
            return "LREM \(key) 1 \(val)"
        case "Sets":
            let member = primaryKey.first(where: { $0.column == "Member" })?.value ?? ""
            return "SREM \(key) \(member)"
        case "Sorted Sets":
            let member = primaryKey.first(where: { $0.column == "Member" })?.value ?? ""
            return "ZREM \(key) \(member)"
        case "Streams":
            let id = primaryKey.first(where: { $0.column == "ID" })?.value ?? ""
            return "XDEL \(key) \(id)"
        default:
            return "-- unsupported delete for \(group)"
        }
    }

    func generateDropElementSQL(path: [String], elementName: String) -> String {
        "DEL \(elementName)"
    }
}
