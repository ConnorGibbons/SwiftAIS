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
        .package(url: "https://github.com/ConnorGibbons/RTLSDRWrapper", revision: "9dd86782273d5a8dcd48afb7cc41c85a897b6d7a"),
        .package(url: "https://github.com/ConnorGibbons/SignalTools", from: "1.0.1"),
        .package(url: "https://github.com/ConnorGibbons/TCPUtils", from: "1.0.3"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftAIS",
            dependencies: [
                .product(name: "RTLSDRWrapper", package: "RTLSDRWrapper"),
                .product(name: "SignalTools", package: "SignalTools"),
                .product(name: "TCPUtils", package: "TCPUtils"),
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
