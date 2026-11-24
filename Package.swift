// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aeris",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Aeris",
            path: "Sources/Aeris"
        )
    ]
)
