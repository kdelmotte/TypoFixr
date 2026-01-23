// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyboardHero",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KeyboardHero", targets: ["KeyboardHero"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "KeyboardHero",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                "HotKey"
            ],
            path: "Sources/KeyboardHero",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KeyboardHeroTests",
            dependencies: ["KeyboardHero"],
            path: "Tests/KeyboardHeroTests"
        )
    ]
)
