// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Capitalist",
     platforms: [
              .macOS(.v10_13),
              .iOS(.v10),
              .watchOS(.v5)
         ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "Capitalist",
            targets: ["Capitalist"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
		  .package(url: "https://github.com/bengottlieb/Suite.git", from: "0.9.30"),
		  .package(url: "https://github.com/bengottlieb/CrossPlatformKit", from: "1.0.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(name: "Capitalist", dependencies: ["Studio", "CrossPlatformKit"]),
    ]
)
