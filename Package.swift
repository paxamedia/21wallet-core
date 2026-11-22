// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "21wallet-core",
    platforms: [.iOS(.v17), .macOS("15.5")],
    products: [
        .library(name: "WalletCore", targets: ["WalletCore"]),
        .library(name: "BitcoinEngine", targets: ["BitcoinEngine"]),
        .library(name: "SecureStore", targets: ["SecureStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/bitcoindevkit/bdk-swift.git", from: "3.0.0")
    ],
    targets: [
        .target(name: "WalletCore"),
        .testTarget(name: "WalletCoreTests", dependencies: ["WalletCore"]),
        .target(
            name: "BitcoinEngine",
            dependencies: [
                "WalletCore",
                .product(name: "BitcoinDevKit", package: "bdk-swift"),
            ]
        ),
        .testTarget(name: "BitcoinEngineTests", dependencies: ["BitcoinEngine"]),
        .target(name: "SecureStore", dependencies: ["WalletCore"]),
        .testTarget(name: "SecureStoreTests", dependencies: ["SecureStore", "WalletCore"]),
        .executableTarget(
            name: "WordlistGenerator",
            dependencies: [.product(name: "BitcoinDevKit", package: "bdk-swift")]
        ),
    ]
)
