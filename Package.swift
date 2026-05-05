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
    targets: [
        .executableTarget(
            name: "Snipr",
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
