// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentSentinel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentSentinel", targets: ["AgentSentinel"])
    ],
    targets: [
        .executableTarget(
            name: "AgentSentinel",
            path: "Sources"
        )
    ]
)
