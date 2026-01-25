// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TypoFixr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TypoFixr", targets: ["TypoFixr"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", exact: "0.14.1"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "TypoFixr",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                "HotKey"
            ],
            path: "Sources/TypoFixr",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "TypoFixrTests",
            dependencies: ["TypoFixr"],
            path: "Tests/TypoFixrTests"
        )
    ]
)
