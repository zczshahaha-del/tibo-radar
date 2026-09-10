// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TiboRadar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "TiboRadar", targets: ["TiboRadarApp"]),
    ],
    targets: [
        .executableTarget(
            name: "TiboRadarApp",
            path: "Sources/TiboRadarApp"
        ),
        .testTarget(
            name: "TiboRadarAppTests",
            dependencies: ["TiboRadarApp"],
            path: "Tests/TiboRadarAppTests"
        ),
    ]
)
