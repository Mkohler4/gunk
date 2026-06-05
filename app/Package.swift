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
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
    .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.10.0"),
    .package(url: "https://github.com/tree-sitter/tree-sitter-javascript.git", exact: "0.25.0"),
    .package(url: "https://github.com/tree-sitter/tree-sitter-typescript.git", exact: "0.23.2"),
    .package(url: "https://github.com/tree-sitter/tree-sitter-python.git", exact: "0.25.0"),
    .package(url: "https://github.com/alex-pinkus/tree-sitter-swift.git", revision: "31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"),
    .package(url: "https://github.com/tree-sitter/tree-sitter-go.git", exact: "0.25.0")
  ],
  targets: [
    .executableTarget(
      name: "GunkApp",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
        .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
        .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
        .product(name: "TreeSitterPython", package: "tree-sitter-python"),
        .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
        .product(name: "TreeSitterGo", package: "tree-sitter-go"),
        "TreeSitterScannerSupport"
      ],
      resources: [
        .copy("Resources/Assets.xcassets")
      ]
    ),
    .target(
      name: "TreeSitterScannerSupport",
      path: "Sources/TreeSitterScannerSupport",
      exclude: ["NOTICE.md"],
      sources: [
        "javascript_scanner.c",
        "python_scanner.c"
      ],
      publicHeadersPath: "include",
      cSettings: [.headerSearchPath("include")]
    ),
    .testTarget(
      name: "GunkAppTests",
      dependencies: [
        "GunkApp",
        .product(name: "GRDB", package: "GRDB.swift")
      ],
      resources: [
        .copy("Fixtures")
      ]
    )
  ]
)
