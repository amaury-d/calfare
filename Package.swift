// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Calflare",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CalflareCore", targets: ["CalflareCore"]),
        .executable(name: "CalflareAgent", targets: ["CalflareAgent"]),
        .executable(name: "CalflareOverlay", targets: ["CalflareOverlay"])
    ],
    targets: [
        .target(name: "CalflareCore"),
        .executableTarget(
            name: "CalflareAgent",
            dependencies: ["CalflareCore"]
        ),
        .executableTarget(
            name: "CalflareOverlay"
        ),
        .testTarget(name: "CalflareCoreTests", dependencies: ["CalflareCore"])
    ]
)
