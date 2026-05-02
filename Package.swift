// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Cove",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio", from: "1.21.0"),
        .package(url: "https://github.com/vapor/mysql-nio", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-cassandra-client.git", from: "0.9.1"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0"),
        .package(url: "https://github.com/orlandos-nl/MongoKitten.git", from: "7.14.0"),
        .package(url: "https://github.com/swift-server/RediStack.git", from: "1.6.0"),
        .package(url: "https://github.com/lovetodream/oracle-nio.git", from: "1.0.0-rc.1"),
        .package(url: "https://github.com/vkuttyp/CosmoSQLClient-Swift.git", branch: "main"),
        .package(url: "https://github.com/patrick-zippenfenig/ClickHouseNIO.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Cove",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "CassandraClient", package: "swift-cassandra-client"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "RediStack", package: "RediStack"),
                .product(name: "OracleNIO", package: "oracle-nio"),
                .product(name: "CosmoMSSQL", package: "CosmoSQLClient-Swift"),
                .product(name: "ClickHouseNIO", package: "ClickHouseNIO"),
                "CDuckDB",
            ],
            path: "Cove",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            linkerSettings: [
                .linkedLibrary("duckdb"),
                .unsafeFlags(["-L/opt/homebrew/lib"]),
            ]
        ),
        .systemLibrary(
            name: "CDuckDB",
            path: "Sources/CDuckDB"
        ),
    ]
)
