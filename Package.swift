// swift-tools-version:5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SMTPKitten",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SMTPKitten",
            targets: ["SMTPKitten"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/multipart-kit.git", from: "4.7.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.3"),

        // 🚀
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
        
        // 🔑
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SMTPKitten",
            dependencies: [
                .product(name: "MultipartKit", package: "multipart-kit"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]),
        .testTarget(
            name: "SMTPKittenTests",
            dependencies: ["SMTPKitten"]),
    ]
)
