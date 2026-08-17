// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Curtain",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Curtain", targets: ["Curtain"]),
        .library(name: "CurtainCore", targets: ["CurtainCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "CurtainCore"),
        .executableTarget(
            name: "Curtain",
            dependencies: [
                "CurtainCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "CurtainCoreTests", dependencies: ["CurtainCore"]),
    ]
)
