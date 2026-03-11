// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Morfeo",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-cassandra-client.git", from: "0.9.1"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "Morfeo",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "CassandraClient", package: "swift-cassandra-client"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Morfeo",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
