// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HimalayaMcpCLI",
    platforms: [
        // swift-configuration 1.0 APIs require macOS 15.0+.
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(
            url: "https://github.com/apple/swift-configuration.git",
            from: "1.0.0",
            traits: ["JSON", "YAML"]
        ),
        .package(url: "https://github.com/amine2233/cascade-kit.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.

        // Domain + DI keys/services: the typed `Request` commands, the
        // `ExecutableService`, and the service keys. The executable owns the
        // container instance and `configure(_:)`.
        .target(
            name: "App",
            dependencies: [
                "AppConfiguration",
                .product(name: "CascadeKit", package: "cascade-kit")
            ]
        ),
        // Reusable configuration module: swift-configuration setup + feature flags.
        // Free of ArgumentParser/MCP so any target (or future tool) can depend on it.
        .target(
            name: "AppConfiguration",
            dependencies: [
                .product(name: "Configuration", package: "swift-configuration")
            ]
        ),
        .executableTarget(
            name: "HimalayaMcpCLI",
            dependencies: [
                "App",
                "AppConfiguration",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "CascadeKit", package: "cascade-kit")
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "App",
                "AppConfiguration",
                .product(name: "CascadeKit", package: "cascade-kit")
            ]
        ),
        .testTarget(
            name: "AppConfigurationTests",
            dependencies: [
                "AppConfiguration",
                .product(name: "Configuration", package: "swift-configuration")
            ]
        ),
        .testTarget(
            name: "HimalayaMcpCLITests",
            dependencies: [
                "HimalayaMcpCLI",
                "App",
                "AppConfiguration",
                .product(name: "CascadeKit", package: "cascade-kit")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
