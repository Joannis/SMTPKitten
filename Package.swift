// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SMTPKitten",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SMTPKitten",
            targets: ["SMTPKitten"]),
    ],
    dependencies: [
        // 🚀
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
        
        // 🔑
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SMTPKitten",
            dependencies: ["NIO", "NIOSSL", "NIOExtras"]),
        .testTarget(
            name: "SMTPKittenTests",
            dependencies: ["SMTPKitten", "NIOFoundationCompat"]),
    ]
)
