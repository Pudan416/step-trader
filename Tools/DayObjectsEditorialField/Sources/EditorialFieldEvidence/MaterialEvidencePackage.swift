import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import EditorialFieldCore
import EditorialFieldRender

public struct MaterialAtlasFixture: Codable, Equatable, Sendable {
    public let index: Int
    public let family: MaterialFamily
    public let requestedColorCount: Int
    public let background: BackgroundCondition
    public let layoutFixtureIndex: Int
    public let seed: UInt64
    public let actorCount: Int
}

public struct MaterialAtlasCoverage: Equatable, Sendable {
    public let fixtures: [MaterialAtlasFixture]
    public var coreImageCount: Int { fixtures.count * EvidenceView.allCases.count }
}

public struct FrozenCompositionRecipeFixture: Codable, Equatable, Sendable {
    public let fixtureIndex: Int
    public let recipe: SceneRecipe

    public init(fixtureIndex: Int, recipe: SceneRecipe) {
        self.fixtureIndex = fixtureIndex
        self.recipe = recipe
    }
}

/// Canonical SceneRecipe bytes projected from, and cryptographically tied to,
/// the approved neutral evidence package. The embedded source bytes let a
/// verifier prove the original approval -> SHA256SUMS -> metrics -> recipe
/// geometry chain without consulting the current CompositionPlanner.
public struct FrozenCompositionRecipeArchive: Codable, Equatable, Sendable {
    public let version: String
    public let approvedEvidenceChecksumsZlib: Data
    public let approvedMetricsZlib: Data
    public let fixtures: [FrozenCompositionRecipeFixture]

    public init(
        version: String = "composition-recipe-archive-v2",
        approvedEvidenceChecksums: Data,
        approvedMetrics: Data,
        fixtures: [FrozenCompositionRecipeFixture]
    ) throws {
        self.version = version
        self.approvedEvidenceChecksumsZlib = try (approvedEvidenceChecksums as NSData)
            .compressed(using: .zlib) as Data
        self.approvedMetricsZlib = try (approvedMetrics as NSData)
            .compressed(using: .zlib) as Data
        self.fixtures = fixtures
    }
}

public struct MaterialSampleMeasurement: Codable, Equatable, Sendable {
    public let role: String
    public let point: CompositionPoint
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
}

public struct MaterialActorMetrics: Codable, Equatable, Sendable {
    public let eventID: String
    public let family: MaterialFamily
    public let mutation: MaterialMutation?
    public let colors: [MaterialColor]
    public let fields: [RadialField]
    public let baseOpacity: Double
    public let edgeSoftness: Double
    public let contourWidth: Double
    public let contourCount: Int
    public let counterformRadius: Double?
    public let counterformSoftness: Double
    public let samples: [MaterialSampleMeasurement]
}

public struct MaterialFixtureMetrics: Codable, Equatable, Sendable {
    public let fixture: MaterialAtlasFixture
    public let grammar: EditorialGrammar
    public let compositionRecipeSHA256: String
    public let tileCrop: PixelRect
    public let actors: [MaterialActorMetrics]
}

public struct MaterialEvidenceMetrics: Codable, Equatable, Sendable {
    public let version: String
    public let fixtureCount: Int
    public let coreImageCount: Int
    public let compositionApprovalSHA256: String
    public let compositionRecipeArchiveSHA256: String
    public let fixtures: [MaterialFixtureMetrics]
}

public struct MaterialEvidenceManifest: Codable, Equatable, Sendable {
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
    public let compositionApprovalSHA256: String
    public let compositionRecipeArchiveSHA256: String
    public let fixtureCount: Int
    public let coreImageCount: Int
    public let fixtures: [MaterialAtlasFixture]
    public let artifacts: [EvidenceArtifact]
}

public struct GeneratedMaterialEvidence: Sendable {
    public let manifest: MaterialEvidenceManifest
    public let packageHash: String
    public let outputDirectory: URL
}

public enum MaterialEvidenceError: Error, LocalizedError {
    case nonCanonicalCorpus
    case invalidCompositionApproval(String)
    case invalidSourceCommit(String)
    case outputDirectoryNotEmpty(String)
    case cannotCreateContactSheet
    case cannotDecodeImage(String)
    case invalidPackage(String)
    case packageHashMismatch(expected: String, actual: String)
    case artifactHashMismatch(String)
    case tileCropMismatch(String)
    case renderPixelMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .nonCanonicalCorpus: "Material atlas requires the canonical visible-v1 corpus"
        case .invalidCompositionApproval(let detail): "Invalid frozen composition approval: \(detail)"
        case .invalidSourceCommit(let value): "Source commit must be a full lowercase Git object ID, got \(value)"
        case .outputDirectoryNotEmpty(let path): "Material output directory is not empty: \(path)"
        case .cannotCreateContactSheet: "Cannot create material contact sheet"
        case .cannotDecodeImage(let path): "Cannot decode material image: \(path)"
        case .invalidPackage(let detail): "Invalid material evidence package: \(detail)"
        case .packageHashMismatch(let expected, let actual):
            "Material package hash mismatch: expected \(expected), got \(actual)"
        case .artifactHashMismatch(let path): "Material artifact hash mismatch: \(path)"
        case .tileCropMismatch(let path): "Material tile is not the exact full-screen crop: \(path)"
        case .renderPixelMismatch(let path): "Material render pixels do not match the canonical recipe: \(path)"
        }
    }
}

public enum MaterialEvidencePackage {
    private struct CompositionApprovalAuthority: Decodable {
        let scope: String
        let corpusVersion: String
        let evidencePackageSHA256: String
        let frozen: Bool
    }

    private struct MaterialPixelProbe {
        let x: Int
        let y: Int
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        func colorDistance(to color: MaterialColor) -> Double {
            hypot(hypot(red - color.red, green - color.green), blue - color.blue)
        }

        func colorDistance(to other: MaterialPixelProbe) -> Double {
            hypot(hypot(red - other.red, green - other.green), blue - other.blue)
        }
    }

    public static func coverage(for manifest: CorpusManifest) -> MaterialAtlasCoverage {
        let requiredBackgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        var fixtures = [MaterialAtlasFixture]()
        for (familyIndex, family) in MaterialFamily.allCases.enumerated() {
            for colorCount in 1...3 {
                let index = familyIndex * 3 + colorCount - 1
                let layoutIndex = index % manifest.breadth.count
                let layout = manifest.breadth[layoutIndex]
                fixtures.append(MaterialAtlasFixture(
                    index: index,
                    family: family,
                    requestedColorCount: colorCount,
                    background: requiredBackgrounds[(familyIndex + colorCount - 1) % requiredBackgrounds.count],
                    layoutFixtureIndex: layoutIndex,
                    seed: layout.seed,
                    actorCount: layout.actorCount
                ))
            }
        }
        return MaterialAtlasCoverage(fixtures: fixtures)
    }

    public static func generate(
        manifest: CorpusManifest,
        compositionApprovalData: Data,
        compositionRecipeArchiveData: Data,
        sourceCommit: String,
        outputDirectory: URL,
        scale: Int = 3
    ) throws -> GeneratedMaterialEvidence {
        try validateCorpus(manifest)
        try validateCompositionApproval(compositionApprovalData, corpusVersion: manifest.version)
        let frozenRecipes = try validatedFrozenRecipes(
            archiveData: compositionRecipeArchiveData,
            approvalData: compositionApprovalData,
            manifest: manifest
        )
        try validateSourceCommit(sourceCommit)
        guard scale > 0 else { throw MaterialEvidenceError.invalidPackage("scale must be positive") }
        try prepareEmptyDirectory(outputDirectory)

        let renderer = MaterialRenderer()
        let atlasCoverage = coverage(for: manifest)
        let approvalHash = sha256(compositionApprovalData)
        let recipeArchiveHash = sha256(compositionRecipeArchiveData)
        var fixtureMetrics = [MaterialFixtureMetrics]()
        var atlasFullPaths = [String]()
        var structuralFullPaths = [String]()

        try write(compositionApprovalData, path: "composition-approved.json", in: outputDirectory)
        try write(compositionRecipeArchiveData, path: "composition-recipes.json", in: outputDirectory)
        try write(manifest.canonicalJSON(), path: "corpus-manifest.json", in: outputDirectory)

        for fixture in atlasCoverage.fixtures {
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            guard let recipe = frozenRecipes[fixture.layoutFixtureIndex] else {
                throw MaterialEvidenceError.invalidCompositionApproval(
                    "missing frozen recipe for breadth fixture \(fixture.layoutFixtureIndex)"
                )
            }
            let recipeBytes = try canonicalJSON(recipe)
            let dna = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: fixture.family,
                requestedColorCount: fixture.requestedColorCount
            )
            let rendered = try renderer.render(
                recipe: recipe,
                material: dna,
                background: fixture.background,
                configuration: .init(scale: scale)
            )
            let stem = renderStem(fixture)
            let fullPath = "renders/\(fixture.family.rawValue)/\(stem)-full@\(scale)x.png"
            let tilePath = "renders/\(fixture.family.rawValue)/\(stem)-tile@\(scale)x.png"
            try write(rendered.fullScreen.pngData, path: fullPath, in: outputDirectory)
            try write(rendered.calendarTile.pngData, path: tilePath, in: outputDirectory)
            atlasFullPaths.append(fullPath)
            if fixture.family == .outline || fixture.family == .counterform {
                structuralFullPaths.append(fullPath)
            }

            let actorMetrics = try actorMetrics(for: dna, renderer: renderer)
            fixtureMetrics.append(MaterialFixtureMetrics(
                fixture: fixture,
                grammar: recipe.grammar,
                compositionRecipeSHA256: sha256(recipeBytes),
                tileCrop: rendered.tileCrop,
                actors: actorMetrics
            ))
        }

        let metrics = MaterialEvidenceMetrics(
            version: "material-metrics-v2",
            fixtureCount: atlasCoverage.fixtures.count,
            coreImageCount: atlasCoverage.coreImageCount,
            compositionApprovalSHA256: approvalHash,
            compositionRecipeArchiveSHA256: recipeArchiveHash,
            fixtures: fixtureMetrics
        )
        try write(canonicalJSON(metrics), path: "metrics.json", in: outputDirectory)
        try makeContactSheet(
            paths: atlasFullPaths,
            outputPath: "contact-sheets/material-atlas.png",
            directory: outputDirectory
        )
        try makeContactSheet(
            paths: structuralFullPaths,
            outputPath: "contact-sheets/outline-counterform.png",
            directory: outputDirectory
        )

        let artifacts = try artifactRecords(in: outputDirectory)
        let packageManifest = MaterialEvidenceManifest(
            version: "material-evidence-v2",
            sourceCommit: sourceCommit,
            rendererVersion: MaterialRenderer.version,
            toolchain: "Swift 6 / Swift Package Manager",
            device: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            viewport: EvidenceViewportMetadata(
                widthPoints: 393,
                heightPoints: 852,
                scale: scale,
                tileCrop: "centered-square-from-phone-canvas"
            ),
            colorSpace: "sRGB",
            corpusVersion: manifest.version,
            specificationCommit: manifest.specificationCommit,
            compositionApprovalSHA256: approvalHash,
            compositionRecipeArchiveSHA256: recipeArchiveHash,
            fixtureCount: atlasCoverage.fixtures.count,
            coreImageCount: atlasCoverage.coreImageCount,
            fixtures: atlasCoverage.fixtures,
            artifacts: artifacts
        )
        try write(canonicalJSON(packageManifest), path: "manifest.json", in: outputDirectory)
        let packageHash = try EvidencePackage.seal(directory: outputDirectory)
        return GeneratedMaterialEvidence(
            manifest: packageManifest,
            packageHash: packageHash,
            outputDirectory: outputDirectory
        )
    }

    @discardableResult
    public static func verify(
        directory: URL,
        expectedSourceCommit: String,
        expectedCompositionApprovalData: Data,
        expectedCompositionRecipeArchiveData: Data
    ) throws -> String {
        try validateSourceCommit(expectedSourceCommit)
        let packageHash = try verifySealedArtifacts(in: directory)
        let actualApproval = try Data(contentsOf: directory.appendingPathComponent("composition-approved.json"))
        guard actualApproval == expectedCompositionApprovalData else {
            throw MaterialEvidenceError.invalidPackage("composition approval bytes changed")
        }
        let actualRecipeArchive = try Data(
            contentsOf: directory.appendingPathComponent("composition-recipes.json")
        )
        guard actualRecipeArchive == expectedCompositionRecipeArchiveData else {
            throw MaterialEvidenceError.invalidPackage("composition recipe archive bytes changed")
        }

        let decoder = JSONDecoder()
        let corpus = try decoder.decode(
            CorpusManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("corpus-manifest.json"))
        )
        try validateCorpus(corpus)
        try validateCompositionApproval(actualApproval, corpusVersion: corpus.version)
        let frozenRecipes = try validatedFrozenRecipes(
            archiveData: actualRecipeArchive,
            approvalData: actualApproval,
            manifest: corpus
        )
        let manifest = try decoder.decode(
            MaterialEvidenceManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        let metrics = try decoder.decode(
            MaterialEvidenceMetrics.self,
            from: Data(contentsOf: directory.appendingPathComponent("metrics.json"))
        )
        let expectedCoverage = coverage(for: corpus)
        guard manifest.version == "material-evidence-v2",
              manifest.sourceCommit == expectedSourceCommit,
              manifest.rendererVersion == MaterialRenderer.version,
              manifest.toolchain == "Swift 6 / Swift Package Manager",
              !manifest.device.isEmpty,
              !manifest.operatingSystem.isEmpty,
              manifest.viewport.widthPoints == 393,
              manifest.viewport.heightPoints == 852,
              manifest.viewport.scale > 0,
              manifest.viewport.tileCrop == "centered-square-from-phone-canvas",
              manifest.colorSpace == "sRGB",
              manifest.corpusVersion == corpus.version,
              manifest.specificationCommit == corpus.specificationCommit,
              manifest.compositionApprovalSHA256 == sha256(actualApproval),
              manifest.compositionRecipeArchiveSHA256 == sha256(actualRecipeArchive),
              manifest.fixtureCount == expectedCoverage.fixtures.count,
              manifest.coreImageCount == expectedCoverage.coreImageCount,
              manifest.fixtures == expectedCoverage.fixtures
        else {
            throw MaterialEvidenceError.invalidPackage("manifest authority or coverage mismatch")
        }
        let expectedFixtureMetrics = try expectedCoverage.fixtures.map { fixture in
            try expectedMetrics(
                for: fixture,
                manifest: corpus,
                frozenRecipes: frozenRecipes,
                scale: manifest.viewport.scale,
                renderer: MaterialRenderer()
            )
        }
        guard metrics.version == "material-metrics-v2",
              metrics.fixtureCount == expectedCoverage.fixtures.count,
              metrics.coreImageCount == expectedCoverage.coreImageCount,
              metrics.compositionApprovalSHA256 == manifest.compositionApprovalSHA256,
              metrics.compositionRecipeArchiveSHA256 == manifest.compositionRecipeArchiveSHA256,
              metrics.fixtures == expectedFixtureMetrics
        else {
            throw MaterialEvidenceError.invalidPackage("metrics coverage or descriptors mismatch")
        }

        let expectedPaths = expectedArtifactPaths(coverage: expectedCoverage, scale: manifest.viewport.scale)
        let actualArtifacts = try artifactRecords(in: directory, excluding: ["manifest.json"])
        guard Set(manifest.artifacts.map(\.path)) == expectedPaths,
              manifest.artifacts == actualArtifacts
        else {
            throw MaterialEvidenceError.invalidPackage("artifact manifest mismatch")
        }
        try validateImagesAndCrops(
            coverage: expectedCoverage,
            manifest: corpus,
            frozenRecipes: frozenRecipes,
            scale: manifest.viewport.scale,
            directory: directory
        )
        return packageHash
    }

    private static func renderedSamples(
        for actor: ActorMaterialRecipe,
        renderer: MaterialRenderer
    ) throws -> [MaterialSampleMeasurement] {
        let size = 96
        let rendered = try renderer.renderActor(actor, pixelSize: size)
        let image = try decodedPNG(rendered.pngData, path: actor.eventID)
        let rgba = try normalizedRGBA(image)
        var probes = [MaterialPixelProbe]()
        probes.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                let alphaByte = Double(rgba[offset + 3])
                let divisor = max(1, alphaByte)
                probes.append(MaterialPixelProbe(
                    x: x,
                    y: y,
                    red: Double(rgba[offset]) / divisor,
                    green: Double(rgba[offset + 1]) / divisor,
                    blue: Double(rgba[offset + 2]) / divisor,
                    alpha: alphaByte / 255
                ))
            }
        }
        let maximumAlpha = probes.map(\.alpha).max() ?? 0
        let visibleThreshold = max(0.04, maximumAlpha * 0.18)
        let visible = probes.filter { $0.alpha >= visibleThreshold }
        guard !visible.isEmpty else {
            throw MaterialEvidenceError.invalidPackage("actor \(actor.eventID) has no sampleable pixels")
        }

        var selected = [(role: String, probe: MaterialPixelProbe)]()
        var selectedCoordinates = Set<String>()
        func append(_ role: String, _ probe: MaterialPixelProbe?) {
            guard let probe else { return }
            let key = "\(probe.x):\(probe.y)"
            guard selectedCoordinates.insert(key).inserted else { return }
            selected.append((role, probe))
        }

        let center = probes[(size / 2) * size + size / 2]
        append("center", center)
        append("visible-peak", visible.max { $0.alpha < $1.alpha })

        if actor.family == .outline || actor.family == .counterform {
            let centerCoordinate = Double(size - 1) * 0.5
            func radius(_ probe: MaterialPixelProbe) -> Double {
                hypot(Double(probe.x) - centerCoordinate, Double(probe.y) - centerCoordinate)
            }
            append("inner-visible-band", visible.min { radius($0) < radius($1) })
            append("outer-visible-band", visible.max { radius($0) < radius($1) })
        }

        var paletteProbes = [MaterialPixelProbe]()
        for (index, color) in actor.colors.enumerated() {
            let closest = visible.min { $0.colorDistance(to: color) < $1.colorDistance(to: color) }
            append("palette-\(index)", closest)
            if let closest { paletteProbes.append(closest) }
        }
        if let first = paletteProbes.first {
            append(
                "color-extreme",
                visible.max { $0.colorDistance(to: first) < $1.colorDistance(to: first) }
            )
        }

        for (index, field) in actor.fields.enumerated() {
            let x = min(size - 1, max(0, Int((field.focus.x * Double(size)).rounded(.down))))
            let y = min(size - 1, max(0, Int((field.focus.y * Double(size)).rounded(.down))))
            let probe = probes[y * size + x]
            if probe.alpha >= visibleThreshold {
                append("field-focus-\(index)", probe)
            }
        }

        return selected.map { role, probe in
            return MaterialSampleMeasurement(
                role: role,
                point: CompositionPoint(
                    x: (Double(probe.x) + 0.5) / Double(size),
                    y: (Double(probe.y) + 0.5) / Double(size)
                ),
                red: probe.red,
                green: probe.green,
                blue: probe.blue,
                alpha: probe.alpha
            )
        }
    }

    private static func actorMetrics(
        for dna: DailyMaterialDNA,
        renderer: MaterialRenderer
    ) throws -> [MaterialActorMetrics] {
        try dna.actors.map { actor in
            MaterialActorMetrics(
                eventID: actor.eventID,
                family: actor.family,
                mutation: actor.mutation,
                colors: actor.colors,
                fields: actor.fields,
                baseOpacity: actor.baseOpacity,
                edgeSoftness: actor.edgeSoftness,
                contourWidth: actor.contourWidth,
                contourCount: actor.contourCount,
                counterformRadius: actor.counterformRadius,
                counterformSoftness: actor.counterformSoftness,
                samples: try renderedSamples(for: actor, renderer: renderer)
            )
        }
    }

    private static func expectedMetrics(
        for fixture: MaterialAtlasFixture,
        manifest: CorpusManifest,
        frozenRecipes: [Int: SceneRecipe],
        scale: Int,
        renderer: MaterialRenderer
    ) throws -> MaterialFixtureMetrics {
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        guard let recipe = frozenRecipes[fixture.layoutFixtureIndex] else {
            throw MaterialEvidenceError.invalidCompositionApproval(
                "missing frozen recipe for breadth fixture \(fixture.layoutFixtureIndex)"
            )
        }
        let dna = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: fixture.family,
            requestedColorCount: fixture.requestedColorCount
        )
        let side = 393 * scale
        return MaterialFixtureMetrics(
            fixture: fixture,
            grammar: recipe.grammar,
            compositionRecipeSHA256: sha256(try canonicalJSON(recipe)),
            tileCrop: PixelRect(
                x: 0,
                y: (852 * scale - side) / 2,
                width: side,
                height: side
            ),
            actors: try actorMetrics(for: dna, renderer: renderer)
        )
    }

    private static func validateCorpus(_ manifest: CorpusManifest) throws {
        guard try manifest.canonicalJSON() == CorpusManifest.visibleV1().canonicalJSON() else {
            throw MaterialEvidenceError.nonCanonicalCorpus
        }
    }

    private static func validateCompositionApproval(_ data: Data, corpusVersion: String) throws {
        let approval: CompositionApprovalAuthority
        do {
            approval = try JSONDecoder().decode(CompositionApprovalAuthority.self, from: data)
        } catch {
            throw MaterialEvidenceError.invalidCompositionApproval(error.localizedDescription)
        }
        guard approval.scope == "neutral-composition-only",
              approval.corpusVersion == corpusVersion,
              approval.frozen,
              isSHA256(approval.evidencePackageSHA256)
        else {
            throw MaterialEvidenceError.invalidCompositionApproval("scope, corpus, frozen flag, or evidence hash mismatch")
        }
    }

    private static func validatedFrozenRecipes(
        archiveData: Data,
        approvalData: Data,
        manifest: CorpusManifest
    ) throws -> [Int: SceneRecipe] {
        let approval: CompositionApprovalAuthority
        let archive: FrozenCompositionRecipeArchive
        let sourceMetrics: CompositionEvidenceMetrics
        let approvedEvidenceChecksums: Data
        let approvedMetrics: Data
        do {
            approval = try JSONDecoder().decode(CompositionApprovalAuthority.self, from: approvalData)
            archive = try JSONDecoder().decode(FrozenCompositionRecipeArchive.self, from: archiveData)
            approvedEvidenceChecksums = try (archive.approvedEvidenceChecksumsZlib as NSData)
                .decompressed(using: .zlib) as Data
            approvedMetrics = try (archive.approvedMetricsZlib as NSData)
                .decompressed(using: .zlib) as Data
            sourceMetrics = try JSONDecoder().decode(
                CompositionEvidenceMetrics.self,
                from: approvedMetrics
            )
        } catch {
            throw MaterialEvidenceError.invalidCompositionApproval(
                "cannot decode frozen recipe authority: \(error.localizedDescription)"
            )
        }
        guard archive.version == "composition-recipe-archive-v2",
              sha256(approvedEvidenceChecksums) == approval.evidencePackageSHA256,
              checksum(
                for: "metrics.json",
                in: approvedEvidenceChecksums
              ) == sha256(approvedMetrics),
              sourceMetrics.version == "composition-metrics-v1",
              archive.fixtures.count == manifest.breadth.count,
              archive.fixtures.map(\.fixtureIndex) == manifest.breadth.map(\.index)
        else {
            throw MaterialEvidenceError.invalidCompositionApproval(
                "recipe archive is not bound to the approved evidence metrics"
            )
        }

        var result = [Int: SceneRecipe]()
        for (layout, frozen) in zip(manifest.breadth, archive.fixtures) {
            let sourceFrames = sourceMetrics.frames.filter {
                $0.suite == layout.suite && $0.fixtureIndex == layout.index && $0.stage == nil
            }
            guard sourceFrames.count == manifest.phases.count,
                  sourceFrames.map(\.phase) == manifest.phases,
                  frozen.fixtureIndex == layout.index
            else {
                throw MaterialEvidenceError.invalidCompositionApproval(
                    "approved metrics coverage mismatch for breadth fixture \(layout.index)"
                )
            }
            for frame in sourceFrames {
                try validateFrozenRecipe(frozen.recipe, layout: layout, sourceFrame: frame)
            }
            result[layout.index] = frozen.recipe
        }
        return result
    }

    private static func validateFrozenRecipe(
        _ recipe: SceneRecipe,
        layout: CorpusFixture,
        sourceFrame: CompositionFrameMetrics
    ) throws {
        guard recipe.daySeed == layout.seed,
              recipe.daySeed == sourceFrame.seed,
              recipe.grammar == sourceFrame.grammar,
              recipe.viewport == .phone,
              recipe.actors.count == layout.actorCount,
              sourceFrame.actors.count == recipe.actors.count,
              Set(recipe.actors.map(\.eventID)) == Set(layout.eventIDs)
        else {
            throw MaterialEvidenceError.invalidCompositionApproval(
                "frozen recipe identity mismatch for breadth fixture \(layout.index)"
            )
        }
        for (actor, sourceActor) in zip(recipe.actors, sourceFrame.actors) {
            let finite = [
                actor.position.x,
                actor.position.y,
                actor.diameter,
                actor.depth,
                actor.localBlur,
                actor.cropAllowance,
            ].allSatisfy(\.isFinite)
            let cropFraction = recipe.cropFraction(of: actor)
            guard finite,
                  actor.eventID == sourceActor.eventID,
                  actor.position == sourceActor.position,
                  actor.diameter == sourceActor.diameter,
                  actor.depth == sourceActor.depth,
                  actor.localBlur == sourceActor.localBlur,
                  actor.drawOrder == sourceActor.drawOrder,
                  abs(cropFraction - sourceActor.cropFraction) < 0.000_000_000_001,
                  (0...0.45).contains(actor.cropAllowance),
                  cropFraction <= actor.cropAllowance + 0.07
            else {
                throw MaterialEvidenceError.invalidCompositionApproval(
                    "frozen recipe geometry mismatch for \(sourceActor.eventID)"
                )
            }
        }
    }

    private static func checksum(for path: String, in sums: Data) -> String? {
        let text = String(decoding: sums, as: UTF8.self)
        for substring in text.split(whereSeparator: \.isNewline) {
            let line = String(substring)
            guard line.count > 66, String(line.dropFirst(66)) == path else { continue }
            return String(line.prefix(64))
        }
        return nil
    }

    private static func validateSourceCommit(_ value: String) throws {
        let count = value.utf8.count
        let isHex = value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
        guard (count == 40 || count == 64), isHex else {
            throw MaterialEvidenceError.invalidSourceCommit(value)
        }
    }

    private static func prepareEmptyDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
                throw MaterialEvidenceError.outputDirectoryNotEmpty(directory.path)
            }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func expectedArtifactPaths(
        coverage: MaterialAtlasCoverage,
        scale: Int
    ) -> Set<String> {
        var paths: Set<String> = [
            "composition-approved.json",
            "composition-recipes.json",
            "contact-sheets/material-atlas.png",
            "contact-sheets/outline-counterform.png",
            "corpus-manifest.json",
            "metrics.json",
        ]
        for fixture in coverage.fixtures {
            let prefix = "renders/\(fixture.family.rawValue)/\(renderStem(fixture))"
            paths.insert("\(prefix)-full@\(scale)x.png")
            paths.insert("\(prefix)-tile@\(scale)x.png")
        }
        return paths
    }

    private static func validateImagesAndCrops(
        coverage: MaterialAtlasCoverage,
        manifest: CorpusManifest,
        frozenRecipes: [Int: SceneRecipe],
        scale: Int,
        directory: URL
    ) throws {
        let fullWidth = 393 * scale
        let fullHeight = 852 * scale
        let cropRect = CGRect(
            x: 0,
            y: (fullHeight - fullWidth) / 2,
            width: fullWidth,
            height: fullWidth
        )
        let renderer = MaterialRenderer()
        for fixture in coverage.fixtures {
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            guard let recipe = frozenRecipes[fixture.layoutFixtureIndex] else {
                throw MaterialEvidenceError.invalidCompositionApproval(
                    "missing frozen recipe for breadth fixture \(fixture.layoutFixtureIndex)"
                )
            }
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: fixture.family,
                requestedColorCount: fixture.requestedColorCount
            )
            let expected = try renderer.render(
                recipe: recipe,
                material: material,
                background: fixture.background,
                configuration: .init(scale: scale)
            )
            let prefix = "renders/\(fixture.family.rawValue)/\(renderStem(fixture))"
            let fullPath = "\(prefix)-full@\(scale)x.png"
            let tilePath = "\(prefix)-tile@\(scale)x.png"
            let full = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(fullPath)),
                path: fullPath
            )
            let tile = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(tilePath)),
                path: tilePath
            )
            let expectedFull = try decodedPNG(expected.fullScreen.pngData, path: "expected:\(fullPath)")
            let expectedTileImage = try decodedPNG(expected.calendarTile.pngData, path: "expected:\(tilePath)")
            guard full.width == fullWidth,
                  full.height == fullHeight,
                  tile.width == fullWidth,
                  tile.height == fullWidth
            else {
                throw MaterialEvidenceError.tileCropMismatch(tilePath)
            }
            guard try normalizedRGBA(full) == normalizedRGBA(expectedFull),
                  try normalizedRGBA(tile) == normalizedRGBA(expectedTileImage)
            else {
                throw MaterialEvidenceError.renderPixelMismatch(fullPath)
            }
            guard let expectedTile = full.cropping(to: cropRect),
                  try normalizedRGBA(expectedTile) == normalizedRGBA(tile)
            else {
                throw MaterialEvidenceError.tileCropMismatch(tilePath)
            }
        }
        for path in ["contact-sheets/material-atlas.png", "contact-sheets/outline-counterform.png"] {
            _ = try decodedPNG(Data(contentsOf: directory.appendingPathComponent(path)), path: path)
        }
    }

    private static func verifySealedArtifacts(in directory: URL) throws -> String {
        let sums = try Data(contentsOf: directory.appendingPathComponent("SHA256SUMS"))
        let expectedPackageHash = try String(
            contentsOf: directory.appendingPathComponent("package-hash.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let actualPackageHash = sha256(sums)
        guard expectedPackageHash == actualPackageHash else {
            throw MaterialEvidenceError.packageHashMismatch(
                expected: expectedPackageHash,
                actual: actualPackageHash
            )
        }
        let lines = String(decoding: sums, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        var namedPaths = [String]()
        for line in lines {
            guard line.count > 66, line.dropFirst(64).prefix(2) == "  " else {
                throw MaterialEvidenceError.invalidPackage("malformed SHA256SUMS")
            }
            let expected = String(line.prefix(64))
            let path = String(line.dropFirst(66))
            let actual = sha256(try Data(contentsOf: directory.appendingPathComponent(path)))
            guard expected == actual else { throw MaterialEvidenceError.artifactHashMismatch(path) }
            namedPaths.append(path)
        }
        guard namedPaths == (try packageFilePaths(in: directory)) else {
            throw MaterialEvidenceError.invalidPackage("checksum artifact set mismatch")
        }
        return expectedPackageHash
    }

    private static func renderStem(_ fixture: MaterialAtlasFixture) -> String {
        String(
            format: "%02d-%@-colors-%02d-%@-layout-%02d",
            fixture.index,
            fixture.family.rawValue,
            fixture.requestedColorCount,
            fixture.background.rawValue,
            fixture.layoutFixtureIndex
        )
    }

    private static func write(_ data: Data, path: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
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
        excluding excluded: Set<String> = []
    ) throws -> [EvidenceArtifact] {
        try packageFilePaths(in: directory).filter { !excluded.contains($0) }.map { path in
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            let kind: String
            if path.hasPrefix("renders/") { kind = "core-render" }
            else if path.hasPrefix("contact-sheets/") { kind = "contact-sheet" }
            else if path == "metrics.json" { kind = "metrics" }
            else if path == "corpus-manifest.json" { kind = "corpus-manifest" }
            else if path == "composition-approved.json" { kind = "composition-approval" }
            else if path == "composition-recipes.json" { kind = "composition-recipe-archive" }
            else { kind = "artifact" }
            return EvidenceArtifact(
                path: path,
                kind: kind,
                byteCount: data.count,
                sha256: sha256(data)
            )
        }
    }

    private static func packageFilePaths(in directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }
        let root = directory.standardizedFileURL.path + "/"
        var paths = [String]()
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root) else {
                throw MaterialEvidenceError.invalidPackage("unsafe path \(path)")
            }
            let relative = String(path.dropFirst(root.count))
            if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            if relative != "SHA256SUMS" && relative != "package-hash.txt" {
                paths.append(relative)
            }
        }
        return paths.sorted()
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
        guard let context = CGContext(
            data: nil,
            width: columns * cellWidth,
            height: rows * cellHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw MaterialEvidenceError.cannotCreateContactSheet }
        context.setFillColor(gray: 0.10, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: columns * cellWidth, height: rows * cellHeight))
        for (index, path) in paths.enumerated() {
            let sourceURL = directory.appendingPathComponent(path)
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: cellHeight - 12,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { throw MaterialEvidenceError.cannotDecodeImage(path) }
            let column = index % columns
            let row = rows - index / columns - 1
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
                destination.origin.x += (cell.width - destination.width) * 0.5
            } else {
                destination.size.height = destination.width / aspect
                destination.origin.y += (cell.height - destination.height) * 0.5
            }
            context.draw(image, in: destination)
        }
        guard let image = context.makeImage() else { throw MaterialEvidenceError.cannotCreateContactSheet }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw MaterialEvidenceError.cannotCreateContactSheet }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        try write(data as Data, path: outputPath, in: directory)
    }

    private static func decodedPNG(_ data: Data, path: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MaterialEvidenceError.cannotDecodeImage(path) }
        return image
    }

    private static func normalizedRGBA(_ image: CGImage) throws -> Data {
        let bytesPerRow = image.width * 4
        var data = Data(count: bytesPerRow * image.height)
        let rendered = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { throw MaterialEvidenceError.cannotDecodeImage("rgba-buffer") }
        return data
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}
