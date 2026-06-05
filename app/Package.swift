// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "GunkApp",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "GunkApp",
      targets: ["GunkApp"]
    )
  ],
  dependencies: [
    // Static analysis + the AI pipeline now live in the cross-platform
    // `gunk-engine` (TypeScript/Bun, via web-tree-sitter). The Swift app is a
    // thin macOS shell that spawns the engine, so the SwiftPM tree-sitter
    // grammars are no longer needed here.
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
  ],
  targets: [
    .executableTarget(
      name: "GunkApp",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
      ],
      resources: [
        .copy("Resources/Assets.xcassets")
      ]
    ),
    .testTarget(
      name: "GunkAppTests",
      dependencies: [
        "GunkApp",
        .product(name: "GRDB", package: "GRDB.swift")
      ]
    )
  ]
)
