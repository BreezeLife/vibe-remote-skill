// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeRemote",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VibeRemoteCore", targets: ["VibeRemoteCore"]),
        .executable(name: "VibeRemote", targets: ["VibeRemote"])
    ],
    targets: [
        .target(name: "VibeRemoteCore"),
        .executableTarget(name: "VibeRemote", dependencies: ["VibeRemoteCore"]),
        .testTarget(name: "VibeRemoteCoreTests", dependencies: ["VibeRemoteCore"])
    ]
)
