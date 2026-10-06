// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClockifyBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClockifyBar", targets: ["ClockifyBar"])],
    targets: [
        .target(name: "ClockifyCore"),
        .executableTarget(name: "ClockifyBar", dependencies: ["ClockifyCore"]),
        .testTarget(name: "ClockifyCoreTests", dependencies: ["ClockifyCore"]),
        .testTarget(name: "ClockifyBarTests", dependencies: ["ClockifyBar", "ClockifyCore"])
    ]
)
