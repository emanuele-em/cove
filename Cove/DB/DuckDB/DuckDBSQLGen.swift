import Foundation

extension DuckDBBackend {

    func generateUpdateSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) -> String {
        guard !isReadOnly else {
            return "-- DuckDB over SSH is read-only for now"
        }

        let fqn = fqnFrom(tablePath)

        let setClause: String
        if let newValue {
            let escaped = newValue.replacingOccurrences(of: "'", with: "''")
            setClause = "\(quoteIdentifier(column)) = '\(escaped)'"
        } else {
            setClause = "\(quoteIdentifier(column)) = NULL"
        }

        return "UPDATE \(fqn) SET \(setClause) WHERE \(whereClause(primaryKey))"
    }

    func generateInsertSQL(
        tablePath: [String],
        columns: [String],
        values: [String?]
    ) -> String {
        guard !isReadOnly else {
            return "-- DuckDB over SSH is read-only for now"
        }

        let fqn = fqnFrom(tablePath)
        let colList = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
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
        guard !isReadOnly else {
            return "-- DuckDB over SSH is read-only for now"
        }
        return "DELETE FROM \(fqnFrom(tablePath)) WHERE \(whereClause(primaryKey))"
    }

    func generateDropElementSQL(path: [String], elementName: String) -> String {
        guard !isReadOnly else {
            return "-- DuckDB over SSH is read-only for now"
        }

        let escaped = elementName.replacingOccurrences(of: "\"", with: "\"\"")
        switch path[4] {
        case "Indexes":
            return "DROP INDEX \(quoteIdentifier(path[0])).\(quoteIdentifier(path[1])).\"\(escaped)\""
        default:
            return "-- unsupported element type: \(path[4])"
        }
    }

    private func fqnFrom(_ tablePath: [String]) -> String {
        guard tablePath.count >= 4 else { return "-- invalid path" }
        return "\(quoteIdentifier(tablePath[0])).\(quoteIdentifier(tablePath[1])).\(quoteIdentifier(tablePath[3]))"
    }

    private func whereClause(_ primaryKey: [(column: String, value: String)]) -> String {
        primaryKey.map { pk in
            let escaped = pk.value.replacingOccurrences(of: "'", with: "''")
            return "\(quoteIdentifier(pk.column)) = '\(escaped)'"
        }.joined(separator: " AND ")
    }
}
