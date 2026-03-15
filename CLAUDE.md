# Cove — Development Guidelines

## What is Cove

Cove is a multi-database GUI client written in Swift + SwiftUI for macOS 15+. It currently supports PostgreSQL and ScyllaDB, and is designed so that adding a new database backend requires **zero changes to UI code**.

## Contribution-first architecture

Every feature must work through the `DatabaseBackend` protocol. The UI never checks which backend is active — it asks the protocol what's possible and renders accordingly. When adding or modifying a feature:

1. **Define capability in the protocol** — add a method to `DatabaseBackend` with a default no-op in the extension so existing backends keep compiling.
2. **Implement per backend** — each backend opts in by overriding the default. All backend-specific logic stays inside its `DB/<Backend>/` subdirectory.
3. **UI stays generic** — views call protocol methods and adapt. No `if postgres` / `if scylla` in UI code, ever.

This means a new contributor can add an entire database backend (MySQL, Redis, MongoDB, SQLite, etc.) by only adding files under `DB/` and a case in `BackendType` — nothing else needs to change.

## Code Style
- Idiomatic Swift 6. Structured concurrency, @Observable, modern SwiftUI APIs.
- Keep it simple. No premature abstractions, no unnecessary generics.
- Only add code that is needed right now.

## Structure
- One concern per file. Split files beyond ~300 lines.
- Organize by feature, not by layer.
- Only comment "why", never "what".

## Architecture

```
Cove/
  CoveApp.swift
  DB/
    DatabaseBackend.swift      — protocol + CreateField type
    ConnectionConfig.swift     — BackendType enum, ConnectionConfig, coveConnect()
    HierarchyNode.swift        — tree node types (HierarchyNode, NodeTint)
    QueryResult.swift          — query result types
    DbError.swift              — error types
    README.md                  — step-by-step guide for adding backends
    Postgres/                  — everything PostgreSQL-specific
      PostgresBackend.swift    — class definition, connection pool
      PostgresHierarchy.swift  — tree navigation, node details, create/drop
      PostgresDataOps.swift    — data fetching, query execution
      PostgresSQLGen.swift     — SQL generation (UPDATE/INSERT/DELETE/DROP)
      PostgresDecoders.swift   — binary wire format decoders
    ScyllaDB/                  — everything ScyllaDB-specific
      ScyllaBackend.swift      — class definition, connection
      ScyllaHierarchy.swift    — tree navigation, node details, create/drop
      ScyllaDataOps.swift      — data fetching, query execution
      ScyllaCQLGen.swift       — CQL generation
      ScyllaDecoders.swift     — binary wire format decoders
  Views/                       — all SwiftUI views
  State/                       — @Observable state classes
  Store/                       — JSON persistence
  Theme/                       — color palette constants
```

## DB/ protocol design

The `DatabaseBackend` protocol has three tiers of methods:

**Required** — every backend must implement these:
- `listChildren(path:)`, `isDataBrowsable(path:)`, `isEditable(path:)`, `isStructureEditable(path:)`
- `fetchTableData(...)`, `fetchNodeDetails(...)`, `executeQuery(...)`
- `updateCell(...)`, `generateUpdateSQL(...)`, `generateInsertSQL(...)`, `generateDeleteSQL(...)`, `generateDropElementSQL(...)`

**Opt-in with defaults** — override to enable sidebar create/drop:
- `creatableChildLabel(path:)` → return a label like `"Table"` to enable right-click "New Table..." on that node (default: `nil`, menu hidden)
- `createFormFields(path:)` → return `[CreateField]` describing the form. Use `options:` array for dropdowns, omit for text fields (default: `[]`)
- `generateCreateChildSQL(path:values:)` → build CREATE SQL from filled-in form values (default: `nil`)
- `isDeletable(path:)` → return `true` to enable "Drop ..." context menu (default: `false`)
- `generateDropSQL(path:)` → build the DROP statement (default: `nil`)

**Adding a new backend:** see `DB/README.md` for the full step-by-step guide with a minimal skeleton.

## UI Style
- Always use native macOS controls and materials. No custom-drawn buttons, backgrounds, or chrome when SwiftUI provides a standard equivalent.
- Use system button styles (`.bordered`, `.borderless`, `.borderedProminent`), native `Picker` with `.segmented`, and standard materials (`.bar`, `.ultraThinMaterial`) instead of custom colors/shapes.
- Prefer `.secondary` / `.primary` foreground styles over theme-specific colors for standard UI elements.
- Never implement custom gestures (e.g. `DragGesture`) for behaviors that SwiftUI or AppKit already provide. Use `HSplitView`/`VSplitView` for resizable panes, `NavigationSplitView` for navigation columns, native `List` for selection, etc.

## Error Handling
- Use `throws` and `try`. No force-unwraps in production code.
- String-based errors are fine when only displayed to the user.
- Only validate at system boundaries (user input, database responses).

## Dependencies
- Minimal. Every new package must justify its existence.
- Prefer Foundation/SwiftUI when good enough.

## Build & Run

```
xcodebuild -scheme Cove -derivedDataPath .build build && open .build/Build/Products/Debug/Cove.app
```

Or open `Cove.xcodeproj` in Xcode and build (Cmd+B).

## Tech Stack
- Swift 6 + SwiftUI (macOS 15+)
- PostgresNIO (PostgreSQL driver)
- CassandraClient (ScyllaDB driver)
- SF Symbols (icons)
- @Observable (state management)
- JSON + Codable (persistence)
