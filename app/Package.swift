// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "GunkApp",
  platforms: [
    .macOS(.v26)
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
        .copy("Resources/Assets.xcassets"),
        .copy("Resources/ProviderIcons")
      ]
    ),
    .testTarget(
      name: "GunkAppTests",
      dependencies: [
        "GunkApp",
        .product(name: "GRDB", package: "GRDB.swift")
      ]
    )
  ],
  // Keep the Swift 5 language mode for now: tools 6.x would otherwise turn on
  // Swift 6 strict concurrency, a migration that is out of scope for the
  // macOS 26 platform bump (T-7.1).
  swiftLanguageModes: [.v5]
)
