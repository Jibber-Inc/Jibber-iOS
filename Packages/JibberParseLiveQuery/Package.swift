// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "JibberParseLiveQuery",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15),
        .tvOS(.v12),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "JibberParseLiveQuery",
            targets: ["JibberParseLiveQuery"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/parse-community/Parse-SDK-iOS-OSX.git",
            .exact("4.2.0")
        ),
        .package(
            url: "https://github.com/BoltsFramework/Bolts-Swift.git",
            .exact("1.5.0")
        ),
        .package(
            url: "https://github.com/daltoniam/Starscream.git",
            .exact("4.0.8")
        )
    ],
    targets: [
        .target(
            name: "JibberParseLiveQuery",
            dependencies: [
                .product(
                    name: "ParseObjC",
                    package: "Parse-SDK-iOS-OSX"
                ),
                .product(
                    name: "BoltsSwift",
                    package: "Bolts-Swift"
                ),
                .product(
                    name: "Starscream",
                    package: "Starscream"
                )
            ],
            path: "Sources/ParseLiveQuery",
            swiftSettings: [
                // ParseCore's umbrella header exposes deprecated StoreKit 1
                // purchase declarations that ParseLiveQuery never uses.
                .unsafeFlags([
                    "-Xcc",
                    "-Wno-deprecated-declarations"
                ])
            ]
        )
    ]
)
