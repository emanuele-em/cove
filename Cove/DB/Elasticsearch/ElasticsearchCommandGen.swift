import Foundation

extension ElasticsearchBackend {

    func generateUpdateSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) -> String {
        guard tablePath.count >= 1 else { return "// invalid path" }
        let index = tablePath[0]
        let docId = primaryKey.first(where: { $0.column == "_id" })?.value ?? ""
        let val = formatValue(newValue)

        return "POST /\(index)/_update/\(docId)\n{\"doc\": {\"\(column)\": \(val)}}"
    }

    func generateInsertSQL(
        tablePath: [String],
        columns: [String],
        values: [String?]
    ) -> String {
        guard tablePath.count >= 1 else { return "// invalid path" }
        let index = tablePath[0]

        var fields: [String] = []
        for (col, val) in zip(columns, values) where col != "_id" {
            fields.append("\"\(col)\": \(formatValue(val))")
        }

        return "POST /\(index)/_doc\n{\(fields.joined(separator: ", "))}"
    }

    func generateDeleteSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)]
    ) -> String {
        guard tablePath.count >= 1 else { return "// invalid path" }
        let index = tablePath[0]
        let docId = primaryKey.first(where: { $0.column == "_id" })?.value ?? ""

        return "DELETE /\(index)/_doc/\(docId)"
    }

    func generateDropElementSQL(path: [String], elementName: String) -> String {
        guard path.count >= 1 else { return "// invalid path" }
        return "DELETE /\(path[0])"
    }

    // MARK: - Formatting helpers

    private func formatValue(_ value: String?) -> String {
        guard let value else { return "null" }
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed == "null" || trimmed == "true" || trimmed == "false" {
            return trimmed
        }
        if Int(trimmed) != nil || Double(trimmed) != nil {
            return trimmed
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }

        return "\"\(trimmed.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
