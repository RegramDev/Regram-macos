// swift-tools-version:5.5
import PackageDescription

let deps: [(String, String)] = [
    ("PhoneNumberUtils", "../PhoneNumberUtils"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("InAppSettings", "../InAppSettings"),
    ("ColorPalette", "../ColorPalette"),
    ("RegramCore", "../RegramCore"),
    ("RegramServices", "../RegramServices"),
    ("Translate", "../Translate"),
    ("TGUIKit", "../TGUIKit"),
    ("Localization", "../Localization"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramTheme", "../TelegramTheme"),
    ("InputDataUI", "../InputDataUI"),
    ("GeneralRows", "../GeneralRows"),
    ("TelegramUtils", "../TelegramUtils"),
    ("AlertsUI", "../AlertsUI")
]

let package = Package(
    name: "RegramUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "RegramUI", targets: ["RegramUI"])],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox")
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [.target(name: "RegramUI", dependencies: [
        .product(name: "SwiftSignalKit", package: "SSignalKit"),
        .product(name: "TelegramCore", package: "TelegramCore"),
        .product(name: "Postbox", package: "Postbox"),
        .product(name: "RegramSignals", package: "RegramCore")
    ] + deps.map { .product(name: $0.0, package: $0.0) }, resources: [.process("Resources")])]
)
