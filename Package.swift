// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Calflare",
    defaultLocalization: "en",
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
            dependencies: ["CalflareCore"],
            path: "Sources/CalflareAgent",
            exclude: ["Info.plist", "Resources"]
        ),
        .executableTarget(
            name: "CalflareOverlay",
            path: "Sources/CalflareOverlay",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CalflareCoreTests", dependencies: ["CalflareCore"])
    ]
)
