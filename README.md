# Cove

[![Build](https://github.com/emanuele-em/cove/actions/workflows/build.yml/badge.svg)](https://github.com/emanuele-em/cove/actions/workflows/build.yml)
[![Download](https://img.shields.io/github/v/release/emanuele-em/cove?label=Download&style=flat)](https://github.com/emanuele-em/cove/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000.svg?logo=apple)](https://developer.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg?logo=swift&logoColor=white)](https://swift.org)

A native macOS database client. Fast, lightweight, extensible.

![Cove demo](docs/hero.gif)

### Supported databases

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/postgres-logo.imageset/postgres-logo.png" width="40"><br><b>PostgreSQL</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/mysql-logo.imageset/mysql-logo.png" width="40"><br><b>MySQL</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/mariadb-logo.imageset/mariadb-logo.png" width="40"><br><b>MariaDB</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/sqlite-logo.imageset/sqlite-logo.png" width="40"><br><b>SQLite</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/mongodb-logo.imageset/mongodb-logo.png" width="40"><br><b>MongoDB</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/redis-logo.imageset/redis-logo.png" width="40"><br><b>Redis</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/scylladb-logo.imageset/scylladb-logo.png" width="40"><br><b>ScyllaDB</b></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/cassandra-logo.imageset/cassandra-logo.png" width="40"><br><b>Cassandra</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/elasticsearch-logo.imageset/elasticsearch-logo.png" width="40"><br><b>Elasticsearch</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/oracle-logo.imageset/oracle-logo.png" width="40"><br><b>Oracle</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/sqlserver-logo.imageset/sqlserver-logo.png" width="40"><br><b>SQL Server</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/clickhouse-logo.imageset/clickhouse-logo.png" width="40"><br><b>ClickHouse</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/duckdb-logo.imageset/duckdb-logo.png" width="40"><br><b>DuckDB</b></td>
  </tr>
</table>

Adding a new backend requires zero changes to UI code — see [`DB/README.md`](Cove/DB/README.md).

## Features

- **Browse** schemas, tables, views, indexes, and keys in a sidebar tree
- **Edit rows** inline with SQL/CQL preview before commit
- **Run queries** with syntax highlighting and autocomplete
- **Agent Mode** — generate or edit queries with Claude Code or Codex CLI
- **Multiple tabs** with independent connections (Cmd+T)
- **Connection environments** — local, dev, staging, production
- **SSH tunneling** — password or private key authentication
- **SQLite over SSH** — browse and query a VPS-hosted SQLite file from the same SQLite connection flow
- **Session persistence** — connections and tabs restore across app relaunches
- **Color-coded indicators** and connection tooltips
- Native macOS UI — no Electron, no web views

## Agent Mode

Agent Mode can create a new query or edit the current query block using a local agent CLI.

<img width="1068" height="316" alt="image" src="https://github.com/user-attachments/assets/eb78ed0f-c6ee-4293-888c-78f7c55f3072" />


- Hover a selected query block or an empty editor line, then click **agent mode**
- Press **Cmd+K** to open Agent Mode at the cursor
- Press **Cmd+Return** from the Agent Mode prompt to generate
- Press **Esc** or the close button to close Agent Mode

Cove currently supports:

- **Claude Code** via the `claude` CLI
- **Codex CLI** via the `codex` CLI

The selected agent receives the current query block, the active backend and database metadata, the loaded browser tree, and completion schema context. Cove does not send database passwords to the agent prompt.

Agent processes run locally from Cove's Application Support workspace. macOS may still show a Documents folder permission prompt if the underlying CLI tries to access a protected folder, especially when developing or launching Cove from a repository inside `~/Documents`.

## Install

Download the latest `.dmg` from [Releases](https://github.com/emanuele-em/cove/releases/latest).

> On first launch, macOS may block the app. Right-click the app and select **Open** to bypass Gatekeeper.

Or build from source:

```bash
# One-time Xcode setup, if needed
xcodebuild -runFirstLaunch

xcodebuild -scheme Cove -derivedDataPath .build build
open .build/Build/Products/Debug/Cove.app
```

If `xcodebuild` fails because Xcode has not completed setup on your machine, run `xcodebuild -runFirstLaunch` once and retry.

Requires macOS 15+.

## Roadmap

Contributions welcome:

- Import/export (CSV, JSON, SQL)
- Data filtering and search
- Query history panel
- SSL/TLS certificate configuration UI
- Query explain/analyze visualization
- Homebrew cask

## Community

- [Bug reports](https://github.com/emanuele-em/cove/issues/new?template=bug_report.md)
- [Feature requests](https://github.com/emanuele-em/cove/issues/new?template=feature_request.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

[MIT](LICENSE)
