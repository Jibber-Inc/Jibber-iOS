// swift-tools-version: 6.4

import PackageDescription

let swift6Settings: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "Messaging",
    platforms: [
        .iOS(.v27),
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
            exact: "7.11.1"
        )
    ],
    targets: [
        .target(
            name: "MessagingContracts",
            swiftSettings: swift6Settings
        ),
        .target(
            name: "MessagingPersistence",
            dependencies: [
                "MessagingContracts",
                .product(name: "ParseSwift", package: "Parse-Swift"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: swift6Settings
        ),
        .testTarget(
            name: "MessagingContractsTests",
            dependencies: ["MessagingContracts"],
            swiftSettings: swift6Settings
        ),
        .testTarget(
            name: "MessagingPersistenceTests",
            dependencies: ["MessagingPersistence"],
            swiftSettings: swift6Settings
        )
    ],
    swiftLanguageModes: [.v6]
)
