// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftEarcut",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftEarcut", targets: ["SwiftEarcut"]),
    ],
    targets: [
        .target(name: "SwiftEarcut"),
        .testTarget(name: "SwiftEarcutTests", dependencies: ["SwiftEarcut"]),
    ]
)
