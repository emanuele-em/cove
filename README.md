# Cove

A native macOS database client. Fast, lightweight, extensible.

Supports **PostgreSQL**, **ScyllaDB**, and **Redis** out of the box. Adding a new database backend requires zero changes to UI code.

> **Early release** — core browsing and editing works, but features like import/export and query tabs are not yet implemented. See [Roadmap](#roadmap).

## Features

- Browse schemas, tables, views, keys in a sidebar tree
- Edit rows inline with SQL/CQL preview before commit
- Run queries with syntax highlighting and autocomplete
- Manage multiple connections with color-coded indicators
- **SSH tunneling** — connect to databases behind firewalls via a jump host (password or private key auth)
- Native macOS UI — no Electron, no web views

## Install

Download the latest `.dmg` from [Releases](https://github.com/user/cove/releases), or build from source:

```
xcodebuild -scheme Cove -derivedDataPath .build build
open .build/Build/Products/Debug/Cove.app
```

Requires macOS 15+.

## Add a database backend

Cove is designed so that a new backend (MySQL, SQLite, MongoDB, ...) can be added by only creating files under `DB/` and a case in `BackendType`. The UI adapts automatically.

See [`DB/README.md`](Cove/DB/README.md) for the step-by-step guide.

## Roadmap

Not yet implemented (contributions welcome):

- Import/export (CSV, JSON, SQL)
- Multiple query tabs
- Data filtering and search
- Query history panel
- SSL/TLS certificate configuration
- Query explain/analyze visualization

## License

[MIT](LICENSE)
