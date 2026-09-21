// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RainNext",
    platforms: [.macOS(.v14)],
    targets: [
        // Models + services. No SwiftUI, no AppKit UI — keeps the domain testable.
        .target(
            name: "RainNextKit",
            path: "Sources/RainNextKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menu bar app: SwiftUI views only.
        .executableTarget(
            name: "RainNext",
            dependencies: ["RainNextKit"],
            path: "Sources/RainNext",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RainNextKitTests",
            dependencies: ["RainNextKit"],
            path: "Tests/RainNextKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
