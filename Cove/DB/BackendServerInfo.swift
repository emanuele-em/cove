import Foundation

private func firstCell(_ result: QueryResult) -> String? {
    result.rows.first?.first.flatMap { $0 }?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

extension PostgresBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT version()"))
    }
}

extension MySQLBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT VERSION()"))
    }
}

extension MariaDBBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT VERSION()"))
    }
}

extension SQLiteBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT sqlite_version()"))
    }
}

extension DuckDBBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT version()"))
    }
}

extension CassandraBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: "", sql: "SELECT release_version FROM system.local"))
    }
}

extension ScyllaBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: "", sql: "SELECT release_version FROM system.local"))
    }
}

extension ClickHouseBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT version()"))
    }
}

extension OracleBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT banner FROM v$version WHERE rownum = 1"))
    }
}

extension SQLServerBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        firstCell(try await executeQuery(database: database, sql: "SELECT @@VERSION"))
    }
}

extension MongoDBBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        struct BuildInfoCommand: Encodable, Sendable {
            let buildInfo = 1
        }
        struct BuildInfoResponse: Decodable, Sendable {
            let version: String?
        }

        let db = try await databaseFor(name: database.isEmpty ? "admin" : database)
        let result = try await executeRawCommand(
            BuildInfoCommand(),
            decodeAs: BuildInfoResponse.self,
            on: db
        )
        return result.version
    }
}

extension RedisBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        let db = Int(database) ?? Int(config.database) ?? 0
        let response = try await sendCommand("INFO", ["server"], db: db)
        guard let info = response.string else { return nil }
        for line in info.components(separatedBy: .newlines) {
            if line.hasPrefix("redis_version:") {
                return line.replacingOccurrences(of: "redis_version:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}

extension ElasticsearchBackend {
    func fetchServerVersion(database: String) async throws -> String? {
        guard let info = try await request(method: "GET", path: "/") as? [String: Any],
              let version = info["version"] as? [String: Any],
              let number = version["number"] as? String else { return nil }
        return number
    }
}

