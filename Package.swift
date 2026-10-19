// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AILimit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AILimit", path: "Sources/AILimit")
    ]
)
