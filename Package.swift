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
      targets: ["Overtype"])
  ],
  dependencies: [
    // KeyboardShortcuts 1.15.0 is vendored, not fetched: upstream's generated
    // Bundle.module accessor calls fatalError from a path that no signable .app
    // can satisfy, which crashed Settings > Actions > Add/Edit in every release.
    // Vendor/KeyboardShortcuts/VENDORING.md records the upstream revision, the
    // evidence, and the exact local patch. Do not swap this back for a remote
    // pin without re-applying that patch.
    .package(path: "Vendor/KeyboardShortcuts")
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
