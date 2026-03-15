import Foundation

extension PostgresBackend {

    func generateUpdateSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) -> String {
        let fqn = fqnFrom(tablePath)

        let setClause: String
        if let newValue {
            let escaped = newValue.replacingOccurrences(of: "'", with: "''")
            setClause = "\"\(column)\" = '\(escaped)'"
        } else {
            setClause = "\"\(column)\" = NULL"
        }

        return "UPDATE \(fqn) SET \(setClause) WHERE \(whereClause(primaryKey))"
    }

    func generateInsertSQL(
        tablePath: [String],
        columns: [String],
        values: [String?]
    ) -> String {
        let fqn = fqnFrom(tablePath)
        let colList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let valList = values.map { val -> String in
            guard let val else { return "NULL" }
            let escaped = val.replacingOccurrences(of: "'", with: "''")
            return "'\(escaped)'"
        }.joined(separator: ", ")
        return "INSERT INTO \(fqn) (\(colList)) VALUES (\(valList))"
    }

    func generateDeleteSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)]
    ) -> String {
        return "DELETE FROM \(fqnFrom(tablePath)) WHERE \(whereClause(primaryKey))"
    }

    func generateDropElementSQL(path: [String], elementName: String) -> String {
        let schema = path[1]
        let table = path[3]
        let escaped = elementName.replacingOccurrences(of: "\"", with: "\"\"")
        switch path[4] {
        case "Indexes":
            return "DROP INDEX \"\(schema)\".\"\(escaped)\""
        case "Constraints":
            return "ALTER TABLE \"\(schema)\".\"\(table)\" DROP CONSTRAINT \"\(escaped)\""
        case "Triggers":
            return "DROP TRIGGER \"\(escaped)\" ON \"\(schema)\".\"\(table)\""
        default:
            return "-- unsupported element type: \(path[4])"
        }
    }

    // MARK: - Private helpers

    private func fqnFrom(_ tablePath: [String]) -> String {
        precondition(tablePath.count >= 4, "tablePath must have at least 4 elements")
        return "\"\(tablePath[1])\".\"\(tablePath[3])\""
    }

    private func whereClause(_ primaryKey: [(column: String, value: String)]) -> String {
        primaryKey.map { pk in
            let escaped = pk.value.replacingOccurrences(of: "'", with: "''")
            return "\"\(pk.column)\" = '\(escaped)'"
        }.joined(separator: " AND ")
    }
}
