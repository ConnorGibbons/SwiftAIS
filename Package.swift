// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftAIS",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/RTLSDRWrapper", revision: "c2b4bd2"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftAIS",
            dependencies: [
                .product(name: "RTLSDRWrapper", package: "RTLSDRWrapper")
            ]
        ),
    ]
)
