# Changelog

<!--
  Contributors: add a bullet point describing your change under [Unreleased].
  You don't need to add a PR reference or your name — CI does that automatically.
-->

## [Unreleased]

## [0.2.0] - 2026-05-02

- Local agent mode for queries with Claude Code and Codex CLI support
- Review query result edits before saving
- Keep database error details visible in the editor
- Wire database dependencies for local Xcode builds
- Ignore Swift profiling output
- Refresh the README demo

## [0.1.3] - 2026-04-04

- Fix DuckDB column info query to use `duckdb_columns()` instead of `information_schema` ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- Show a per-backend notice in the connection dialog; DuckDB explains the brew install requirement ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- SQLite over SSH — browse and query remote SQLite files via SSH exec channels ([#2](https://github.com/emanuele-em/cove/pull/2) by [@eznix86](https://github.com/eznix86))
- DuckDB over SSH — same remote CLI execution pattern as SQLite ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- Shared `FileBackendExecution` abstraction for file-based backend SSH support ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- Extracted SSH connection primitives into shared `SSHSupport` module ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- Replaced `isFileBased` boolean with `BackendCapabilities` struct ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- Mitmproxy-style changelog workflow with automatic PR attribution ([#7](https://github.com/emanuele-em/cove/pull/7) by @emanuele-em)
- Fix connection rail tooltip to use native macOS system tooltip

## [0.1.2] - 2026-03-29

- Oracle backend with schema-based navigation and connection pool pattern
- SQL Server backend with multi-database + schema support
- DuckDB backend (file-based analytical DB, C API)
- ClickHouse backend with column-oriented OLAP support
- Fix reconnect when editing active connection config
- Fix show all databases when no database specified in SQL Server
- Add CDuckDB search paths to CoveTests build settings
- Bump actions/checkout to v5

## [0.1.1] - 2026-03-24

- Resolve localhost to 127.0.0.1 for IPv4-only database servers

## [0.1.0] - 2026-03-20

- PostgreSQL backend with full schema browsing, TLS support, and type decoders
- MySQL backend with multi-database support and TLS fallback
- MariaDB backend
- SQLite backend (file-based, no external dependency)
- MongoDB backend with shell-style commands and document schema inference
- Redis backend with command-based execution and dynamic type discovery
- ScyllaDB backend (CQL)
- Cassandra backend (CQL)
- Elasticsearch backend with REST-style query execution
- Sidebar tree for browsing databases, schemas, tables, views, indexes, and keys
- Inline row editing with SQL/CQL preview before commit
- Query editor with syntax highlighting for keywords, strings, numbers, and comments
- SQL/CQL autocomplete engine with schema-aware completions
- Multiple tabs with independent connections (Cmd+T)
- Connection environments (local, dev, staging, production)
- SSH tunneling with password and private key authentication
- Session persistence and restore across app relaunches
- Encrypted credential storage via macOS Keychain
- Color-coded connection indicators
- Context menu actions for creating and dropping database objects
- Data pagination with sorting
- Table structure tab showing columns, indexes, and triggers
- GitHub Actions CI (build + test on macOS 15)
- GitHub Actions release workflow (DMG + ZIP on tag push)
