// swift-tools-version: 6.4

import PackageDescription

let swift6Settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "Lightbox",
    platforms: [.iOS(.v27)],
    products: [
        .library(name: "Lightbox", targets: ["Lightbox"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Lightbox",
            dependencies: [],
            resources: [.copy("Resources/Lightbox.bundle")],
            swiftSettings: swift6Settings
        )
    ],
    swiftLanguageModes: [.v6]
)
