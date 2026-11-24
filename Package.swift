// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ACControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ACControl",
            path: "Sources/ACControl"
        )
    ]
)
