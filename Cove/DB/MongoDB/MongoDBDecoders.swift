import Foundation
@preconcurrency import MongoKitten
import BSON

extension MongoDBBackend {

    // MARK: - BSON to display string

    static func primitiveToString(_ value: Primitive?) -> String? {
        guard let value else { return nil }

        switch value {
        case let str as String:
            return str
        case let int as Int:
            return String(int)
        case let int32 as Int32:
            return String(int32)
        case let double as Double:
            return String(double)
        case let bool as Bool:
            return String(bool)
        case let objectId as ObjectId:
            return objectId.hexString
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let doc as Document:
            return documentToJSON(doc)
        case let binary as Binary:
            return "Binary(\(binary.count) bytes)"
        case is Null:
            return "null"
        default:
            return "\(value)"
        }
    }

    static func documentToJSON(_ doc: Document) -> String {
        var parts: [String] = []
        if doc.isArray {
            for value in doc.values {
                parts.append(primitiveToJSONValue(value))
            }
            return "[\(parts.joined(separator: ", "))]"
        } else {
            for (key, value) in doc {
                parts.append("\"\(key)\": \(primitiveToJSONValue(value))")
            }
            return "{\(parts.joined(separator: ", "))}"
        }
    }

    private static func primitiveToJSONValue(_ value: Primitive) -> String {
        switch value {
        case let str as String:
            return "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
        case let int as Int:
            return String(int)
        case let int32 as Int32:
            return String(int32)
        case let double as Double:
            return String(double)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let objectId as ObjectId:
            return "ObjectId(\"\(objectId.hexString)\")"
        case let date as Date:
            return "ISODate(\"\(ISO8601DateFormatter().string(from: date))\")"
        case let doc as Document:
            return documentToJSON(doc)
        case is Null:
            return "null"
        case let binary as Binary:
            return "BinData(\(binary.count) bytes)"
        default:
            return "\"\(value)\""
        }
    }

    // MARK: - JSON string to BSON Document

    static func parseJSONToDocument(_ json: String) -> Document? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dictionaryToDocument(obj)
    }

    private static func dictionaryToDocument(_ dict: [String: Any]) -> Document {
        var doc = Document()
        for (key, value) in dict {
            doc[key] = anyToPrimitive(value)
        }
        return doc
    }

    private static func anyToPrimitive(_ value: Any) -> Primitive {
        switch value {
        case let str as String:
            return str
        case let num as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return num.boolValue
            }
            if num.doubleValue == Double(num.intValue) && !"\(num)".contains(".") {
                return Int(num.intValue)
            }
            return num.doubleValue
        case let dict as [String: Any]:
            return dictionaryToDocument(dict)
        case let arr as [Any]:
            var arrayDoc = Document(isArray: true)
            for (i, item) in arr.enumerated() {
                arrayDoc["\(i)"] = anyToPrimitive(item)
            }
            return arrayDoc
        case is NSNull:
            return Null()
        default:
            return "\(value)"
        }
    }

    // MARK: - User input to BSON

    static func parseValue(_ string: String) -> Primitive {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        if trimmed == "null" { return Null() }
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }

        if let objectId = try? ObjectId(trimmed) {
            return objectId
        }

        if let intVal = Int(trimmed) {
            return intVal
        }

        if let doubleVal = Double(trimmed), trimmed.contains(".") {
            return doubleVal
        }

        if let doc = parseJSONToDocument(trimmed) {
            return doc
        }

        return trimmed
    }

    static func parseObjectId(_ string: String) -> Primitive {
        if let objectId = try? ObjectId(string) {
            return objectId
        }
        return string
    }

    // MARK: - Command parsing

    struct MongoCommand {
        let collection: String
        let method: String
        let argument: String
    }

    static func parseCommand(_ input: String) -> MongoCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("db.") else { return nil }
        let afterDb = trimmed.dropFirst(3)

        guard let dotIndex = afterDb.firstIndex(of: ".") else { return nil }
        let collection = String(afterDb[afterDb.startIndex..<dotIndex])
        let rest = String(afterDb[afterDb.index(after: dotIndex)...])

        guard let parenStart = rest.firstIndex(of: "("),
              rest.hasSuffix(")") else {
            return MongoCommand(collection: collection, method: rest, argument: "")
        }

        let method = String(rest[rest.startIndex..<parenStart])
        let argStart = rest.index(after: parenStart)
        let argEnd = rest.index(before: rest.endIndex)
        let argument = argStart < argEnd ? String(rest[argStart..<argEnd]) : ""

        return MongoCommand(collection: collection, method: method, argument: argument)
    }

    // MARK: - Document key extraction

    static func extractKeys(from documents: [Document]) -> [String] {
        var keyOrder: [String] = []
        var keySet = Set<String>()

        keyOrder.append("_id")
        keySet.insert("_id")

        for doc in documents {
            for key in doc.keys where keySet.insert(key).inserted {
                keyOrder.append(key)
            }
        }

        return keyOrder
    }
}
