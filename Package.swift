// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "nio-1279",
    dependencies: [
         .package(url: "https://github.com/apple/swift-nio.git", from: "2.10.1"),
         .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "nio-1279",
            dependencies: [
            "NIO",
            "NIOConcurrencyHelpers",
            "NIOFoundationCompat",
            "NIOHTTP1",
            "NIOSSL",
            "NIOWebSocket"
        ]),
        .testTarget(
            name: "nio-1279Tests",
            dependencies: ["nio-1279"]),
    ]
)
