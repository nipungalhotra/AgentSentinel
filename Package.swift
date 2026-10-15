// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "loggdin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "loggdin", targets: ["loggdin"])
    ],
    targets: [
        .executableTarget(
            name: "loggdin",
            path: "Sources"
        )
    ]
)
