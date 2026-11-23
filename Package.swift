// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Dockus",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "Dockus", path: "Sources/Dockus")
    ]
)
