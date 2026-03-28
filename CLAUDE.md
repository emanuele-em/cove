# Cove

Multi-database GUI client in Swift + SwiftUI for macOS 15+. Supports PostgreSQL, ScyllaDB, Redis, MySQL, MariaDB, MongoDB, SQLite, Elasticsearch, Cassandra, Oracle, SQL Server, ClickHouse, and DuckDB.

## Core Rule

Everything goes through the `DatabaseBackend` protocol. No `if postgres` / `if scylla` in UI code, ever. New backends only add files under `DB/` and a case in `BackendType`. See `DB/README.md` for how to add a backend.

## Code Style

- Idiomatic Swift 6. Structured concurrency, @Observable, modern SwiftUI.
- Keep it simple. No premature abstractions.
- Only comment "why", never "what".
- Use native macOS controls. No custom chrome when SwiftUI provides a standard equivalent.
- Use `throws` and `try`. No force-unwraps.

## Build

```
xcodebuild -scheme Cove -derivedDataPath .build build && open .build/Build/Products/Debug/Cove.app
```
