# Adding a Database Backend

## Steps

1. Create `DB/YourDB/` folder
2. Add a case to `BackendType` in `ConnectionConfig.swift` (`displayName`, `iconAsset`, `defaultPort`)
3. Add the logo to `Assets.xcassets/`
4. Implement `DatabaseBackend` (see skeleton below)
5. Add factory case in `coveConnect()` in `ConnectionConfig.swift`
6. Add driver dependency via SPM

## Skeleton

```swift
final class MyDBBackend: DatabaseBackend, @unchecked Sendable {
    let name = "MyDB"
    let syntaxKeywords: Set<String> = []  // empty for non-SQL backends

    static func connect(config: ConnectionConfig) async throws -> MyDBBackend {
        fatalError("TODO")
    }

    // Capability queries
    func isDataBrowsable(path: [String]) -> Bool { false }
    func isEditable(path: [String]) -> Bool { false }
    func isStructureEditable(path: [String]) -> Bool { false }

    // Tree — path is [] for root, grows deeper per level
    func listChildren(path: [String]) async throws -> [HierarchyNode] { [] }

    // Data
    func fetchTableData(path: [String], limit: UInt32, offset: UInt32,
                        sort: (column: String, direction: SortDirection)?) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
    }
    func fetchNodeDetails(path: [String]) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
    }
    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
    }

    // Editing
    func updateCell(tablePath: [String], primaryKey: [(column: String, value: String)],
                    column: String, newValue: String?) async throws {}
    func generateUpdateSQL(tablePath: [String], primaryKey: [(column: String, value: String)],
                           column: String, newValue: String?) -> String { "" }
    func generateInsertSQL(tablePath: [String], columns: [String], values: [String?]) -> String { "" }
    func generateDeleteSQL(tablePath: [String], primaryKey: [(column: String, value: String)]) -> String { "" }
    func generateDropElementSQL(path: [String], elementName: String) -> String { "" }

    // Optional: override creatableChildLabel, createFormFields, generateCreateChildSQL,
    // isDeletable, generateDropSQL to enable sidebar create/drop menus.
}
```

## Notes

- Split files at ~300 lines using `extension MyDBBackend` in separate files
- `executeQuery` accepts any command string, not just SQL
- Look at `DB/Postgres/` or `DB/Redis/` for real examples
