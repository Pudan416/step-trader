import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import EditorialFieldCore
import EditorialFieldRender

public enum EvidenceView: String, CaseIterable, Codable, Hashable, Sendable {
    case fullScreen
    case calendarTile
}

public struct CompositionEvidenceFrame: Codable, Equatable, Hashable, Sendable {
    public let suite: String
    public let fixtureIndex: Int
    public let stage: Int?
    public let actorCount: Int
    public let seed: UInt64
    public let phase: Double
    public let view: EvidenceView
}

public struct CompositionEvidenceCoverage: Equatable, Sendable {
    public let breadth: [CompositionEvidenceFrame]
    public let continuity: [CompositionEvidenceFrame]
    public let continuityActorCounts: [Int]

    public var coreImageCount: Int { breadth.count + continuity.count }
}

public struct EvidenceViewportMetadata: Codable, Equatable, Sendable {
    public let widthPoints: Int
    public let heightPoints: Int
    public let scale: Int
    public let tileCrop: String
}

public struct EvidenceArtifact: Codable, Equatable, Sendable {
    public let path: String
    public let kind: String
    public let byteCount: Int
    public let sha256: String
}

public struct CompositionEvidenceManifest: Codable, Equatable, Sendable {
    public let version: String
    public let sourceCommit: String
    public let rendererVersion: String
    public let toolchain: String
    public let device: String
    public let operatingSystem: String
    public let viewport: EvidenceViewportMetadata
    public let colorSpace: String
    public let corpusVersion: String
    public let specificationCommit: String
    public let coreImageCount: Int
    public let frames: [CompositionEvidenceFrame]
    public let overlays: [String]
    public let artifacts: [EvidenceArtifact]
}

public struct GeneratedCompositionEvidence: Sendable {
    public let manifest: CompositionEvidenceManifest
    public let packageHash: String
    public let outputDirectory: URL
}

public struct CompositionFrameMetrics: Codable, Equatable, Sendable {
    public let suite: String
    public let fixtureIndex: Int
    public let stage: Int?
    public let seed: UInt64
    public let phase: Double
    public let background: BackgroundCondition
    public let sleep: SleepCondition
    public let steps: StepCondition
    public let reduceMotion: Bool
    public let grammar: EditorialGrammar
    public let tileCrop: PixelRect
    public let actors: [NeutralActorEvidence]
}

public struct CompositionEvidenceMetrics: Codable, Equatable, Sendable {
    public let version: String
    public let breadthSceneCount: Int
    public let continuitySceneCount: Int
    public let coreImageCount: Int
    public let frames: [CompositionFrameMetrics]
}

public enum EvidencePackageError: Error, LocalizedError {
    case outputDirectoryNotEmpty(String)
    case missingControlFile(String)
    case malformedChecksumLine(String)
    case unsafeRelativePath(String)
    case artifactSetMismatch
    case hashMismatch(path: String, expected: String, actual: String)
    case packageHashMismatch(expected: String, actual: String)
    case cannotDecodeImage(String)
    case cannotCreateContactSheet

    public var errorDescription: String? {
        switch self {
        case .outputDirectoryNotEmpty(let path): "Evidence output directory is not empty: \(path)"
        case .missingControlFile(let name): "Evidence package is missing \(name)"
        case .malformedChecksumLine(let line): "Malformed SHA256SUMS line: \(line)"
        case .unsafeRelativePath(let path): "Unsafe evidence package path: \(path)"
        case .artifactSetMismatch: "SHA256SUMS does not name exactly the package artifacts"
        case .hashMismatch(let path, let expected, let actual):
            "Evidence hash mismatch for \(path): expected \(expected), got \(actual)"
        case .packageHashMismatch(let expected, let actual):
            "Evidence package hash mismatch: expected \(expected), got \(actual)"
        case .cannotDecodeImage(let path): "Cannot decode evidence image: \(path)"
        case .cannotCreateContactSheet: "Cannot create evidence contact sheet"
        }
    }
}

public enum EvidencePackage {
    public static func compositionCoverage(for manifest: CorpusManifest) -> CompositionEvidenceCoverage {
        let views = EvidenceView.allCases
        let breadth = manifest.breadth.flatMap { fixture in
            manifest.phases.flatMap { phase in
                views.map { view in
                    CompositionEvidenceFrame(
                        suite: fixture.suite,
                        fixtureIndex: fixture.index,
                        stage: nil,
                        actorCount: fixture.actorCount,
                        seed: fixture.seed,
                        phase: phase,
                        view: view
                    )
                }
            }
        }
        let continuity = manifest.continuity.stages.flatMap { stage in
            manifest.phases.flatMap { phase in
                views.map { view in
                    CompositionEvidenceFrame(
                        suite: manifest.continuity.suite,
                        fixtureIndex: manifest.continuity.index,
                        stage: stage.stage,
                        actorCount: stage.actorCount,
                        seed: manifest.continuity.seed,
                        phase: phase,
                        view: view
                    )
                }
            }
        }
        return CompositionEvidenceCoverage(
            breadth: breadth,
            continuity: continuity,
            continuityActorCounts: manifest.continuity.stages.map(\.actorCount)
        )
    }

    public static func generateComposition(
        manifest: CorpusManifest,
        sourceCommit: String,
        outputDirectory: URL,
        renderConfiguration: NeutralRenderConfiguration = .init(
            scale: 3,
            overlays: Set(NeutralOverlay.allCases)
        )
    ) throws -> GeneratedCompositionEvidence {
        try prepareEmptyDirectory(outputDirectory)
        let renderer = NeutralRenderer()
        let coverage = compositionCoverage(for: manifest)
        var frameMetrics = [CompositionFrameMetrics]()
        var breadthFullPaths = [String]()
        var continuityFullPaths = [String]()

        for fixture in manifest.breadth {
            for phase in manifest.phases {
                let recipe = CompositionPlanner.make(
                    daySeed: fixture.seed,
                    eventIDs: fixture.eventIDs,
                    viewport: .phone
                )
                let scene = try renderer.render(
                    recipe: recipe,
                    background: fixture.background,
                    configuration: renderConfiguration
                )
                let stem = "breadth-\(padded(fixture.index, width: 2))-phase-\(phaseCode(phase))"
                let fullPath = "renders/breadth/\(stem)-full@\(renderConfiguration.scale)x.png"
                let tilePath = "renders/breadth/\(stem)-tile@\(renderConfiguration.scale)x.png"
                try write(scene.fullScreen.pngData, relativePath: fullPath, in: outputDirectory)
                try write(scene.calendarTile.pngData, relativePath: tilePath, in: outputDirectory)
                breadthFullPaths.append(fullPath)
                try writeDebug(scene, suite: "breadth", stem: stem, scale: renderConfiguration.scale, output: outputDirectory)
                frameMetrics.append(CompositionFrameMetrics(
                    suite: fixture.suite,
                    fixtureIndex: fixture.index,
                    stage: nil,
                    seed: fixture.seed,
                    phase: phase,
                    background: fixture.background,
                    sleep: fixture.sleep,
                    steps: fixture.steps,
                    reduceMotion: fixture.reduceMotion,
                    grammar: recipe.grammar,
                    tileCrop: scene.tileCrop,
                    actors: scene.actors
                ))
            }
        }

        let continuityFixture = manifest.continuity
        for stage in continuityFixture.stages {
            for phase in manifest.phases {
                let recipe = CompositionPlanner.make(
                    daySeed: continuityFixture.seed,
                    eventIDs: stage.eventIDs,
                    viewport: .phone
                )
                let scene = try renderer.render(
                    recipe: recipe,
                    background: continuityFixture.background,
                    configuration: renderConfiguration
                )
                let stem = "continuity-stage-\(padded(stage.stage, width: 2))-count-\(padded(stage.actorCount, width: 2))-phase-\(phaseCode(phase))"
                let fullPath = "renders/continuity/\(stem)-full@\(renderConfiguration.scale)x.png"
                let tilePath = "renders/continuity/\(stem)-tile@\(renderConfiguration.scale)x.png"
                try write(scene.fullScreen.pngData, relativePath: fullPath, in: outputDirectory)
                try write(scene.calendarTile.pngData, relativePath: tilePath, in: outputDirectory)
                continuityFullPaths.append(fullPath)
                try writeDebug(scene, suite: "continuity", stem: stem, scale: renderConfiguration.scale, output: outputDirectory)
                frameMetrics.append(CompositionFrameMetrics(
                    suite: continuityFixture.suite,
                    fixtureIndex: continuityFixture.index,
                    stage: stage.stage,
                    seed: continuityFixture.seed,
                    phase: phase,
                    background: continuityFixture.background,
                    sleep: continuityFixture.sleep,
                    steps: continuityFixture.steps,
                    reduceMotion: continuityFixture.reduceMotion,
                    grammar: recipe.grammar,
                    tileCrop: scene.tileCrop,
                    actors: scene.actors
                ))
            }
        }

        let metrics = CompositionEvidenceMetrics(
            version: "composition-metrics-v1",
            breadthSceneCount: manifest.breadth.count * manifest.phases.count,
            continuitySceneCount: manifest.continuity.stages.count * manifest.phases.count,
            coreImageCount: coverage.coreImageCount,
            frames: frameMetrics
        )
        try write(canonicalJSON(metrics), relativePath: "metrics.json", in: outputDirectory)
        try write(manifest.canonicalJSON(), relativePath: "corpus-manifest.json", in: outputDirectory)
        try makeContactSheet(paths: breadthFullPaths, outputPath: "contact-sheets/breadth.png", directory: outputDirectory)
        try makeContactSheet(paths: continuityFullPaths, outputPath: "contact-sheets/continuity.png", directory: outputDirectory)

        let artifacts = try artifactRecords(in: outputDirectory)
        let packageManifest = CompositionEvidenceManifest(
            version: "composition-evidence-v1",
            sourceCommit: sourceCommit,
            rendererVersion: NeutralRenderer.version,
            toolchain: "Swift 6 / Swift Package Manager",
            device: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            viewport: EvidenceViewportMetadata(
                widthPoints: 393,
                heightPoints: 852,
                scale: renderConfiguration.scale,
                tileCrop: "centered-square-from-phone-canvas"
            ),
            colorSpace: "sRGB",
            corpusVersion: manifest.version,
            specificationCommit: manifest.specificationCommit,
            coreImageCount: coverage.coreImageCount,
            frames: coverage.breadth + coverage.continuity,
            overlays: renderConfiguration.overlays.map(\.rawValue).sorted(),
            artifacts: artifacts
        )
        try write(canonicalJSON(packageManifest), relativePath: "manifest.json", in: outputDirectory)
        let packageHash = try seal(directory: outputDirectory)
        return GeneratedCompositionEvidence(
            manifest: packageManifest,
            packageHash: packageHash,
            outputDirectory: outputDirectory
        )
    }

    @discardableResult
    public static func seal(directory: URL) throws -> String {
        let artifacts = try packageFilePaths(in: directory)
        let lines = try artifacts.map { path -> String in
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            return "\(sha256(data))  \(path)"
        }
        var sums = Data(lines.joined(separator: "\n").utf8)
        sums.append(0x0A)
        try sums.write(to: directory.appendingPathComponent("SHA256SUMS"), options: .atomic)
        let packageHash = sha256(sums)
        try Data("\(packageHash)\n".utf8).write(
            to: directory.appendingPathComponent("package-hash.txt"),
            options: .atomic
        )
        return packageHash
    }

    @discardableResult
    public static func verify(directory: URL) throws -> String {
        let sumsURL = directory.appendingPathComponent("SHA256SUMS")
        let hashURL = directory.appendingPathComponent("package-hash.txt")
        guard FileManager.default.fileExists(atPath: sumsURL.path) else {
            throw EvidencePackageError.missingControlFile("SHA256SUMS")
        }
        guard FileManager.default.fileExists(atPath: hashURL.path) else {
            throw EvidencePackageError.missingControlFile("package-hash.txt")
        }
        let sums = try Data(contentsOf: sumsURL)
        let expectedPackageHash = try String(contentsOf: hashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let actualPackageHash = sha256(sums)
        guard expectedPackageHash == actualPackageHash else {
            throw EvidencePackageError.packageHashMismatch(
                expected: expectedPackageHash,
                actual: actualPackageHash
            )
        }

        let text = String(decoding: sums, as: UTF8.self)
        var namedPaths = [String]()
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.count > 66 else { throw EvidencePackageError.malformedChecksumLine(line) }
            let expected = String(line.prefix(64))
            let separator = line.dropFirst(64).prefix(2)
            let path = String(line.dropFirst(66))
            guard separator == "  ", expected.count == 64, !path.isEmpty else {
                throw EvidencePackageError.malformedChecksumLine(line)
            }
            try validateRelativePath(path)
            let url = directory.appendingPathComponent(path)
            let actual = sha256(try Data(contentsOf: url))
            guard actual == expected else {
                throw EvidencePackageError.hashMismatch(path: path, expected: expected, actual: actual)
            }
            namedPaths.append(path)
        }
        guard namedPaths == (try packageFilePaths(in: directory)) else {
            throw EvidencePackageError.artifactSetMismatch
        }
        return expectedPackageHash
    }

    private static func prepareEmptyDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            let contents = try manager.contentsOfDirectory(atPath: directory.path)
            guard contents.isEmpty else {
                throw EvidencePackageError.outputDirectoryNotEmpty(directory.path)
            }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func writeDebug(
        _ scene: NeutralRenderedScene,
        suite: String,
        stem: String,
        scale: Int,
        output: URL
    ) throws {
        for overlay in scene.debugOverlays.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let path = "debug/\(suite)/\(stem)-\(overlay.rawValue)@\(scale)x.png"
            try write(scene.debugOverlays[overlay]!.pngData, relativePath: path, in: output)
        }
    }

    private static func write(_ data: Data, relativePath: String, in directory: URL) throws {
        try validateRelativePath(relativePath)
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private static func artifactRecords(in directory: URL) throws -> [EvidenceArtifact] {
        try packageFilePaths(in: directory).map { path in
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            let kind: String
            if path.hasPrefix("renders/") { kind = "core-render" }
            else if path.hasPrefix("debug/") { kind = "debug-overlay" }
            else if path.hasPrefix("contact-sheets/") { kind = "contact-sheet" }
            else if path == "metrics.json" { kind = "metrics" }
            else if path == "corpus-manifest.json" { kind = "corpus-manifest" }
            else { kind = "artifact" }
            return EvidenceArtifact(path: path, kind: kind, byteCount: data.count, sha256: sha256(data))
        }
    }

    private static func packageFilePaths(in directory: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var paths = [String]()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let root = directory.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { throw EvidencePackageError.unsafeRelativePath(path) }
            let relative = String(path.dropFirst(root.count + 1))
            if relative == "SHA256SUMS" || relative == "package-hash.txt" { continue }
            try validateRelativePath(relative)
            paths.append(relative)
        }
        return paths.sorted()
    }

    private static func validateRelativePath(_ path: String) throws {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw EvidencePackageError.unsafeRelativePath(path)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func padded(_ value: Int, width: Int) -> String {
        String(format: "%0*d", width, value)
    }

    private static func phaseCode(_ phase: Double) -> String {
        padded(Int((phase * 100).rounded()), width: 3)
    }

    private static func makeContactSheet(
        paths: [String],
        outputPath: String,
        directory: URL
    ) throws {
        let columns = min(6, max(1, paths.count))
        let rows = Int(ceil(Double(paths.count) / Double(columns)))
        let cellWidth = 132
        let cellHeight = 286
        let width = columns * cellWidth
        let height = rows * cellHeight
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw EvidencePackageError.cannotCreateContactSheet }
        context.setFillColor(gray: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (index, path) in paths.enumerated() {
            let url = directory.appendingPathComponent(path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: cellHeight - 12,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { throw EvidencePackageError.cannotDecodeImage(path) }
            let column = index % columns
            let rowFromTop = index / columns
            let row = rows - rowFromTop - 1
            let cell = CGRect(
                x: column * cellWidth + 6,
                y: row * cellHeight + 6,
                width: cellWidth - 12,
                height: cellHeight - 12
            )
            let aspect = Double(image.width) / Double(image.height)
            var destination = cell
            if aspect < Double(cell.width / cell.height) {
                destination.size.width = destination.height * aspect
                destination.origin.x += (cell.width - destination.width) / 2
            } else {
                destination.size.height = destination.width / aspect
                destination.origin.y += (cell.height - destination.height) / 2
            }
            context.draw(image, in: destination)
        }
        guard let image = context.makeImage() else { throw EvidencePackageError.cannotCreateContactSheet }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw EvidencePackageError.cannotCreateContactSheet }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EvidencePackageError.cannotCreateContactSheet }
        try write(data as Data, relativePath: outputPath, in: directory)
    }
}
