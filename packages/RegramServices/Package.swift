// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "RegramServices",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "RegramServices", targets: ["RegramServices"])],
    dependencies: [
        .package(name: "RegramCore", path: "../RegramCore"),
        .package(name: "MtProtoKit", path: "../../submodules/telegram-ios/submodules/MtProtoKit"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit")
    ],
    targets: [
        .target(name: "RegramServices", dependencies: ["RegramCore", .product(name: "MtProtoKit", package: "MtProtoKit"), .product(name: "SwiftSignalKit", package: "SSignalKit")], resources: [.process("Resources")]),
        .testTarget(name: "RegramServicesTests", dependencies: ["RegramServices", .product(name: "RegramCore", package: "RegramCore"), .product(name: "SwiftSignalKit", package: "SSignalKit")])
    ]
)
