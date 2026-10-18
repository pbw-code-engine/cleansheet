// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PbWCodeEngine",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CodeEngineCore"),
        .executableTarget(name: "PbWCodeEngine", dependencies: ["CodeEngineCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["CodeEngineCore"]),
    ]
)
