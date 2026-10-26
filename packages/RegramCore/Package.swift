// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "RegramCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "RegramCore", targets: ["RegramCore"]),
        .library(name: "RegramSignals", targets: ["RegramSignals"])
    ],
    dependencies: [.package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit")],
    targets: [
        .target(name: "RegramCore", resources: [.process("Resources")]),
        .target(name: "RegramSignals", dependencies: ["RegramCore", .product(name: "SwiftSignalKit", package: "SSignalKit")]),
        .testTarget(name: "RegramCoreTests", dependencies: ["RegramCore", "RegramSignals"])
    ]
)
