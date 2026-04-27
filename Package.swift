// swift-tools-version:5.5
// 5.5 needed for .package(url:,branch:)
// Don't put space in front of version number of Swift will get mad

import PackageDescription

let package = Package(
    name: "SwiftAIS",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/SignalTools", branch: "main"),
        .package(url: "https://github.com/ConnorGibbons/Networking", branch: "main"),
        .package(url: "https://github.com/ConnorGibbons/SoapySDRWrapper", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwiftAIS",
            dependencies: [
                .product(name: "SoapySDRWrapper", package: "SoapySDRWrapper"),
                .product(name: "SignalTools", package: "SignalTools"),
                .product(name: "Networking", package: "Networking"),
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
