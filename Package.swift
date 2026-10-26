// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LidBlur",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LidBlurCore"),
        .executableTarget(name: "LidBlur", dependencies: ["LidBlurCore"]),
        .testTarget(name: "LidBlurCoreTests", dependencies: ["LidBlurCore"]),
    ]
)
