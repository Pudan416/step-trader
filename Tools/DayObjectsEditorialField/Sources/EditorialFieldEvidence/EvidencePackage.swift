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

/// Every evidence corpus is accepted only through an explicit, versioned
/// semantic contract. Future held-out corpora add a new kind and validator;
/// unknown versions fail closed rather than inheriting visible-v1 rules.
public enum EvidenceCorpusKind: String, Codable, Hashable, Sendable {
    case visibleV1 = "visible-v1"
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
    case unsupportedCorpusKind(String)
    case corpusContractMismatch(EvidenceCorpusKind)
    case invalidEvidenceManifest(String)
    case invalidMetrics(String)
    case artifactManifestMismatch
    case requiredArtifactSetMismatch
    case invalidImage(path: String, expectedWidth: Int, expectedHeight: Int)

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
        case .unsupportedCorpusKind(let version): "Unsupported evidence corpus kind: \(version)"
        case .corpusContractMismatch(let kind):
            "Corpus does not match the canonical \(kind.rawValue) semantic contract"
        case .invalidEvidenceManifest(let detail): "Invalid evidence manifest: \(detail)"
        case .invalidMetrics(let detail): "Invalid composition metrics: \(detail)"
        case .artifactManifestMismatch: "Evidence artifact records do not match package files"
        case .requiredArtifactSetMismatch: "Evidence package paths do not match required corpus coverage"
        case .invalidImage(let path, let expectedWidth, let expectedHeight):
            "Evidence image \(path) is not a \(expectedWidth)x\(expectedHeight) PNG"
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
        _ = try validatedCorpusKind(for: manifest)
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
        try verifySemanticContract(in: directory)
        return expectedPackageHash
    }

    private static func verifySemanticContract(in directory: URL) throws {
        let decoder = JSONDecoder()
        let corpusURL = directory.appendingPathComponent("corpus-manifest.json")
        let evidenceURL = directory.appendingPathComponent("manifest.json")
        let metricsURL = directory.appendingPathComponent("metrics.json")
        let corpus: CorpusManifest
        let evidence: CompositionEvidenceManifest
        let metrics: CompositionEvidenceMetrics
        do {
            corpus = try decoder.decode(CorpusManifest.self, from: Data(contentsOf: corpusURL))
            evidence = try decoder.decode(CompositionEvidenceManifest.self, from: Data(contentsOf: evidenceURL))
            metrics = try decoder.decode(CompositionEvidenceMetrics.self, from: Data(contentsOf: metricsURL))
        } catch {
            throw EvidencePackageError.invalidEvidenceManifest(error.localizedDescription)
        }

        let kind = try validatedCorpusKind(for: corpus)
        guard evidence.version == "composition-evidence-v1",
              evidence.corpusVersion == kind.rawValue,
              evidence.corpusVersion == corpus.version,
              evidence.specificationCommit == corpus.specificationCommit,
              evidence.rendererVersion == NeutralRenderer.version,
              evidence.colorSpace == "sRGB",
              evidence.viewport.widthPoints == 393,
              evidence.viewport.heightPoints == 852,
              evidence.viewport.scale > 0,
              evidence.viewport.tileCrop == "centered-square-from-phone-canvas",
              !evidence.sourceCommit.isEmpty
        else {
            throw EvidencePackageError.invalidEvidenceManifest("authority or renderer metadata mismatch")
        }

        let coverage = compositionCoverage(for: corpus)
        let expectedFrames = coverage.breadth + coverage.continuity
        guard evidence.coreImageCount == coverage.coreImageCount,
              evidence.frames == expectedFrames
        else {
            throw EvidencePackageError.invalidEvidenceManifest("frame coverage does not match canonical corpus")
        }

        let overlays = try validatedOverlays(evidence.overlays)
        let expectedKinds = expectedArtifactKinds(
            coverage: coverage,
            scale: evidence.viewport.scale,
            overlays: overlays
        )
        let recordedPaths = evidence.artifacts.map(\.path)
        guard recordedPaths == recordedPaths.sorted(),
              Set(recordedPaths).count == recordedPaths.count,
              Dictionary(uniqueKeysWithValues: evidence.artifacts.map { ($0.path, $0.kind) }) == expectedKinds
        else {
            throw EvidencePackageError.requiredArtifactSetMismatch
        }

        let actualArtifacts = try artifactRecords(in: directory, excluding: ["manifest.json"])
        guard evidence.artifacts == actualArtifacts else {
            throw EvidencePackageError.artifactManifestMismatch
        }
        try validateMetrics(metrics, corpus: corpus, scale: evidence.viewport.scale)
        try validateImageFiles(expectedKinds: expectedKinds, scale: evidence.viewport.scale, directory: directory)
    }

    private static func validatedOverlays(_ values: [String]) throws -> Set<NeutralOverlay> {
        var overlays = Set<NeutralOverlay>()
        for value in values {
            guard let overlay = NeutralOverlay(rawValue: value), overlays.insert(overlay).inserted else {
                throw EvidencePackageError.invalidEvidenceManifest("unknown or duplicate overlay \(value)")
            }
        }
        guard values == values.sorted() else {
            throw EvidencePackageError.invalidEvidenceManifest("overlay list is not canonical")
        }
        return overlays
    }

    private static func expectedArtifactKinds(
        coverage: CompositionEvidenceCoverage,
        scale: Int,
        overlays: Set<NeutralOverlay>
    ) -> [String: String] {
        let frames = coverage.breadth + coverage.continuity
        var result = [
            "contact-sheets/breadth.png": "contact-sheet",
            "contact-sheets/continuity.png": "contact-sheet",
            "corpus-manifest.json": "corpus-manifest",
            "metrics.json": "metrics",
        ]
        for frame in frames {
            result[coreRenderPath(frame, scale: scale)] = "core-render"
            guard frame.view == .fullScreen else { continue }
            let stem = renderStem(frame)
            for overlay in overlays {
                result["debug/\(frame.suite)/\(stem)-\(overlay.rawValue)@\(scale)x.png"] = "debug-overlay"
            }
        }
        return result
    }

    private static func coreRenderPath(_ frame: CompositionEvidenceFrame, scale: Int) -> String {
        let suffix = frame.view == .fullScreen ? "full" : "tile"
        return "renders/\(frame.suite)/\(renderStem(frame))-\(suffix)@\(scale)x.png"
    }

    private static func renderStem(_ frame: CompositionEvidenceFrame) -> String {
        if frame.suite == "breadth" {
            return "breadth-\(padded(frame.fixtureIndex, width: 2))-phase-\(phaseCode(frame.phase))"
        }
        return "continuity-stage-\(padded(frame.stage ?? -1, width: 2))-count-\(padded(frame.actorCount, width: 2))-phase-\(phaseCode(frame.phase))"
    }

    private static func validateMetrics(
        _ metrics: CompositionEvidenceMetrics,
        corpus: CorpusManifest,
        scale: Int
    ) throws {
        let breadthCount = corpus.breadth.count * corpus.phases.count
        let continuityCount = corpus.continuity.stages.count * corpus.phases.count
        guard metrics.version == "composition-metrics-v1",
              metrics.breadthSceneCount == breadthCount,
              metrics.continuitySceneCount == continuityCount,
              metrics.coreImageCount == (breadthCount + continuityCount) * EvidenceView.allCases.count,
              metrics.frames.count == breadthCount + continuityCount
        else {
            throw EvidencePackageError.invalidMetrics("summary counts do not match canonical corpus")
        }

        var index = 0
        for fixture in corpus.breadth {
            for phase in corpus.phases {
                try validateMetricFrame(
                    metrics.frames[index],
                    suite: fixture.suite,
                    fixtureIndex: fixture.index,
                    stage: nil,
                    seed: fixture.seed,
                    phase: phase,
                    background: fixture.background,
                    sleep: fixture.sleep,
                    steps: fixture.steps,
                    reduceMotion: fixture.reduceMotion,
                    eventIDs: fixture.eventIDs,
                    scale: scale
                )
                index += 1
            }
        }
        let continuity = corpus.continuity
        for stage in continuity.stages {
            for phase in corpus.phases {
                try validateMetricFrame(
                    metrics.frames[index],
                    suite: continuity.suite,
                    fixtureIndex: continuity.index,
                    stage: stage.stage,
                    seed: continuity.seed,
                    phase: phase,
                    background: continuity.background,
                    sleep: continuity.sleep,
                    steps: continuity.steps,
                    reduceMotion: continuity.reduceMotion,
                    eventIDs: stage.eventIDs,
                    scale: scale
                )
                index += 1
            }
        }
    }

    private static func validateMetricFrame(
        _ actual: CompositionFrameMetrics,
        suite: String,
        fixtureIndex: Int,
        stage: Int?,
        seed: UInt64,
        phase: Double,
        background: BackgroundCondition,
        sleep: SleepCondition,
        steps: StepCondition,
        reduceMotion: Bool,
        eventIDs: [String],
        scale: Int
    ) throws {
        let recipe = CompositionPlanner.make(daySeed: seed, eventIDs: eventIDs, viewport: .phone)
        let tileSide = 393 * scale
        let expectedCrop = PixelRect(
            x: 0,
            y: (852 * scale - tileSide) / 2,
            width: tileSide,
            height: tileSide
        )
        let expectedActors = recipe.actors.enumerated().map { actorIndex, actor in
            NeutralActorEvidence(
                eventID: actor.eventID,
                label: String(format: "A%02d", actorIndex + 1),
                position: actor.position,
                diameter: actor.diameter,
                diameterPixels: actor.diameter * Double(tileSide),
                depth: actor.depth,
                luminance: 0.22 + min(max(actor.depth, 0), 1) * 0.58,
                localBlur: actor.localBlur,
                localBlurPixels: actor.localBlur * Double(tileSide),
                cropFraction: recipe.cropFraction(of: actor),
                drawOrder: actor.drawOrder,
                labelInkPixelCount: max(1, 3 * scale * 8)
            )
        }
        guard actual.suite == suite,
              actual.fixtureIndex == fixtureIndex,
              actual.stage == stage,
              actual.seed == seed,
              actual.phase == phase,
              actual.background == background,
              actual.sleep == sleep,
              actual.steps == steps,
              actual.reduceMotion == reduceMotion,
              actual.grammar == recipe.grammar,
              actual.tileCrop == expectedCrop,
              actual.actors == expectedActors
        else {
            throw EvidencePackageError.invalidMetrics("frame \(suite)/\(fixtureIndex)/\(stage.map(String.init) ?? "-")/\(phase) mismatch")
        }
    }

    private static func validateImageFiles(
        expectedKinds: [String: String],
        scale: Int,
        directory: URL
    ) throws {
        for (path, kind) in expectedKinds where ["core-render", "debug-overlay", "contact-sheet"].contains(kind) {
            let expected: (Int, Int)
            if kind == "contact-sheet" {
                expected = path.contains("breadth") ? (792, 2_288) : (792, 1_430)
            } else if path.contains("-tile@") {
                expected = (393 * scale, 393 * scale)
            } else {
                expected = (393 * scale, 852 * scale)
            }
            let url = directory.appendingPathComponent(path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetType(source) as String? == UTType.png.identifier,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expected.0,
                  (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expected.1
            else {
                throw EvidencePackageError.invalidImage(
                    path: path,
                    expectedWidth: expected.0,
                    expectedHeight: expected.1
                )
            }
        }
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

    private static func validatedCorpusKind(for manifest: CorpusManifest) throws -> EvidenceCorpusKind {
        guard let kind = EvidenceCorpusKind(rawValue: manifest.version) else {
            throw EvidencePackageError.unsupportedCorpusKind(manifest.version)
        }
        switch kind {
        case .visibleV1:
            let expected = try CorpusManifest.visibleV1().canonicalJSON()
            let actual = try manifest.canonicalJSON()
            guard actual == expected else {
                throw EvidencePackageError.corpusContractMismatch(kind)
            }
        }
        return kind
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

    private static func artifactRecords(
        in directory: URL,
        excluding excludedPaths: Set<String> = []
    ) throws -> [EvidenceArtifact] {
        try packageFilePaths(in: directory).filter { !excludedPaths.contains($0) }.map { path in
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
