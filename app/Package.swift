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
  targets: [
    .executableTarget(
      name: "GunkApp"
    ),
    .testTarget(
      name: "GunkAppTests",
      dependencies: ["GunkApp"]
    )
  ]
)
