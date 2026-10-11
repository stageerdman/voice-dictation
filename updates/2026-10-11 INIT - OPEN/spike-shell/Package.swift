// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShellSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShellSpike",
            path: "Sources/ShellSpike"
        )
    ]
)
