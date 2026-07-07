// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Snipr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Snipr", targets: ["Snipr"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Snipr",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SniprTests",
            dependencies: ["Snipr"]
        )
    ]
)
