// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShopCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ShopCore",
            targets: ["ShopCore"]
        )
    ],
    targets: [
        .target(
            name: "ShopCore",
            path: "Sources/ShopCore"
        ),
        .testTarget(
            name: "ShopCoreTests",
            dependencies: ["ShopCore"],
            path: "Tests/ShopCoreTests"
        )
    ]
)
