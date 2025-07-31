// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SwiftAIS",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/RTLSDRWrapper", branch: "main"),
        .package(url: "https://github.com/ConnorGibbons/SignalTools", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwiftAIS",
            dependencies: [
                .product(name: "RTLSDRWrapper", package: "RTLSDRWrapper"),
                .product(name: "SignalTools", package: "SignalTools")
            ]
        ),
        .testTarget(
            name: "SwiftAISTests",
            dependencies: ["SwiftAIS"],
            resources: [
                .process("TestData")
            ]
        )
    ]
)
