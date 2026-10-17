// swift-tools-version: 6.0
// FunLayerCore — платформенно-независимое ядро «слоя приколов».
// Только Foundation: никакого UIKit/SwiftUI, никаких сторонних зависимостей.
// Каждый файл переносится на Kotlin 1:1 (см. docs/ANDROID_PORTING.md).
import PackageDescription

let package = Package(
    name: "FunLayerCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "FunLayerCore", targets: ["FunLayerCore"]),
    ],
    targets: [
        .target(name: "FunLayerCore"),
        .testTarget(name: "FunLayerCoreTests", dependencies: ["FunLayerCore"]),
    ]
)
