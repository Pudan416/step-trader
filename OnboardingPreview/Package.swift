// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OnboardingPreview",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OnboardingPreview",
            path: "Sources"
        )
    ]
)
