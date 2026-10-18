// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanSheet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CleanSheetCore"),
        .executableTarget(name: "CleanSheet", dependencies: ["CleanSheetCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["CleanSheetCore"]),
    ]
)
