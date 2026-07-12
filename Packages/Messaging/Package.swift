// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Messaging",
    platforms: [
        .iOS(.v14),
        .macOS(.v12)
    ],
    products: [
        .library(name: "MessagingContracts", targets: ["MessagingContracts"]),
        .library(name: "MessagingPersistence", targets: ["MessagingPersistence"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/parse-community/Parse-Swift.git",
            exact: "4.14.2"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.10.0"
        )
    ],
    targets: [
        .target(name: "MessagingContracts"),
        .target(
            name: "MessagingPersistence",
            dependencies: [
                "MessagingContracts",
                .product(name: "ParseSwift", package: "Parse-Swift"),
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MessagingContractsTests",
            dependencies: ["MessagingContracts"]
        ),
        .testTarget(
            name: "MessagingPersistenceTests",
            dependencies: ["MessagingPersistence"]
        )
    ]
)

