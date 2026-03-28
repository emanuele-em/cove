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
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/cassandra-logo.imageset/cassandra-logo.png" width="40"><br><b>Cassandra</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/elasticsearch-logo.imageset/elasticsearch-logo.png" width="40"><br><b>Elasticsearch</b></td>
  </tr>
</table>

Adding a new backend requires zero changes to UI code — see [`DB/README.md`](Cove/DB/README.md).

## Features

- **Browse** schemas, tables, views, indexes, and keys in a sidebar tree
- **Edit rows** inline with SQL/CQL preview before commit
- **Run queries** with syntax highlighting and autocomplete
- **Multiple tabs** with independent connections (Cmd+T)
- **Connection environments** — local, dev, staging, production
- **SSH tunneling** — password or private key authentication
- **Session persistence** — connections and tabs restore across app relaunches
- **Color-coded indicators** and connection tooltips
- Native macOS UI — no Electron, no web views

## Install

Download the latest `.dmg` from [Releases](https://github.com/emanuele-em/cove/releases/latest).

> On first launch, macOS may block the app. Right-click the app and select **Open** to bypass Gatekeeper.

Or build from source:

```
xcodebuild -scheme Cove -derivedDataPath .build build
open .build/Build/Products/Debug/Cove.app
```

Requires macOS 15+.

## Roadmap

Contributions welcome:

- Import/export (CSV, JSON, SQL)
- Data filtering and search
- Query history panel
- SSL/TLS certificate configuration UI
- Query explain/analyze visualization
- Homebrew cask
- More backends (clickhouse, duckDB, sqlserver)

## Community

- [Bug reports](https://github.com/emanuele-em/cove/issues/new?template=bug_report.md)
- [Feature requests](https://github.com/emanuele-em/cove/issues/new?template=feature_request.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

[MIT](LICENSE)
