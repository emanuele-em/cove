import Foundation

struct ColumnInfo: Sendable {
    let name: String
    let typeName: String
    let isPrimaryKey: Bool
    let sourceColumnName: String?

    init(name: String, typeName: String, isPrimaryKey: Bool, sourceColumnName: String? = nil) {
        self.name = name
        self.typeName = typeName
        self.isPrimaryKey = isPrimaryKey
        self.sourceColumnName = sourceColumnName
    }

    var updateColumnName: String {
        sourceColumnName ?? name
    }
}

struct QueryResult: Sendable {
    let columns: [ColumnInfo]
    let rows: [[String?]]
    let rowsAffected: UInt64?
    let totalCount: UInt64?
    let editableTablePath: [String]?

    init(
        columns: [ColumnInfo],
        rows: [[String?]],
        rowsAffected: UInt64?,
        totalCount: UInt64?,
        editableTablePath: [String]? = nil
    ) {
        self.columns = columns
        self.rows = rows
        self.rowsAffected = rowsAffected
        self.totalCount = totalCount
        self.editableTablePath = editableTablePath
    }
}

enum SortDirection: Sendable {
    case asc
    case desc
}
