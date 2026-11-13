// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceDictation",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher"
        ),
        .executableTarget(
            name: "VoiceDictation",
            dependencies: ["ObjCExceptionCatcher"],
            path: "Sources/VoiceDictation"
        ),
        .testTarget(
            name: "VoiceDictationTests",
            dependencies: ["VoiceDictation", "ObjCExceptionCatcher"],
            path: "Tests/VoiceDictationTests"
        ),
    ]
)
