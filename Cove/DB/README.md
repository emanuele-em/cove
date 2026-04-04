# Adding a Database Backend

## Steps

1. Create `DB/YourDB/` folder
2. Add a case to `BackendType` in `ConnectionConfig.swift`:
   - `displayName`, `iconAsset`, `defaultPort`
   - Set backend `capabilities` so the connection dialog can adapt automatically.
   - Use `usesFilePath` for file-backed databases (e.g. SQLite) and `supportsSSH` when the same backend can also connect through SSH.
3. Add the logo to `Assets.xcassets/yourdb-logo.imageset/` (PNG + `Contents.json`)
4. Implement `DatabaseBackend` (see skeleton below)
5. Add factory case in `coveConnect()` in `ConnectionConfig.swift`
6. Add driver dependency via SPM (skip if using a system module like SQLite3)

## File Split Convention

Split into extensions by concern, one file each:

| File | Contents |
|------|----------|
| `YourDBBackend.swift` | Connection management, `connect()`, `deinit`, `quoteIdentifier`, `syntaxKeywords` |
| `YourDBDataOps.swift` | `fetchTableData`, `executeQuery`, `updateCell`, `fetchColumnInfo`, `fetchCompletionSchema` |
| `YourDBHierarchy.swift` | `listChildren`, `fetchNodeDetails`, capability queries, creation/deletion, `NodeTint` constants |
| `YourDBSQLGen.swift` | `generateUpdateSQL`, `generateInsertSQL`, `generateDeleteSQL`, `generateDropElementSQL` |
| `YourDBDecoders.swift` | Type-to-string conversion (only if the driver returns binary/typed data) |

Target ~300 lines per file. All extensions go on the same class.

## SSH Support for File-Based Backends

File-based backends (SQLite, DuckDB) can support SSH by setting `supportsSSH: true` in `BackendCapabilities`.
The shared `RemoteCLIExecution` handles SSH command execution and CSV parsing — backends only need to choose between local and remote in their `connect()`:

```swift
static func connect(config: ConnectionConfig) async throws -> MyDBBackend {
    let execution: any FileBackendExecution
    if let sshConfig = config.sshTunnel {
        execution = try await RemoteCLIExecution.connect(binaryName: "mydb", path: config.database, sshConfig: sshConfig)
    } else {
        execution = try MyDBLocalExecution.connect(path: config.database)
    }
    return MyDBBackend(execution: execution)
}
```

Remote connections are read-only. Guard mutation paths with `isReadOnly` checks in hierarchy, data ops, and SQL gen.

## Thread Safety

Protect mutable connection state. Existing patterns:

- **NSLock** — most backends. Wraps a `[String: Connection]` dict.
- **Mutex\<T\>** — SQLite. Bundles lock with the single `OpaquePointer` it protects.

Mark the class `@unchecked Sendable` in both cases.

## Path Structure

`listChildren(path:)` receives a growing path array. Typical layouts:

**SQL backends** (Postgres, MySQL, MariaDB, SQLite):
```
[] → databases/keyspaces
[db] → groups (Tables, Views, Functions, ...)
[db, group] → items
[db, group, item] → sub-groups (Columns, Indexes, Triggers, ...)
[db, group, item, sub] → leaf details
```

**NoSQL** (Redis, MongoDB): same idea, different semantics (keys, collections, etc.)

Capability queries map to path depth:
- `isDataBrowsable` — typically `path.count == 3` for Tables/Views
- `isEditable` — same depth, Tables only
- `isStructureEditable` — `path.count >= 4`, specific sub-groups (Indexes, Triggers, ...)

## Identifier Quoting

| Style | Backends |
|-------|----------|
| Double-quote `"` | Postgres, ScyllaDB, Cassandra, SQLite, Oracle, DuckDB |
| Bracket `[]` | SQL Server |
| Backtick `` ` `` | MySQL, MariaDB, ClickHouse |
| None | Redis, MongoDB |

## Optional Protocol Methods

Default implementations return `nil`/`false`/`.empty`. Override to enable features:

| Method | Enables |
|--------|---------|
| `creatableChildLabel` / `createFormFields` / `generateCreateChildSQL` | "New..." context menu in sidebar |
| `isDeletable` / `generateDropSQL` | "Delete" context menu in sidebar |
| `structurePath` | Links table view to its column structure node |
| `fetchCompletionSchema` | SQL editor autocomplete |

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

## Reference Implementations

| Backend | Best example for |
|---------|-----------------|
| `Postgres/` | Full-featured SQL backend with schemas, completion, complex type decoders |
| `MySQL/` | Multi-database SQL backend, TLS fallback, backtick quoting |
| `Redis/` | Non-SQL backend, command-based execution, dynamic type discovery |
| `SQLite/` | File-based backend with local/SSH execution via `FileBackendExecution` |
| `MongoDB/` | Document store, shell-style commands, schema inferred from sample data |
| `Oracle/` | Schema-based SQL backend (no per-DB connections), `withConnection` pool pattern, Oracle system views |
| `SQLServer/` | Multi-database + schema SQL backend, bracket quoting, T-SQL system views, `SQLValue` enum decoding |
| `ClickHouse/` | Column-oriented OLAP backend, `ALTER TABLE` mutations for UPDATE/DELETE, columnar→row transpose, ClickHouseNIO `EventLoopFuture` bridging |
| `DuckDB/` | File-based analytical DB with local/SSH execution, C API via `Sources/CDuckDB`, `duckdb_columns()`/`duckdb_constraints()` for introspection |
