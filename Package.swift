// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftEarcut",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "SwiftEarcut", targets: ["SwiftEarcut"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    ],
    targets: [
        .target(name: "SwiftEarcut", dependencies: [
            .product(name: "HeapModule", package: "swift-collections"),
        ]),
        .testTarget(name: "SwiftEarcutTests", dependencies: ["SwiftEarcut"]),
        .executableTarget(
            name: "Benchmarks",
            dependencies: ["SwiftEarcut"],
            path: "Benchmarks"
        ),
    ]
)
