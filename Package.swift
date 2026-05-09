// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "MacHub",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "MacHub", targets: ["MacHub"])
  ],
  targets: [
    .target(
      name: "MacHubSMC",
      swiftSettings: [
        .unsafeFlags(["-Onone"], .when(configuration: .release))
      ],
      linkerSettings: [
        .linkedFramework("IOKit")
      ]
    ),
    .executableTarget(
      name: "MacHub",
      dependencies: ["MacHubSMC"],
      linkerSettings: [
        .linkedFramework("ApplicationServices"),
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("Metal"),
        .linkedFramework("IOKit")
      ]
    ),
    .testTarget(
      name: "MacHubTests",
      dependencies: ["MacHub"]
    )
  ]
)
