import Foundation

struct ColumnInfo: Sendable {
    let name: String
    let typeName: String
    let isPrimaryKey: Bool
}

struct QueryResult: Sendable {
    let columns: [ColumnInfo]
    let rows: [[String?]]
    let rowsAffected: UInt64?
    let totalCount: UInt64?
}

enum SortDirection: Sendable {
    case asc
    case desc
}
