// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WordPopup",
    platforms: [.macOS("26.0")],
    dependencies: [
        // build.sh downloads the Core ML model of the same release: keep the two versions together.
        .package(url: "https://github.com/gradium-ai/xn-ptts.git", exact: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "WordPopup",
            dependencies: [.product(name: "ptts", package: "xn-ptts")],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Cocoa"), .linkedFramework("Carbon")]
        ),
    ]
)
