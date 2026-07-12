// swift-tools-version: 6.4

import PackageDescription

let swift6Settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "Transitions",
    platforms: [.iOS(.v27)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Transitions",
            targets: ["Transitions"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Transitions",
            dependencies: [],
            swiftSettings: swift6Settings),
        .testTarget(
            name: "TransitionsTests",
            dependencies: ["Transitions"],
            swiftSettings: swift6Settings),
    ],
    swiftLanguageModes: [.v6]
)
