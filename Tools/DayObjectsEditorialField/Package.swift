// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayObjectsEditorialField",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EditorialFieldCore", targets: ["EditorialFieldCore"]),
        .executable(name: "editorial-field-corpus", targets: ["editorial-field-corpus"]),
    ],
    targets: [
        .target(name: "EditorialFieldCore"),
        .executableTarget(name: "editorial-field-corpus", dependencies: ["EditorialFieldCore"]),
        .testTarget(name: "EditorialFieldCoreTests", dependencies: ["EditorialFieldCore"]),
    ]
)
