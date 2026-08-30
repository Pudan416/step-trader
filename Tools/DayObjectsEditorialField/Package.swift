// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayObjectsEditorialField",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EditorialFieldCore", targets: ["EditorialFieldCore"]),
        .library(name: "EditorialFieldRender", targets: ["EditorialFieldRender"]),
        .library(name: "EditorialFieldEvidence", targets: ["EditorialFieldEvidence"]),
        .executable(name: "editorial-field-corpus", targets: ["editorial-field-corpus"]),
        .executable(name: "editorial-field-render", targets: ["editorial-field-render"]),
    ],
    targets: [
        .target(name: "EditorialFieldCore"),
        .target(name: "EditorialFieldRender", dependencies: ["EditorialFieldCore"]),
        .target(
            name: "EditorialFieldEvidence",
            dependencies: ["EditorialFieldCore", "EditorialFieldRender"]
        ),
        .executableTarget(name: "editorial-field-corpus", dependencies: ["EditorialFieldCore"]),
        .executableTarget(
            name: "editorial-field-render",
            dependencies: ["EditorialFieldCore", "EditorialFieldRender", "EditorialFieldEvidence"]
        ),
        .testTarget(name: "EditorialFieldCoreTests", dependencies: ["EditorialFieldCore"]),
        .testTarget(
            name: "EditorialFieldRenderTests",
            dependencies: ["EditorialFieldCore", "EditorialFieldRender", "EditorialFieldEvidence"]
        ),
    ]
)
