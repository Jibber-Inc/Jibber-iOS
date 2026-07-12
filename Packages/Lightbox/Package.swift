// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Lightbox",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "Lightbox", targets: ["Lightbox"])
    ],
    dependencies: [
        .package(url: "https://github.com/hyperoslo/Imaginary.git", branch: "master")
    ],
    targets: [
        .target(
            name: "Lightbox",
            dependencies: ["Imaginary"],
            resources: [.copy("Resources/Lightbox.bundle")]
        )
    ]
)
