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
        ),
        // Unit tests for the parts that decide what gets through: risk scoring, scopes, phone crypto.
        .testTarget(
            name: "loggdinTests",
            dependencies: ["loggdin"],
            path: "tests/loggdinTests"
        )
    ]
)
