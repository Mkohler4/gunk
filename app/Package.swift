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
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
  ],
  targets: [
    .executableTarget(
      name: "GunkApp",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
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
