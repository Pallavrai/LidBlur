// swift-tools-version: 6.0
// SwiftPM instead of an .xcodeproj: same targets, buildable and testable from the CLI; open Package.swift in Xcode.
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
