// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Lightbox",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "Lightbox", targets: ["Lightbox"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/hyperoslo/Imaginary.git",
            revision: "2f30de8b84d9f85d3c66386e2461df6db70c645b"
        )
    ],
    targets: [
        .target(
            name: "Lightbox",
            dependencies: ["Imaginary"],
            resources: [.copy("Resources/Lightbox.bundle")]
        )
    ]
)
