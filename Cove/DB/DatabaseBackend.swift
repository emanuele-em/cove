import Foundation

struct CreateField: Sendable, Identifiable {
    let id: String
    let label: String
    let defaultValue: String
    let placeholder: String
    let options: [String]?

    init(id: String, label: String, defaultValue: String, placeholder: String, options: [String]? = nil) {
        self.id = id
        self.label = label
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.options = options
    }
}

protocol DatabaseBackend: Sendable {
    var name: String { get }
    var syntaxKeywords: Set<String> { get }

    func listChildren(path: [String]) async throws -> [HierarchyNode]

    func isDataBrowsable(path: [String]) -> Bool
    func isEditable(path: [String]) -> Bool
    func isStructureEditable(path: [String]) -> Bool

    func fetchTableData(
        path: [String],
        limit: UInt32,
        offset: UInt32,
        sort: (column: String, direction: SortDirection)?
    ) async throws -> QueryResult

    func fetchNodeDetails(path: [String]) async throws -> QueryResult

    func executeQuery(database: String, sql: String) async throws -> QueryResult

    func updateCell(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) async throws

    func generateUpdateSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)],
        column: String,
        newValue: String?
    ) -> String

    func generateInsertSQL(
        tablePath: [String],
        columns: [String],
        values: [String?]
    ) -> String

    func generateDeleteSQL(
        tablePath: [String],
        primaryKey: [(column: String, value: String)]
    ) -> String

    func generateDropElementSQL(path: [String], elementName: String) -> String

    func creatableChildLabel(path: [String]) -> String?
    func createFormFields(path: [String]) -> [CreateField]
    func generateCreateChildSQL(path: [String], values: [String: String]) -> String?

    func isDeletable(path: [String]) -> Bool
    func generateDropSQL(path: [String]) -> String?

    func structurePath(for tablePath: [String]) -> [String]?

    func fetchCompletionSchema(database: String) async throws -> CompletionSchema
}

extension DatabaseBackend {
    func creatableChildLabel(path: [String]) -> String? { nil }
    func createFormFields(path: [String]) -> [CreateField] { [] }
    func generateCreateChildSQL(path: [String], values: [String: String]) -> String? { nil }
    func isDeletable(path: [String]) -> Bool { false }
    func generateDropSQL(path: [String]) -> String? { nil }
    func structurePath(for tablePath: [String]) -> [String]? { tablePath + ["Columns"] }
    func fetchCompletionSchema(database: String) async throws -> CompletionSchema { .empty }

    // Use this instead of error.localizedDescription — NIO and driver errors implement
    // CustomStringConvertible with human-readable output, which localizedDescription loses.
    static func errorMessage(_ error: any Error) -> String { String(describing: error) }
}
