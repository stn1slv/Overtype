// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Overtype",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Overtype",
            targets: ["Overtype"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Overtype",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .testTarget(
            name: "OvertypeTests",
            dependencies: ["Overtype"]),
    ]
)
