// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceDictation",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceDictation",
            path: "Sources/VoiceDictation"
        ),
        .testTarget(
            name: "VoiceDictationTests",
            dependencies: ["VoiceDictation"],
            path: "Tests/VoiceDictationTests"
        ),
    ]
)
