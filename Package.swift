// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "switchboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sb", targets: ["sb"]),
        .library(name: "SwitchboardCore", targets: ["SwitchboardCore"]),
    ],
    targets: [
        .target(name: "SwitchboardCore"),
        .executableTarget(name: "sb", dependencies: ["SwitchboardCore"]),
    ]
)
