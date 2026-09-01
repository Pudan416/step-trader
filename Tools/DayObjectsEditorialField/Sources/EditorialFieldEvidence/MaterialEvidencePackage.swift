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
    public let organicTopology: OrganicRadialTopology?
    public let samples: [MaterialSampleMeasurement]
}

public struct MaterialFixtureMetrics: Codable, Equatable, Sendable {
    public let fixture: MaterialAtlasFixture
    public let grammar: EditorialGrammar
    public let compositionRecipeSHA256: String
    public let tileCrop: PixelRect
    public let actors: [MaterialActorMetrics]
}

public struct MaterialFamilyCropMetrics: Codable, Equatable, Sendable {
    public let family: MaterialFamily
    public let requestedColorCount: Int
    public let actualColorCount: Int
    public let daySeed: UInt64
    public let eventID: String
    public let background: BackgroundCondition
    public let pixelSize: Int
    public let path: String
}

public struct MaterialExactTopologyCropMetrics: Codable, Equatable, Sendable {
    public let fixtureIndex: Int
    public let eventID: String
    public let family: MaterialFamily
    public let background: BackgroundCondition
    public let scale: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let path: String
}

public struct MaterialC3ActorAcceptance: Codable, Equatable, Sendable {
    public let eventID: String
    public let diameter: Double
    public let secondaryAreaFraction: Double
    public let tertiaryAreaFraction: Double
    public let secondaryPeakDifference: Double
    public let tertiaryPeakDifference: Double
    public let ownershipCenterDistance: Double
    public let ownershipColorDistance: Double
    public let tertiaryExpectedColorDistance: Double
    public let tertiarySecondaryColorDistance: Double
    public let secondaryTertiaryPaletteDistance: Double
    public let duplicateTertiaryRejected: Bool
    public let passes: Bool
}

public struct MaterialC3FixtureAcceptance: Codable, Equatable, Sendable {
    public let fixtureIndex: Int
    public let family: MaterialFamily
    public let eligibleActorCount: Int
    public let passingActorCount: Int
    public let passRate: Double
    public let actors: [MaterialC3ActorAcceptance]
}

public struct MaterialSceneScaleActorMetrics: Codable, Equatable, Sendable {
    public let eventID: String
    public let diameter: Double
    public let eligible: Bool
    public let sampleCount: Int
    public let meanContrast: Double
    public let percentile90Contrast: Double
    public let visibleAreaFraction: Double
    public let fullPresentation: MaterialOutlinePresentationMetadata?
    public let tilePresentation: MaterialOutlinePresentationMetadata?
    public let passes: Bool
}

public struct MaterialOutlinePresentationMetadata: Codable, Equatable, Sendable {
    public let inFrameRayCount: Int
    public let croppedRayCount: Int
    public let observableOwnedRayCount: Int
    public let occludedRayCount: Int
    public let supportedRayCount: Int
    public let angularCoverage: Double
}

public struct MaterialAlphaBandTopologyMetrics: Codable, Equatable, Sendable {
    public let contourIndex: Int
    public let centerOffset: Double
    public let thicknessRange: Double
    public let thicknessVariation: Double
    public let angularCoverage: Double
    public let minimumThickness: Double
    public let passes: Bool
}

public struct MaterialSceneScaleTopologyMetrics: Codable, Equatable, Sendable {
    public let eventID: String
    public let diameter: Double
    public let eligible: Bool
    public let fullCenterContrast: Double
    public let fullRimContrast: Double
    public let fullOpenCenterMargin: Double
    public let fullCenterToRimRatio: Double
    public let tileCenterContrast: Double
    public let tileRimContrast: Double
    public let tileOpenCenterMargin: Double
    public let tileCenterToRimRatio: Double
    public let fullEccentricCenterOffset: Double
    public let fullThicknessRange: Double
    public let tileEccentricCenterOffset: Double
    public let tileThicknessRange: Double
    public let fullAlphaBands: [MaterialAlphaBandTopologyMetrics]
    public let tileAlphaBands: [MaterialAlphaBandTopologyMetrics]
    public let passes: Bool
}

public struct MaterialSceneScaleMetrics: Codable, Equatable, Sendable {
    public let family: MaterialFamily
    public let requestedColorCount: Int
    public let background: BackgroundCondition
    public let layoutFixtureIndex: Int
    public let daySeed: UInt64
    public let sourceScale: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fullPath: String
    public let tilePath: String
    public let actors: [MaterialSceneScaleActorMetrics]
    public let topology: [MaterialSceneScaleTopologyMetrics]
}

public struct MaterialEvidenceMetrics: Codable, Equatable, Sendable {
    public let version: String
    public let fixtureCount: Int
    public let coreImageCount: Int
    public let compositionApprovalSHA256: String
    public let compositionRecipeArchiveSHA256: String
    public let fixtures: [MaterialFixtureMetrics]
    public let familyCrops: [MaterialFamilyCropMetrics]
    public let exactTopologyCrops: [MaterialExactTopologyCropMetrics]
    public let c3Acceptance: [MaterialC3FixtureAcceptance]
    public let sceneScale: [MaterialSceneScaleMetrics]
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

    private struct AnalysisPixel {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        func distance(to other: AnalysisPixel) -> Double {
            hypot(hypot(red - other.red, green - other.green), blue - other.blue)
        }

        func distance(to color: MaterialColor) -> Double {
            hypot(hypot(red - color.red, green - color.green), blue - color.blue)
        }
    }

    private struct AnalysisImage {
        let width: Int
        let height: Int
        let rgba: Data

        func pixel(x: Int, y: Int) -> AnalysisPixel {
            let offset = (y * width + x) * 4
            let alphaByte = Double(rgba[offset + 3])
            let divisor = max(1, alphaByte)
            return AnalysisPixel(
                red: Double(rgba[offset]) / divisor,
                green: Double(rgba[offset + 1]) / divisor,
                blue: Double(rgba[offset + 2]) / divisor,
                alpha: alphaByte / 255
            )
        }
    }

    private struct ColorContributionAnalysis {
        let areaFraction: Double
        let peakDifference: Double
        let center: CompositionPoint
        let color: AnalysisPixel
    }

    private struct SceneScaleEvidence {
        let metrics: [MaterialSceneScaleMetrics]
        let fullImages: [String: Data]
        let tileImages: [String: Data]
    }

    private struct ExactTopologyCropEvidence {
        let metrics: [MaterialExactTopologyCropMetrics]
        let images: [String: Data]
    }

    private struct OutlineReadabilityImages {
        let isolatedFull: Data
        let removedFull: Data
        let isolatedTile: Data
        let removedTile: Data
        let ownerIndex: UInt8?
        let ownerLabelsFull: Data?
        let ownerLabelsTile: Data?
    }

    struct C3ActorAssessment {
        let secondaryAreaFraction: Double
        let tertiaryAreaFraction: Double
        let secondaryPeakDifference: Double
        let tertiaryPeakDifference: Double
        let ownershipCenterDistance: Double
        let ownershipColorDistance: Double
        let tertiaryExpectedColorDistance: Double
        let tertiarySecondaryColorDistance: Double
        let secondaryTertiaryPaletteDistance: Double
        let passes: Bool
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

        let familyCrops = try writeFamilyCropArtifacts(
            manifest: manifest,
            scale: scale,
            renderer: renderer,
            directory: outputDirectory
        )
        let exactTopologyCrops = try makeExactTopologyCropEvidence(
            coverage: atlasCoverage,
            manifest: manifest,
            frozenRecipes: frozenRecipes,
            renderer: renderer,
            scale: scale
        )
        for (path, data) in exactTopologyCrops.images {
            try write(data, path: path, in: outputDirectory)
        }
        let c3Acceptance = try c3AcceptanceMetrics(
            coverage: atlasCoverage,
            manifest: manifest,
            frozenRecipes: frozenRecipes,
            renderer: renderer
        )
        guard c3Acceptance.allSatisfy({ $0.passRate >= 0.90 }) else {
            throw MaterialEvidenceError.invalidPackage(
                "critic c3 discriminability proxy did not reach 90 percent"
            )
        }
        let sceneScaleEvidence = try makeSceneScaleEvidence(
            manifest: manifest,
            frozenRecipes: frozenRecipes,
            renderer: renderer
        )
        let sceneScaleFailures = sceneScaleEvidence.metrics.flatMap { scene in
            let readability = scene.actors.filter { !$0.passes }.map { actor in
                "\(scene.family.rawValue)/c\(scene.requestedColorCount)/"
                    + "\(scene.background.rawValue)/\(actor.eventID.prefix(4))"
                    + " p90=\(String(format: "%.3f", actor.percentile90Contrast))"
                    + " area=\(String(format: "%.3f", actor.visibleAreaFraction))"
            }
            let topology = scene.topology.filter { !$0.passes }.map { actor in
                "\(scene.family.rawValue)/c\(scene.requestedColorCount)/"
                    + "\(scene.background.rawValue)/\(actor.eventID.prefix(4))"
                    + " topology full=\(String(format: "%.3f", actor.fullCenterToRimRatio))"
                    + " tile=\(String(format: "%.3f", actor.tileCenterToRimRatio))"
            }
            return readability + topology
        }
        guard sceneScaleFailures.isEmpty else {
            throw MaterialEvidenceError.invalidPackage(
                "scene-scale actor readability proxy failed: "
                    + sceneScaleFailures.joined(separator: ", ")
            )
        }
        for (path, data) in sceneScaleEvidence.fullImages {
            try write(data, path: path, in: outputDirectory)
        }
        for (path, data) in sceneScaleEvidence.tileImages {
            try write(data, path: path, in: outputDirectory)
        }

        let metrics = MaterialEvidenceMetrics(
            version: "material-metrics-v8",
            fixtureCount: atlasCoverage.fixtures.count,
            coreImageCount: atlasCoverage.coreImageCount,
            compositionApprovalSHA256: approvalHash,
            compositionRecipeArchiveSHA256: recipeArchiveHash,
            fixtures: fixtureMetrics,
            familyCrops: familyCrops,
            exactTopologyCrops: exactTopologyCrops.metrics,
            c3Acceptance: c3Acceptance,
            sceneScale: sceneScaleEvidence.metrics
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
        try makeContactSheet(
            paths: sceneScaleEvidence.metrics.map(\.fullPath),
            outputPath: "contact-sheets/scene-scale-full.png",
            directory: outputDirectory,
            columns: 9,
            cellWidth: 92,
            cellHeight: 198
        )
        try makeContactSheet(
            paths: sceneScaleEvidence.metrics.map(\.tilePath),
            outputPath: "contact-sheets/scene-scale-tile.png",
            directory: outputDirectory,
            columns: 9,
            cellWidth: 96,
            cellHeight: 96
        )

        let artifacts = try artifactRecords(in: outputDirectory)
        let packageManifest = MaterialEvidenceManifest(
            version: "material-evidence-v8",
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
        guard manifest.version == "material-evidence-v8",
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
        let expectedFamilyCrops = familyCropMetrics(manifest: corpus, scale: manifest.viewport.scale)
        let expectedExactTopologyCrops = try makeExactTopologyCropEvidence(
            coverage: expectedCoverage,
            manifest: corpus,
            frozenRecipes: frozenRecipes,
            renderer: MaterialRenderer(),
            scale: manifest.viewport.scale
        )
        let expectedC3Acceptance = try c3AcceptanceMetrics(
            coverage: expectedCoverage,
            manifest: corpus,
            frozenRecipes: frozenRecipes,
            renderer: MaterialRenderer()
        )
        let expectedSceneScale = try makeSceneScaleEvidence(
            manifest: corpus,
            frozenRecipes: frozenRecipes,
            renderer: MaterialRenderer()
        )
        guard metrics.version == "material-metrics-v8",
              metrics.fixtureCount == expectedCoverage.fixtures.count,
              metrics.coreImageCount == expectedCoverage.coreImageCount,
              metrics.compositionApprovalSHA256 == manifest.compositionApprovalSHA256,
              metrics.compositionRecipeArchiveSHA256 == manifest.compositionRecipeArchiveSHA256,
              metrics.fixtures == expectedFixtureMetrics,
              metrics.familyCrops == expectedFamilyCrops,
              metrics.exactTopologyCrops == expectedExactTopologyCrops.metrics,
              metrics.c3Acceptance == expectedC3Acceptance,
              metrics.c3Acceptance.allSatisfy({ $0.passRate >= 0.90 }),
              metrics.sceneScale == expectedSceneScale.metrics,
              metrics.sceneScale.allSatisfy({
                  !$0.actors.isEmpty
                      && $0.actors.allSatisfy(\.passes)
                      && $0.topology.allSatisfy(\.passes)
              })
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
            sceneScaleEvidence: expectedSceneScale,
            exactTopologyCropEvidence: expectedExactTopologyCrops,
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
                organicTopology: actor.organicTopology,
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

    private static func familyCropMetrics(
        manifest: CorpusManifest,
        scale: Int
    ) -> [MaterialFamilyCropMetrics] {
        let exemplar = manifest.breadth[0]
        let eventID = exemplar.eventIDs[0]
        let pixelSize = 160 * scale
        return MaterialFamily.allCases.flatMap { family in
            (1...3).map { colorCount in
                MaterialFamilyCropMetrics(
                    family: family,
                    requestedColorCount: colorCount,
                    actualColorCount: family == .solid ? 1 : colorCount,
                    daySeed: exemplar.seed,
                    eventID: eventID,
                    background: .lowContrast,
                    pixelSize: pixelSize,
                    path: familyCropPath(
                        family: family,
                        colorCount: colorCount,
                        scale: scale
                    )
                )
            }
        }
    }

    private static func writeFamilyCropArtifacts(
        manifest: CorpusManifest,
        scale: Int,
        renderer: MaterialRenderer,
        directory: URL
    ) throws -> [MaterialFamilyCropMetrics] {
        let metrics = familyCropMetrics(manifest: manifest, scale: scale)
        for crop in metrics {
            let actor = MaterialDNA.fixture(
                daySeed: crop.daySeed,
                eventIDs: [crop.eventID],
                family: crop.family,
                requestedColorCount: crop.requestedColorCount
            ).actor(crop.eventID)
            guard let actor else {
                throw MaterialEvidenceError.invalidPackage("missing family crop actor")
            }
            let rendered = try renderer.renderActor(
                actor,
                pixelSize: crop.pixelSize,
                background: crop.background
            )
            try write(rendered.pngData, path: crop.path, in: directory)
        }
        try makeContactSheet(
            paths: metrics.map(\.path),
            outputPath: "contact-sheets/family-optics.png",
            directory: directory,
            columns: 3,
            cellWidth: 180,
            cellHeight: 180
        )
        return metrics
    }

    private static func makeExactTopologyCropEvidence(
        coverage: MaterialAtlasCoverage,
        manifest: CorpusManifest,
        frozenRecipes: [Int: SceneRecipe],
        renderer: MaterialRenderer,
        scale: Int
    ) throws -> ExactTopologyCropEvidence {
        var metrics = [MaterialExactTopologyCropMetrics]()
        var images = [String: Data]()
        let canvasWidth = 393 * scale
        let canvasHeight = 852 * scale

        for item in exactTopologyCropCases {
            guard let fixture = coverage.fixtures.first(where: { $0.index == item.fixtureIndex }),
                  manifest.breadth.indices.contains(fixture.layoutFixtureIndex),
                  let recipe = frozenRecipes[fixture.layoutFixtureIndex],
                  let actor = recipe.actor(item.eventID)
            else {
                throw MaterialEvidenceError.invalidPackage("missing exact topology crop fixture")
            }
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: fixture.family,
                requestedColorCount: fixture.requestedColorCount
            )
            let isolated = SceneRecipe(
                daySeed: recipe.daySeed,
                grammar: recipe.grammar,
                viewport: recipe.viewport,
                actors: [actor]
            )
            let rendered = try renderer.render(
                recipe: isolated,
                material: material,
                background: fixture.background,
                configuration: .init(scale: scale)
            )
            let full = try decodedPNG(rendered.fullScreen.pngData, path: "exact-topology-source")
            let actorLayerPoints = (actor.diameter + actor.localBlur * 6) * 393
            let cropSide = min(
                canvasWidth,
                max(96 * scale, Int(ceil(actorLayerPoints * Double(scale))))
            )
            let desiredX = Int((actor.position.x * Double(canvasWidth)).rounded()) - cropSide / 2
            let desiredY = Int((actor.position.y * Double(canvasHeight)).rounded()) - cropSide / 2
            let cropX = min(max(0, desiredX), canvasWidth - cropSide)
            let cropY = min(max(0, desiredY), canvasHeight - cropSide)
            guard let crop = full.cropping(to: CGRect(
                x: cropX,
                y: cropY,
                width: cropSide,
                height: cropSide
            )) else {
                throw MaterialEvidenceError.cannotCreateContactSheet
            }
            let path = exactTopologyCropPath(
                fixtureIndex: item.fixtureIndex,
                family: fixture.family,
                eventID: item.eventID,
                scale: scale
            )
            images[path] = try encodedPNG(crop)
            metrics.append(MaterialExactTopologyCropMetrics(
                fixtureIndex: item.fixtureIndex,
                eventID: item.eventID,
                family: fixture.family,
                background: fixture.background,
                scale: scale,
                pixelWidth: crop.width,
                pixelHeight: crop.height,
                path: path
            ))
        }
        return ExactTopologyCropEvidence(metrics: metrics, images: images)
    }

    private static func makeSceneScaleEvidence(
        manifest: CorpusManifest,
        frozenRecipes: [Int: SceneRecipe],
        renderer: MaterialRenderer
    ) throws -> SceneScaleEvidence {
        let layoutFixtureIndex = 11
        guard manifest.breadth.indices.contains(layoutFixtureIndex),
              let recipe = frozenRecipes[layoutFixtureIndex]
        else {
            throw MaterialEvidenceError.invalidCompositionApproval(
                "scene-scale evidence requires frozen breadth fixture 11"
            )
        }
        let layout = manifest.breadth[layoutFixtureIndex]
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        var metrics = [MaterialSceneScaleMetrics]()
        var fullImages = [String: Data]()
        var tileImages = [String: Data]()

        for family in MaterialFamily.allCases {
            for colorCount in 1...3 {
                let material = MaterialDNA.fixture(
                    daySeed: layout.seed,
                    eventIDs: layout.eventIDs,
                    family: family,
                    requestedColorCount: colorCount
                )
                for background in backgrounds {
                    let source = try sceneScaleRenderedScene(
                        recipe: recipe,
                        material: material,
                        background: background,
                        renderer: renderer,
                        presentationEvidenceRequest: family == .outline ? .perActor : .none
                    )
                    let fullImage = try decodedPNG(
                        source.fullScreen.pngData,
                        path: "scene-scale-source"
                    )
                    let tileImage = try decodedPNG(
                        source.calendarTile.pngData,
                        path: "scene-scale-tile"
                    )
                    guard source.tileCrop == PixelRect(x: 0, y: 229, width: 393, height: 393),
                          source.drawSequence == recipe.actors.sorted(by: {
                              if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
                              if $0.depth != $1.depth { return $0.depth < $1.depth }
                              if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
                              return $0.eventID < $1.eventID
                          }).map(\.eventID)
                    else {
                        throw MaterialEvidenceError.invalidPackage(
                            "scene-scale renderer changed frozen crop or draw order"
                        )
                    }
                    let stem = sceneScaleStem(
                        family: family,
                        colorCount: colorCount,
                        background: background
                    )
                    let fullPath = "scene-scale/\(family.rawValue)/\(stem)-full@1x.png"
                    let tilePath = "scene-scale/\(family.rawValue)/\(stem)-tile@1x.png"
                    fullImages[fullPath] = source.fullScreen.pngData
                    tileImages[tilePath] = source.calendarTile.pngData
                    let actorReadability: [MaterialSceneScaleActorMetrics]
                    if family == .outline {
                        guard let payloadReadability = try presentationSceneScaleReadability(
                            source: source,
                            recipe: recipe,
                            material: material,
                            background: background
                        ) else {
                            throw MaterialEvidenceError.invalidPackage(
                                "outline scene-scale render omitted requested presentation evidence"
                            )
                        }
                        actorReadability = payloadReadability
                    } else {
                        actorReadability = try sceneScaleReadability(
                            image: fullImage,
                            tileImage: tileImage,
                            recipe: recipe,
                            material: material,
                            background: background,
                            outlineImages: nil
                        )
                    }
                    let topology = try sceneScaleTopology(
                        family: family,
                        recipe: recipe,
                        material: material,
                        background: background,
                        renderer: renderer
                    )
                    metrics.append(MaterialSceneScaleMetrics(
                        family: family,
                        requestedColorCount: colorCount,
                        background: background,
                        layoutFixtureIndex: layoutFixtureIndex,
                        daySeed: layout.seed,
                        sourceScale: 2,
                        pixelWidth: 393,
                        pixelHeight: 852,
                        fullPath: fullPath,
                        tilePath: tilePath,
                        actors: actorReadability,
                        topology: topology
                    ))
                }
            }
        }
        return SceneScaleEvidence(
            metrics: metrics,
            fullImages: fullImages,
            tileImages: tileImages
        )
    }

    static func sceneScaleRenderedScene(
        recipe: SceneRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        renderer: MaterialRenderer,
        presentationEvidenceRequest: MaterialPresentationEvidenceRequest = .none
    ) throws -> MaterialRenderedScene {
        try renderer.render(
            recipe: recipe,
            material: material,
            background: background,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                presentationEvidenceRequest: presentationEvidenceRequest
            )
        )
    }

    static func legacySceneScaleReadabilityForTesting(
        source: MaterialRenderedScene,
        recipe: SceneRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        renderer: MaterialRenderer
    ) throws -> [MaterialSceneScaleActorMetrics] {
        try sceneScaleReadability(
            image: decodedPNG(source.fullScreen.pngData, path: "scene-scale-source"),
            tileImage: decodedPNG(source.calendarTile.pngData, path: "scene-scale-tile"),
            recipe: recipe,
            material: material,
            background: background,
            outlineImages: { actor in
                let isolatedRecipe = SceneRecipe(
                    daySeed: recipe.daySeed,
                    grammar: recipe.grammar,
                    viewport: recipe.viewport,
                    actors: [actor]
                )
                let removedRecipe = SceneRecipe(
                    daySeed: recipe.daySeed,
                    grammar: recipe.grammar,
                    viewport: recipe.viewport,
                    actors: recipe.actors.filter { $0.eventID != actor.eventID }
                )
                let isolated = try sceneScaleRenderedScene(
                    recipe: isolatedRecipe,
                    material: material,
                    background: background,
                    renderer: renderer
                )
                let removed = try sceneScaleRenderedScene(
                    recipe: removedRecipe,
                    material: material,
                    background: background,
                    renderer: renderer
                )
                return OutlineReadabilityImages(
                    isolatedFull: isolated.fullScreen.pngData,
                    removedFull: removed.fullScreen.pngData,
                    isolatedTile: isolated.calendarTile.pngData,
                    removedTile: removed.calendarTile.pngData,
                    ownerIndex: nil,
                    ownerLabelsFull: nil,
                    ownerLabelsTile: nil
                )
            }
        )
    }

    static func presentationSceneScaleReadabilityForTesting(
        source: MaterialRenderedScene,
        recipe: SceneRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition
    ) throws -> [MaterialSceneScaleActorMetrics]? {
        try presentationSceneScaleReadability(
            source: source,
            recipe: recipe,
            material: material,
            background: background
        )
    }

    private static func presentationSceneScaleReadability(
        source: MaterialRenderedScene,
        recipe: SceneRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition
    ) throws -> [MaterialSceneScaleActorMetrics]? {
        guard let presentationEvidence = source.presentationEvidence else { return nil }
        return try sceneScaleReadability(
            image: decodedPNG(source.fullScreen.pngData, path: "scene-scale-source"),
            tileImage: decodedPNG(source.calendarTile.pngData, path: "scene-scale-tile"),
            recipe: recipe,
            material: material,
            background: background,
            outlineImages: { actor in
                guard let actorEvidence = presentationEvidence.actors.first(where: {
                    $0.eventID == actor.eventID
                }) else {
                    throw MaterialEvidenceError.invalidPackage(
                        "missing outline presentation evidence for \(actor.eventID)"
                    )
                }
                let ownership = actorEvidence.isolated.ownership
                guard ownership.width == actorEvidence.isolated.fullScreen.pixelWidth,
                      ownership.height == actorEvidence.isolated.fullScreen.pixelHeight,
                      ownership.ownerLabels.count == ownership.width * ownership.height,
                      let ownerIndex = ownership.ownerEventIDs.firstIndex(of: actor.eventID),
                      ownerIndex < 255
                else {
                    throw MaterialEvidenceError.invalidPackage(
                        "invalid outline presentation ownership for \(actor.eventID)"
                    )
                }
                return OutlineReadabilityImages(
                    isolatedFull: actorEvidence.isolated.fullScreen.pngData,
                    removedFull: actorEvidence.removed.fullScreen.pngData,
                    isolatedTile: actorEvidence.isolated.calendarTile.pngData,
                    removedTile: actorEvidence.removed.calendarTile.pngData,
                    ownerIndex: UInt8(ownerIndex),
                    ownerLabelsFull: ownership.ownerLabels,
                    ownerLabelsTile: croppedOwnerLabels(
                        ownership.ownerLabels,
                        sourceWidth: ownership.width,
                        crop: actorEvidence.isolated.tileCrop
                    )
                )
            }
        )
    }

    private static func sceneScaleReadability(
        image: CGImage,
        tileImage: CGImage,
        recipe: SceneRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        outlineImages: ((ActorCompositionRecipe) throws -> OutlineReadabilityImages)?
    ) throws -> [MaterialSceneScaleActorMetrics] {
        let analysis = AnalysisImage(
            width: image.width,
            height: image.height,
            rgba: try normalizedRGBA(image)
        )
        let backgroundColor = Self.backgroundRGB(background)
        let tileAnalysis = AnalysisImage(
            width: tileImage.width,
            height: tileImage.height,
            rgba: try normalizedRGBA(tileImage)
        )
        return try recipe.actors.map { actor in
            let actorMaterial = material.actor(actor.eventID)
            let centerX = actor.position.x * 393
            // normalizedRGBA exposes the bitmap's bottom-origin row order, the
            // same coordinate system in which the scene renderer positions it.
            let centerY = actor.position.y * 852
            let nominalRadius = actor.diameter * 393 * 0.5
            let minimumX = max(0, Int(floor(centerX - nominalRadius * 1.08)))
            let maximumX = min(392, Int(ceil(centerX + nominalRadius * 1.08)))
            let minimumY = max(0, Int(floor(centerY - nominalRadius * 1.08)))
            let maximumY = min(851, Int(ceil(centerY + nominalRadius * 1.08)))
            if material.family == .outline {
                guard let outlineImages else {
                    throw MaterialEvidenceError.invalidPackage(
                        "outline scene-scale readability requires presentation images"
                    )
                }
                let actorImages = try outlineImages(actor)
                let isolatedFull = try decodedPNG(
                    actorImages.isolatedFull,
                    path: "scene-scale-isolated"
                )
                let removedFull = try decodedPNG(
                    actorImages.removedFull,
                    path: "scene-scale-removed"
                )
                let isolatedTile = try decodedPNG(
                    actorImages.isolatedTile,
                    path: "scene-scale-isolated-tile"
                )
                let removedTile = try decodedPNG(
                    actorImages.removedTile,
                    path: "scene-scale-removed-tile"
                )
                let isolatedAnalysis = AnalysisImage(
                    width: isolatedFull.width,
                    height: isolatedFull.height,
                    rgba: try normalizedRGBA(isolatedFull)
                )
                let removedAnalysis = AnalysisImage(
                    width: removedFull.width,
                    height: removedFull.height,
                    rgba: try normalizedRGBA(removedFull)
                )
                let isolatedTileAnalysis = AnalysisImage(
                    width: isolatedTile.width,
                    height: isolatedTile.height,
                    rgba: try normalizedRGBA(isolatedTile)
                )
                let removedTileAnalysis = AnalysisImage(
                    width: removedTile.width,
                    height: removedTile.height,
                    rgba: try normalizedRGBA(removedTile)
                )
                let fullPresentation = outlineActorPresentation(
                    isolated: isolatedAnalysis,
                    composed: analysis,
                    removed: removedAnalysis,
                    ownerIndex: actorImages.ownerIndex,
                    ownerLabels: actorImages.ownerLabelsFull,
                    actor: actor,
                    background: backgroundColor,
                    centerYAdjustment: 0
                )
                let tilePresentation = outlineActorPresentation(
                    isolated: isolatedTileAnalysis,
                    composed: tileAnalysis,
                    removed: removedTileAnalysis,
                    ownerIndex: actorImages.ownerIndex,
                    ownerLabels: actorImages.ownerLabelsTile,
                    actor: actor,
                    background: backgroundColor,
                    centerYAdjustment: -229
                )
                let fullMetadata = fullPresentation.metadata
                let tileMetadata = tilePresentation.metadata
                let fullPasses = fullMetadata.observableOwnedRayCount == 0
                    || fullMetadata.angularCoverage >= 0.82
                let tilePasses = tileMetadata.observableOwnedRayCount == 0
                    || tileMetadata.angularCoverage >= 0.82
                return MaterialSceneScaleActorMetrics(
                    eventID: actor.eventID,
                    diameter: actor.diameter,
                    eligible: actor.diameter >= 0.15,
                    sampleCount: fullPresentation.sampleCount,
                    meanContrast: fullPresentation.meanContrast,
                    percentile90Contrast: fullPresentation.percentile90Contrast,
                    visibleAreaFraction: fullPresentation.identityAngularCoverage,
                    fullPresentation: fullMetadata,
                    tilePresentation: tileMetadata,
                    passes: actor.diameter < 0.15 || (
                        fullPresentation.sampleCount >= 8
                            && fullPresentation.percentile90Contrast >= 0.16
                            && fullPresentation.identityAngularCoverage >= 0.82
                            && fullPasses
                            && tilePasses
                    )
                )
            }
            var contrasts = [Double]()
            for y in minimumY...maximumY {
                for x in minimumX...maximumX {
                    let normalizedRadius = hypot(
                        (Double(x) + 0.5 - centerX) / max(nominalRadius, 1),
                        (Double(y) + 0.5 - centerY) / max(nominalRadius, 1)
                    )
                    let sample: Bool = switch material.family {
                    case .counterform:
                        normalizedRadius >= (actorMaterial?.counterformRadius ?? 0.30) * 0.90
                            && normalizedRadius <= 1.02
                    default:
                        normalizedRadius <= 0.94
                    }
                    guard sample else { continue }
                    contrasts.append(analysis.pixel(x: x, y: y).distance(to: backgroundColor))
                }
            }
            contrasts.sort()
            let mean = contrasts.reduce(0, +) / Double(max(contrasts.count, 1))
            let percentileIndex = min(
                max(contrasts.count - 1, 0),
                Int(Double(max(contrasts.count - 1, 0)) * 0.90)
            )
            let percentile90 = contrasts.isEmpty ? 0 : contrasts[percentileIndex]
            let visibleArea = Double(contrasts.filter { $0 >= 0.08 }.count)
                / Double(max(contrasts.count, 1))
            let thresholds: (contrast: Double, area: Double) = switch material.family {
            case .gradient, .solid, .sphere:
                (0.12, 0.44)
            case .glass, .mist, .halo, .luminous:
                (0.11, 0.30)
            case .outline, .counterform:
                (0.13, 0.18)
            }
            return MaterialSceneScaleActorMetrics(
                eventID: actor.eventID,
                diameter: actor.diameter,
                eligible: actor.diameter >= 0.15,
                sampleCount: contrasts.count,
                meanContrast: mean,
                percentile90Contrast: percentile90,
                visibleAreaFraction: visibleArea,
                fullPresentation: nil,
                tilePresentation: nil,
                passes: actor.diameter < 0.15 || (
                    contrasts.count >= 8
                        && percentile90 >= thresholds.contrast
                        && visibleArea >= thresholds.area
                )
            )
        }
    }

    private static func outlineContourPresentation(
        image: AnalysisImage,
        actor: ActorCompositionRecipe,
        background: AnalysisPixel,
        centerYAdjustment: Double
    ) -> (
        sampleCount: Int,
        meanContrast: Double,
        percentile90Contrast: Double,
        angularCoverage: Double
    ) {
        let centerX = actor.position.x * 393
        let centerY = actor.position.y * 852 + centerYAdjustment
        let pixelRadius = max(actor.diameter * 393 * 0.48, 1)
        var supportedContrasts = [Double]()
        var supportedRays = 0
        for angleIndex in 0..<96 {
            let angle = Double(angleIndex) / 96 * Double.pi * 2
            var longestRun = 0
            var currentRun = 0
            var rayContrasts = [Double]()
            let radialSteps = max(1, Int(ceil((1.08 - 0.52) * pixelRadius)))
            for step in 0...radialSteps {
                let radius = 0.52 + Double(step) / pixelRadius
                let x = Int((centerX + cos(angle) * radius * pixelRadius).rounded(.down))
                let y = Int((centerY + sin(angle) * radius * pixelRadius).rounded(.down))
                guard (0..<image.width).contains(x), (0..<image.height).contains(y) else {
                    currentRun = 0
                    continue
                }
                let contrast = image.pixel(x: x, y: y).distance(to: background)
                if contrast >= 0.075 {
                    currentRun += 1
                    longestRun = max(longestRun, currentRun)
                    rayContrasts.append(contrast)
                } else {
                    currentRun = 0
                }
            }
            if longestRun >= 2 {
                supportedRays += 1
                supportedContrasts.append(contentsOf: rayContrasts)
            }
        }
        supportedContrasts.sort()
        let percentileIndex = min(
            max(supportedContrasts.count - 1, 0),
            Int(Double(max(supportedContrasts.count - 1, 0)) * 0.90)
        )
        return (
            sampleCount: supportedContrasts.count,
            meanContrast: supportedContrasts.reduce(0, +)
                / Double(max(supportedContrasts.count, 1)),
            percentile90Contrast: supportedContrasts.isEmpty ? 0 : supportedContrasts[percentileIndex],
            angularCoverage: Double(supportedRays) / 96
        )
    }

    private struct OutlineActorPresentation {
        let sampleCount: Int
        let meanContrast: Double
        let percentile90Contrast: Double
        let identityAngularCoverage: Double
        let metadata: MaterialOutlinePresentationMetadata
    }

    private static func outlineActorPresentation(
        isolated: AnalysisImage,
        composed: AnalysisImage,
        removed: AnalysisImage,
        ownerIndex: UInt8?,
        ownerLabels: Data?,
        actor: ActorCompositionRecipe,
        background: AnalysisPixel,
        centerYAdjustment: Double
    ) -> OutlineActorPresentation {
        let centerX = actor.position.x * 393
        let centerY = actor.position.y * 852 + centerYAdjustment
        let pixelRadius = max(actor.diameter * 393 * 0.48, 1)
        let radialSteps = max(1, Int(ceil((1.08 - 0.52) * pixelRadius)))
        var identityContrasts = [Double]()
        var identitySupportedRays = 0
        var inFrameRays = 0
        var observableOwnedRays = 0
        var occludedRays = 0
        var presentationSupportedRays = 0

        for angleIndex in 0..<96 {
            let angle = Double(angleIndex) / 96 * Double.pi * 2
            var inFrame = true
            var identityRun = 0
            var longestIdentityRun = 0
            var contributionRun = 0
            var longestContributionRun = 0
            var presentationRun = 0
            var longestPresentationRun = 0
            var rayIdentityContrasts = [Double]()
            for step in 0...radialSteps {
                let radius = 0.52 + Double(step) / pixelRadius
                let x = Int((centerX + cos(angle) * radius * pixelRadius).rounded(.down))
                let y = Int((centerY + sin(angle) * radius * pixelRadius).rounded(.down))
                guard (0..<isolated.width).contains(x), (0..<isolated.height).contains(y) else {
                    inFrame = false
                    identityRun = 0
                    contributionRun = 0
                    presentationRun = 0
                    continue
                }
                let isolatedPixel = isolated.pixel(x: x, y: y)
                let composedPixel = composed.pixel(x: x, y: y)
                let removedPixel = removed.pixel(x: x, y: y)
                let isolatedContrast = isolatedPixel.distance(to: background)
                let exactOwner = ownerIndex.flatMap { index in
                    ownerLabels.map { $0[y * isolated.width + x] == index }
                }
                let actorOwned = ownerLabels == nil
                    ? isolatedContrast >= 0.075
                    : isolatedPixel.alpha > 0
                let structuralSupport = ownerLabels == nil
                    ? actorOwned
                    : outlineStructuralSupport(alpha: isolatedPixel.alpha)
                let actorContributes = exactOwner
                    ?? (composedPixel.distance(to: removedPixel) >= 1.0 / 255.0)
                let presentationContrast = ownerLabels == nil
                    ? isolatedContrast
                    : composedPixel.distance(to: removedPixel)
                let visible = actorOwned
                    && structuralSupport
                    && actorContributes
                    && presentationContrast >= 0.075

                identityRun = actorOwned ? identityRun + 1 : 0
                contributionRun = structuralSupport && actorContributes
                    ? contributionRun + 1
                    : 0
                presentationRun = visible ? presentationRun + 1 : 0
                longestIdentityRun = max(longestIdentityRun, identityRun)
                longestContributionRun = max(longestContributionRun, contributionRun)
                longestPresentationRun = max(longestPresentationRun, presentationRun)
                if structuralSupport && (ownerLabels == nil || actorContributes) {
                    rayIdentityContrasts.append(presentationContrast)
                }
            }
            guard inFrame else { continue }
            inFrameRays += 1
            if longestIdentityRun >= 2 {
                identitySupportedRays += 1
                identityContrasts.append(contentsOf: rayIdentityContrasts)
                if longestContributionRun >= 2 {
                    observableOwnedRays += 1
                    if longestPresentationRun >= 2 { presentationSupportedRays += 1 }
                } else {
                    occludedRays += 1
                }
            }
        }

        identityContrasts.sort()
        let percentileIndex = min(
            max(identityContrasts.count - 1, 0),
            Int(Double(max(identityContrasts.count - 1, 0)) * 0.90)
        )
        let identityCoverage = Double(identitySupportedRays) / Double(max(inFrameRays, 1))
        let presentationCoverage = Double(presentationSupportedRays)
            / Double(max(observableOwnedRays, 1))
        return OutlineActorPresentation(
            sampleCount: identityContrasts.count,
            meanContrast: identityContrasts.reduce(0, +)
                / Double(max(identityContrasts.count, 1)),
            percentile90Contrast: identityContrasts.isEmpty ? 0 : identityContrasts[percentileIndex],
            identityAngularCoverage: identityCoverage,
            metadata: MaterialOutlinePresentationMetadata(
                inFrameRayCount: inFrameRays,
                croppedRayCount: 96 - inFrameRays,
                observableOwnedRayCount: observableOwnedRays,
                occludedRayCount: occludedRays,
                supportedRayCount: presentationSupportedRays,
                angularCoverage: presentationCoverage
            )
        )
    }

    static func outlineStructuralSupport(alpha: Double) -> Bool {
        alpha >= 0.075
    }

    private static func croppedOwnerLabels(
        _ labels: Data,
        sourceWidth: Int,
        crop: PixelRect
    ) -> Data {
        var cropped = Data()
        cropped.reserveCapacity(crop.width * crop.height)
        for y in crop.y..<(crop.y + crop.height) {
            let lower = y * sourceWidth + crop.x
            cropped.append(labels[lower..<(lower + crop.width)])
        }
        return cropped
    }

    static func sceneScaleTopology(
        family: MaterialFamily,
        recipe: SceneRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        renderer: MaterialRenderer
    ) throws -> [MaterialSceneScaleTopologyMetrics] {
        guard [.halo, .outline, .counterform].contains(family) else { return [] }
        // This layout-11 actor is fully present in both the 393x852 canvas and
        // its exact centered 393x393 tile crop, while still carrying scene
        // blur. Isolating it keeps the topology measurement independent from
        // overlap and draw order without changing any frozen actor geometry.
        let exemplarID = "5FA2D140-7C0E-45B9-BE3D-8124A937EF06"
        guard let actor = recipe.actor(exemplarID),
              let actorMaterial = material.actor(exemplarID)
        else {
            throw MaterialEvidenceError.invalidPackage("missing scene-scale topology exemplar")
        }
        let isolated = SceneRecipe(
            daySeed: recipe.daySeed,
            grammar: recipe.grammar,
            viewport: recipe.viewport,
            actors: [actor]
        )
        let source = try sceneScaleRenderedScene(
            recipe: isolated,
            material: material,
            background: background,
            renderer: renderer
        )
        let full = try decodedPNG(
            source.fullScreen.pngData,
            path: "scene-scale-topology-source"
        )
        let tile = try decodedPNG(
            source.calendarTile.pngData,
            path: "scene-scale-topology-tile"
        )
        let fullBands = try topologyBands(
            image: full,
            actor: actor,
            material: actorMaterial,
            background: background,
            centerYAdjustment: 0
        )
        let tileBands = try topologyBands(
            image: tile,
            actor: actor,
            material: actorMaterial,
            background: background,
            centerYAdjustment: -229
        )
        let alphaTopology = try sceneScaleAlphaTopology(
            actor: actor,
            material: actorMaterial,
            background: background,
            renderer: renderer
        )
        let fullOutline = outlineContourPresentation(
            image: AnalysisImage(
                width: full.width,
                height: full.height,
                rgba: try normalizedRGBA(full)
            ),
            actor: actor,
            background: backgroundRGB(background),
            centerYAdjustment: 0
        )
        let tileOutline = outlineContourPresentation(
            image: AnalysisImage(
                width: tile.width,
                height: tile.height,
                rgba: try normalizedRGBA(tile)
            ),
            actor: actor,
            background: backgroundRGB(background),
            centerYAdjustment: -229
        )
        let normalRenderPasses: Bool
        switch family {
        case .halo:
            normalRenderPasses = fullBands.center >= 0.11
                && tileBands.center >= 0.11
                && fullBands.ratio >= 0.64
                && tileBands.ratio >= 0.64
                && fullBands.margin <= 0.18
                && tileBands.margin <= 0.18
        case .outline:
            normalRenderPasses = fullBands.rim >= 0.040
                && tileBands.rim >= 0.040
                && fullBands.ratio <= 0.22
                && tileBands.ratio <= 0.22
                && fullOutline.angularCoverage >= 0.82
                && tileOutline.angularCoverage >= 0.82
        case .counterform:
            let requiredRimContrast = 0.25
            let maximumCenterRatio = 0.55
            let requiredMargin = 0.045
            normalRenderPasses = fullBands.rim >= requiredRimContrast
                && tileBands.rim >= requiredRimContrast
                && fullBands.margin >= requiredMargin
                && tileBands.margin >= requiredMargin
                && fullBands.ratio <= maximumCenterRatio
                && tileBands.ratio <= maximumCenterRatio
        default:
            normalRenderPasses = false
        }
        let requiredEccentricOffset = family == .counterform ? 0.003 : 0.010
        let requiredThicknessRange = 0.025
        let alphaBandsPass = family == .outline || (
            alphaTopology.full.allSatisfy(\.passes)
                && alphaTopology.tile.allSatisfy(\.passes)
        )
        let passes = normalRenderPasses
            && !alphaTopology.full.isEmpty
            && alphaTopology.full.count == alphaTopology.tile.count
            && alphaBandsPass
            && (alphaTopology.full.map(\.centerOffset).min() ?? 0) >= requiredEccentricOffset
            && (alphaTopology.tile.map(\.centerOffset).min() ?? 0) >= requiredEccentricOffset
            && (alphaTopology.full.map(\.thicknessRange).min() ?? 0) >= requiredThicknessRange
            && (alphaTopology.tile.map(\.thicknessRange).min() ?? 0) >= requiredThicknessRange

        return [MaterialSceneScaleTopologyMetrics(
            eventID: exemplarID,
            diameter: actor.diameter,
            eligible: actor.diameter >= 0.15,
            fullCenterContrast: fullBands.center,
            fullRimContrast: fullBands.rim,
            fullOpenCenterMargin: fullBands.margin,
            fullCenterToRimRatio: fullBands.ratio,
            tileCenterContrast: tileBands.center,
            tileRimContrast: tileBands.rim,
            tileOpenCenterMargin: tileBands.margin,
            tileCenterToRimRatio: tileBands.ratio,
            fullEccentricCenterOffset: alphaTopology.full.map(\.centerOffset).min() ?? 0,
            fullThicknessRange: alphaTopology.full.map(\.thicknessRange).min() ?? 0,
            tileEccentricCenterOffset: alphaTopology.tile.map(\.centerOffset).min() ?? 0,
            tileThicknessRange: alphaTopology.tile.map(\.thicknessRange).min() ?? 0,
            fullAlphaBands: alphaTopology.full,
            tileAlphaBands: alphaTopology.tile,
            passes: actorMaterial.family == family && passes
        )]
    }

    static func sceneScaleAlphaTopology(
        actor: ActorCompositionRecipe,
        material: ActorMaterialRecipe,
        background: BackgroundCondition,
        renderer: MaterialRenderer
    ) throws -> (
        full: [MaterialAlphaBandTopologyMetrics],
        tile: [MaterialAlphaBandTopologyMetrics]
    ) {
        let sourceScale = 2
        let sourceWidth = 393 * sourceScale
        let sourceHeight = 852 * sourceScale
        let sourceDiameter = max(1, Int(ceil(actor.diameter * Double(sourceWidth))))
        let blurRadius = actor.localBlur * Double(sourceWidth)
        let layers = try renderer.renderStructuralAlphaLayers(
            material,
            pixelSize: sourceDiameter,
            blurRadius: blurRadius
        )
        var fullMetrics = [MaterialAlphaBandTopologyMetrics]()
        var tileMetrics = [MaterialAlphaBandTopologyMetrics]()
        for (index, layer) in layers.enumerated() {
            let layerImage = try decodedPNG(layer.pngData, path: "structural-alpha-layer")
            let source = try transparentScene(
                layerImage,
                actor: actor,
                width: sourceWidth,
                height: sourceHeight
            )
            let full = try downsampled(source, width: 393, height: 852)
            guard let tile = full.cropping(
                to: CGRect(x: 0, y: 229, width: 393, height: 393)
            ) else {
                throw MaterialEvidenceError.cannotCreateContactSheet
            }
            fullMetrics.append(try organicTopologyBands(
                image: full,
                actor: actor,
                background: background,
                centerYAdjustment: 0,
                contourIndex: index,
                family: material.family
            ))
            tileMetrics.append(try organicTopologyBands(
                image: tile,
                actor: actor,
                background: background,
                centerYAdjustment: -229,
                contourIndex: index,
                family: material.family
            ))
        }
        return (fullMetrics, tileMetrics)
    }

    static func organicTopologyBands(
        image: CGImage,
        actor: ActorCompositionRecipe,
        background _: BackgroundCondition,
        centerYAdjustment: Double,
        contourIndex: Int = 0,
        family: MaterialFamily = .outline
    ) throws -> MaterialAlphaBandTopologyMetrics {
        let rgba = try normalizedRGBA(image)
        let centerX = actor.position.x * 393
        let centerY = actor.position.y * 852 + centerYAdjustment
        let diameter = actor.diameter * 393
        let support = diameter * 0.58
        let minimumX = max(0, Int(floor(centerX - support)))
        let maximumX = min(image.width - 1, Int(ceil(centerX + support)))
        let minimumY = max(0, Int(floor(centerY - support)))
        let maximumY = min(image.height - 1, Int(ceil(centerY + support)))
        var maximumAlpha = 0.0
        var weightedX = 0.0
        var weightedY = 0.0
        var weight = 0.0
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                let alpha = Double(rgba[(y * image.width + x) * 4 + 3]) / 255
                maximumAlpha = max(maximumAlpha, alpha)
                let salience = alpha * alpha
                weight += salience
                weightedX += (Double(x) + 0.5) * salience
                weightedY += (Double(y) + 0.5) * salience
            }
        }
        let contributionCenterX = weightedX / max(weight, 0.000_001)
        let contributionCenterY = weightedY / max(weight, 0.000_001)
        let centerOffset = hypot(
            contributionCenterX - centerX,
            contributionCenterY - centerY
        ) / max(diameter, 1)
        let threshold = maximumAlpha * 0.28
        var thicknesses = [Double]()
        for angleIndex in 0..<72 {
            let angle = Double(angleIndex) / 72 * Double.pi * 2
            var occupied = [Double]()
            for step in 0...180 {
                let radius = Double(step) / 180 * 0.56
                let x = Int((centerX + cos(angle) * radius * diameter).rounded(.down))
                let y = Int((centerY + sin(angle) * radius * diameter).rounded(.down))
                guard (0..<image.width).contains(x), (0..<image.height).contains(y) else { continue }
                let alpha = Double(rgba[(y * image.width + x) * 4 + 3]) / 255
                if alpha >= threshold {
                    occupied.append(radius)
                }
            }
            if let first = occupied.first, let last = occupied.last {
                thicknesses.append(last - first)
            }
        }
        let mean = thicknesses.reduce(0, +) / Double(max(thicknesses.count, 1))
        let variance = thicknesses.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
            / Double(max(thicknesses.count, 1))
        let thicknessRange = (thicknesses.max() ?? 0) - (thicknesses.min() ?? 0)
        let thicknessVariation = sqrt(variance) / max(mean, 0.000_001)
        let angularCoverage = Double(thicknesses.count) / 72
        let minimumThickness = thicknesses.min() ?? 0
        let requiredCenterOffset: Double = switch family {
        case .counterform: 0.003
        case .halo: 0.025
        default: 0.018
        }
        let requiredThicknessRange: Double = family == .counterform ? 0.025 : 0.050
        let requiredVariation: Double = family == .counterform ? 0.045 : 0.080
        return MaterialAlphaBandTopologyMetrics(
            contourIndex: contourIndex,
            centerOffset: centerOffset,
            thicknessRange: thicknessRange,
            thicknessVariation: thicknessVariation,
            angularCoverage: angularCoverage,
            minimumThickness: minimumThickness,
            passes: centerOffset >= requiredCenterOffset
                && thicknessRange >= requiredThicknessRange
                && thicknessVariation >= requiredVariation
                && angularCoverage >= 0.82
                && minimumThickness >= 0.006
        )
    }

    private static func topologyBands(
        image: CGImage,
        actor: ActorCompositionRecipe,
        material: ActorMaterialRecipe,
        background: BackgroundCondition,
        centerYAdjustment: Double
    ) throws -> (center: Double, rim: Double, margin: Double, ratio: Double) {
        let analysis = AnalysisImage(
            width: image.width,
            height: image.height,
            rgba: try normalizedRGBA(image)
        )
        let ground = backgroundRGB(background)
        let diameter = actor.diameter * 393
        let actorCenterX = actor.position.x * 393
        let actorCenterY = actor.position.y * 852 + centerYAdjustment
        let topology = material.organicTopology
        let openingAuthority = material.family == .outline
            ? topology?.contours.last?.innerCenter
            : topology?.innerCenter
        let outerAuthority = material.family == .outline
            ? topology?.contours.first?.outerCenter
            : topology?.outerCenter
        let centerX = actorCenterX + ((openingAuthority?.x ?? 0.5) - 0.5) * diameter
        let centerY = actorCenterY + ((openingAuthority?.y ?? 0.5) - 0.5) * diameter
        let rimCenterX = actorCenterX + ((outerAuthority?.x ?? 0.5) - 0.5) * diameter
        let rimCenterY = actorCenterY + ((outerAuthority?.y ?? 0.5) - 0.5) * diameter
        let outer = diameter * 0.65
        let minimumX = max(0, Int(floor(actorCenterX - outer)))
        let maximumX = min(image.width - 1, Int(ceil(actorCenterX + outer)))
        let minimumY = max(0, Int(floor(actorCenterY - outer)))
        let maximumY = min(image.height - 1, Int(ceil(actorCenterY + outer)))
        var centerSamples = [Double]()
        var rimSamples = [Double]()
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                let radialDistance = hypot(
                    Double(x) + 0.5 - centerX,
                    Double(y) + 0.5 - centerY
                ) / max(diameter, 1)
                let rimDistance = hypot(
                    Double(x) + 0.5 - rimCenterX,
                    Double(y) + 0.5 - rimCenterY
                ) / max(diameter, 1)
                let contrast = analysis.pixel(x: x, y: y).distance(to: ground)
                if radialDistance <= 0.16 {
                    centerSamples.append(contrast)
                }
                if (0.30...0.49).contains(rimDistance) {
                    rimSamples.append(contrast)
                }
            }
        }
        let center = percentile(centerSamples, fraction: 0.50)
        let rim = percentile(rimSamples, fraction: 0.75)
        return (
            center: center,
            rim: rim,
            margin: rim - center,
            ratio: center / max(rim, 0.000_1)
        )
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int((Double(sorted.count - 1) * fraction).rounded(.down)))
        )
        return sorted[index]
    }

    private static func backgroundRGB(_ condition: BackgroundCondition) -> AnalysisPixel {
        let color = MaterialRenderer.backgroundColor(for: condition)
        return AnalysisPixel(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 1
        )
    }

    private static func c3AcceptanceMetrics(
        coverage: MaterialAtlasCoverage,
        manifest: CorpusManifest,
        frozenRecipes: [Int: SceneRecipe],
        renderer: MaterialRenderer
    ) throws -> [MaterialC3FixtureAcceptance] {
        let targetIndexes: Set<Int> = [2, 8, 11, 14, 20]
        return try coverage.fixtures.filter { targetIndexes.contains($0.index) }.map { fixture in
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            guard let recipe = frozenRecipes[fixture.layoutFixtureIndex] else {
                throw MaterialEvidenceError.invalidCompositionApproval(
                    "missing frozen recipe for c3 fixture \(fixture.index)"
                )
            }
            let eligible = recipe.actors.filter { $0.diameter >= 0.15 }
            guard !eligible.isEmpty else {
                throw MaterialEvidenceError.invalidPackage(
                    "c3 fixture \(fixture.index) has no eligible actors"
                )
            }
            let actors = try eligible.map { compositionActor in
                let variants = try (1...3).map { colorCount -> ActorMaterialRecipe in
                    let actor = MaterialDNA.fixture(
                        daySeed: layout.seed,
                        eventIDs: layout.eventIDs,
                        family: fixture.family,
                        requestedColorCount: colorCount
                    ).actor(compositionActor.eventID)
                    guard let actor else {
                        throw MaterialEvidenceError.invalidPackage(
                            "missing c3 proxy actor \(compositionActor.eventID)"
                        )
                    }
                    return actor
                }
                let assessment = try assessC3Actor(
                    oneColor: variants[0],
                    twoColor: variants[1],
                    threeColor: variants[2],
                    renderer: renderer
                )
                let duplicateAssessment = try assessC3Actor(
                    oneColor: variants[0],
                    twoColor: variants[1],
                    threeColor: replacingTertiaryColorWithSecondary(variants[2]),
                    renderer: renderer
                )
                let duplicateRejected = !duplicateAssessment.passes
                return MaterialC3ActorAcceptance(
                    eventID: compositionActor.eventID,
                    diameter: compositionActor.diameter,
                    secondaryAreaFraction: assessment.secondaryAreaFraction,
                    tertiaryAreaFraction: assessment.tertiaryAreaFraction,
                    secondaryPeakDifference: assessment.secondaryPeakDifference,
                    tertiaryPeakDifference: assessment.tertiaryPeakDifference,
                    ownershipCenterDistance: assessment.ownershipCenterDistance,
                    ownershipColorDistance: assessment.ownershipColorDistance,
                    tertiaryExpectedColorDistance: assessment.tertiaryExpectedColorDistance,
                    tertiarySecondaryColorDistance: assessment.tertiarySecondaryColorDistance,
                    secondaryTertiaryPaletteDistance: assessment.secondaryTertiaryPaletteDistance,
                    duplicateTertiaryRejected: duplicateRejected,
                    passes: assessment.passes && duplicateRejected
                )
            }
            let passing = actors.filter(\.passes).count
            return MaterialC3FixtureAcceptance(
                fixtureIndex: fixture.index,
                family: fixture.family,
                eligibleActorCount: actors.count,
                passingActorCount: passing,
                passRate: Double(passing) / Double(actors.count),
                actors: actors
            )
        }
    }

    static func assessC3Actor(
        oneColor: ActorMaterialRecipe,
        twoColor: ActorMaterialRecipe,
        threeColor: ActorMaterialRecipe,
        renderer: MaterialRenderer = MaterialRenderer()
    ) throws -> C3ActorAssessment {
        guard oneColor.colors.count == 1,
              twoColor.colors.count == 2,
              threeColor.colors.count == 3
        else {
            throw MaterialEvidenceError.invalidPackage(
                "c3 assessment requires one, two, and three palette colors"
            )
        }
        let variants = try [oneColor, twoColor, threeColor].map {
            try analysisImage(actor: $0, renderer: renderer)
        }
        let secondary = colorContribution(from: variants[0], to: variants[1])
        let tertiary = colorContribution(from: variants[1], to: variants[2])
        let centerDistance = hypot(
            secondary.center.x - tertiary.center.x,
            secondary.center.y - tertiary.center.y
        )
        let ownershipColorDistance = secondary.color.distance(to: tertiary.color)
        let expectedColorDistance = tertiary.color.distance(to: threeColor.colors[2])
        let secondaryColorDistance = tertiary.color.distance(to: threeColor.colors[1])
        let paletteDistance = materialColorDistance(
            threeColor.colors[1],
            threeColor.colors[2]
        )
        let passes = secondary.areaFraction >= 0.10
            && tertiary.areaFraction >= 0.10
            && secondary.peakDifference >= 0.18
            && tertiary.peakDifference >= 0.18
            && centerDistance >= 0.16
            && ownershipColorDistance >= 0.12
            && paletteDistance >= 0.20
            && expectedColorDistance <= 0.34
            && expectedColorDistance + 0.04 <= secondaryColorDistance
        return C3ActorAssessment(
            secondaryAreaFraction: secondary.areaFraction,
            tertiaryAreaFraction: tertiary.areaFraction,
            secondaryPeakDifference: secondary.peakDifference,
            tertiaryPeakDifference: tertiary.peakDifference,
            ownershipCenterDistance: centerDistance,
            ownershipColorDistance: ownershipColorDistance,
            tertiaryExpectedColorDistance: expectedColorDistance,
            tertiarySecondaryColorDistance: secondaryColorDistance,
            secondaryTertiaryPaletteDistance: paletteDistance,
            passes: passes
        )
    }

    private static func replacingTertiaryColorWithSecondary(
        _ actor: ActorMaterialRecipe
    ) -> ActorMaterialRecipe {
        guard actor.colors.count == 3 else { return actor }
        return ActorMaterialRecipe(
            eventID: actor.eventID,
            family: actor.family,
            mutation: actor.mutation,
            colors: [actor.colors[0], actor.colors[1], actor.colors[1]],
            fields: actor.fields,
            baseOpacity: actor.baseOpacity,
            edgeSoftness: actor.edgeSoftness,
            contourWidth: actor.contourWidth,
            contourCount: actor.contourCount,
            counterformRadius: actor.counterformRadius,
            counterformSoftness: actor.counterformSoftness
        )
    }

    private static func materialColorDistance(
        _ lhs: MaterialColor,
        _ rhs: MaterialColor
    ) -> Double {
        hypot(
            hypot(lhs.red - rhs.red, lhs.green - rhs.green),
            lhs.blue - rhs.blue
        )
    }

    private static func analysisImage(
        actor: ActorMaterialRecipe,
        renderer: MaterialRenderer
    ) throws -> AnalysisImage {
        let rendered = try renderer.renderActor(actor, pixelSize: 160)
        let image = try decodedPNG(rendered.pngData, path: "analysis:\(actor.eventID)")
        return AnalysisImage(
            width: image.width,
            height: image.height,
            rgba: try normalizedRGBA(image)
        )
    }

    private static func colorContribution(
        from previous: AnalysisImage,
        to current: AnalysisImage
    ) -> ColorContributionAnalysis {
        var visibleCount = 0
        var peakDifference = 0.0
        var affected = [(difference: Double, x: Double, y: Double, color: AnalysisPixel)]()
        for y in stride(from: 0, to: current.height, by: 2) {
            for x in stride(from: 0, to: current.width, by: 2) {
                let old = previous.pixel(x: x, y: y)
                let new = current.pixel(x: x, y: y)
                guard min(old.alpha, new.alpha) >= 0.12 else { continue }
                visibleCount += 1
                let difference = old.distance(to: new)
                peakDifference = max(peakDifference, difference)
                guard difference >= 0.10 else { continue }
                affected.append((
                    difference: difference,
                    x: (Double(x) + 0.5) / Double(current.width),
                    y: (Double(y) + 0.5) / Double(current.height),
                    color: new
                ))
            }
        }
        let ownershipFloor = max(0.10, peakDifference * 0.70)
        let ownership = affected.filter { $0.difference >= ownershipFloor }
        var weight = 0.0
        var weightedX = 0.0
        var weightedY = 0.0
        var weightedRed = 0.0
        var weightedGreen = 0.0
        var weightedBlue = 0.0
        for sample in ownership {
            let salience = sample.difference * sample.difference * sample.difference
            weight += salience
            weightedX += sample.x * salience
            weightedY += sample.y * salience
            weightedRed += sample.color.red * salience
            weightedGreen += sample.color.green * salience
            weightedBlue += sample.color.blue * salience
        }
        let divisor = max(weight, 0.000_001)
        return ColorContributionAnalysis(
            areaFraction: Double(affected.count) / Double(max(visibleCount, 1)),
            peakDifference: peakDifference,
            center: CompositionPoint(x: weightedX / divisor, y: weightedY / divisor),
            color: AnalysisPixel(
                red: weightedRed / divisor,
                green: weightedGreen / divisor,
                blue: weightedBlue / divisor,
                alpha: 1
            )
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
            "contact-sheets/family-optics.png",
            "contact-sheets/material-atlas.png",
            "contact-sheets/outline-counterform.png",
            "contact-sheets/scene-scale-full.png",
            "contact-sheets/scene-scale-tile.png",
            "corpus-manifest.json",
            "metrics.json",
        ]
        for fixture in coverage.fixtures {
            let prefix = "renders/\(fixture.family.rawValue)/\(renderStem(fixture))"
            paths.insert("\(prefix)-full@\(scale)x.png")
            paths.insert("\(prefix)-tile@\(scale)x.png")
        }
        for family in MaterialFamily.allCases {
            for colorCount in 1...3 {
                paths.insert(familyCropPath(
                    family: family,
                    colorCount: colorCount,
                    scale: scale
                ))
                for background in [
                    BackgroundCondition.light,
                    .dark,
                    .lowContrast,
                ] {
                    let stem = sceneScaleStem(
                        family: family,
                        colorCount: colorCount,
                        background: background
                    )
                    paths.insert("scene-scale/\(family.rawValue)/\(stem)-full@1x.png")
                    paths.insert("scene-scale/\(family.rawValue)/\(stem)-tile@1x.png")
                }
            }
        }
        for item in exactTopologyCropCases {
            paths.insert(exactTopologyCropPath(
                fixtureIndex: item.fixtureIndex,
                family: item.family,
                eventID: item.eventID,
                scale: scale
            ))
        }
        return paths
    }

    private static func validateImagesAndCrops(
        coverage: MaterialAtlasCoverage,
        manifest: CorpusManifest,
        frozenRecipes: [Int: SceneRecipe],
        scale: Int,
        sceneScaleEvidence: SceneScaleEvidence,
        exactTopologyCropEvidence: ExactTopologyCropEvidence,
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

        let familyCrops = familyCropMetrics(manifest: manifest, scale: scale)
        for crop in familyCrops {
            let actor = MaterialDNA.fixture(
                daySeed: crop.daySeed,
                eventIDs: [crop.eventID],
                family: crop.family,
                requestedColorCount: crop.requestedColorCount
            ).actor(crop.eventID)
            guard let actor else {
                throw MaterialEvidenceError.invalidPackage("missing expected family crop actor")
            }
            let expectedData = try renderer.renderActor(
                actor,
                pixelSize: crop.pixelSize,
                background: crop.background
            ).pngData
            let actual = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(crop.path)),
                path: crop.path
            )
            let expected = try decodedPNG(expectedData, path: "expected:\(crop.path)")
            guard actual.width == crop.pixelSize,
                  actual.height == crop.pixelSize,
                  try normalizedRGBA(actual) == normalizedRGBA(expected)
            else {
                throw MaterialEvidenceError.renderPixelMismatch(crop.path)
            }
        }
        for crop in exactTopologyCropEvidence.metrics {
            guard let expectedData = exactTopologyCropEvidence.images[crop.path] else {
                throw MaterialEvidenceError.invalidPackage("missing expected exact topology crop")
            }
            let actual = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(crop.path)),
                path: crop.path
            )
            let expected = try decodedPNG(expectedData, path: "expected:\(crop.path)")
            guard actual.width == crop.pixelWidth,
                  actual.height == crop.pixelHeight,
                  try normalizedRGBA(actual) == normalizedRGBA(expected)
            else {
                throw MaterialEvidenceError.renderPixelMismatch(crop.path)
            }
        }
        let atlasPaths = coverage.fixtures.map {
            "renders/\($0.family.rawValue)/\(renderStem($0))-full@\(scale)x.png"
        }
        let structuralPaths = coverage.fixtures.filter {
            $0.family == .outline || $0.family == .counterform
        }.map {
            "renders/\($0.family.rawValue)/\(renderStem($0))-full@\(scale)x.png"
        }
        for (path, sourcePaths) in [
            ("contact-sheets/material-atlas.png", atlasPaths),
            ("contact-sheets/outline-counterform.png", structuralPaths),
        ] {
            let actual = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(path)),
                path: path
            )
            let expected = try decodedPNG(
                contactSheetData(paths: sourcePaths, directory: directory),
                path: "expected:\(path)"
            )
            guard actual.width == expected.width,
                  actual.height == expected.height,
                  try normalizedRGBA(actual) == normalizedRGBA(expected)
            else {
                throw MaterialEvidenceError.renderPixelMismatch(path)
            }
        }
        let familySheetPath = "contact-sheets/family-optics.png"
        let actualFamilySheet = try decodedPNG(
            Data(contentsOf: directory.appendingPathComponent(familySheetPath)),
            path: familySheetPath
        )
        let expectedFamilySheet = try decodedPNG(
            contactSheetData(
                paths: familyCrops.map(\.path),
                directory: directory,
                columns: 3,
                cellWidth: 180,
                cellHeight: 180
            ),
            path: "expected:\(familySheetPath)"
        )
        guard actualFamilySheet.width == expectedFamilySheet.width,
              actualFamilySheet.height == expectedFamilySheet.height,
              try normalizedRGBA(actualFamilySheet) == normalizedRGBA(expectedFamilySheet)
        else {
            throw MaterialEvidenceError.renderPixelMismatch(familySheetPath)
        }

        for metric in sceneScaleEvidence.metrics {
            guard let expectedFullData = sceneScaleEvidence.fullImages[metric.fullPath],
                  let expectedTileData = sceneScaleEvidence.tileImages[metric.tilePath]
            else {
                throw MaterialEvidenceError.invalidPackage("missing expected scene-scale image")
            }
            let actualFull = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(metric.fullPath)),
                path: metric.fullPath
            )
            let actualTile = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(metric.tilePath)),
                path: metric.tilePath
            )
            let expectedFull = try decodedPNG(expectedFullData, path: "expected:\(metric.fullPath)")
            let expectedTile = try decodedPNG(expectedTileData, path: "expected:\(metric.tilePath)")
            guard actualFull.width == 393,
                  actualFull.height == 852,
                  actualTile.width == 393,
                  actualTile.height == 393,
                  try normalizedRGBA(actualFull) == normalizedRGBA(expectedFull),
                  try normalizedRGBA(actualTile) == normalizedRGBA(expectedTile),
                  let crop = actualFull.cropping(to: CGRect(x: 0, y: 229, width: 393, height: 393)),
                  try normalizedRGBA(crop) == normalizedRGBA(actualTile)
            else {
                throw MaterialEvidenceError.renderPixelMismatch(metric.fullPath)
            }
        }
        for (path, sourcePaths, columns, cellWidth, cellHeight) in [
            (
                "contact-sheets/scene-scale-full.png",
                sceneScaleEvidence.metrics.map(\.fullPath),
                9,
                92,
                198
            ),
            (
                "contact-sheets/scene-scale-tile.png",
                sceneScaleEvidence.metrics.map(\.tilePath),
                9,
                96,
                96
            ),
        ] {
            let actual = try decodedPNG(
                Data(contentsOf: directory.appendingPathComponent(path)),
                path: path
            )
            let expected = try decodedPNG(
                contactSheetData(
                    paths: sourcePaths,
                    directory: directory,
                    columns: columns,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight
                ),
                path: "expected:\(path)"
            )
            guard actual.width == expected.width,
                  actual.height == expected.height,
                  try normalizedRGBA(actual) == normalizedRGBA(expected)
            else {
                throw MaterialEvidenceError.renderPixelMismatch(path)
            }
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

    private static func familyCropPath(
        family: MaterialFamily,
        colorCount: Int,
        scale: Int
    ) -> String {
        "actor-crops/\(family.rawValue)/\(family.rawValue)-colors-\(colorCount)@\(scale)x.png"
    }

    private static let exactTopologyCropCases: [
        (fixtureIndex: Int, family: MaterialFamily, eventID: String)
    ] = [
        (15, .halo, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
        (15, .halo, "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02"),
        (16, .halo, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
        (21, .outline, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
        (22, .outline, "2C9F4B58-ABF5-4F7E-8CA9-6D415C7B3D03"),
        (23, .outline, "4E6B83FD-19A8-4AA2-91FC-D297E6C15405"),
    ]

    private static func exactTopologyCropPath(
        fixtureIndex: Int,
        family: MaterialFamily,
        eventID: String,
        scale: Int
    ) -> String {
        let prefix = String(eventID.prefix(8))
        return "exact-topology-crops/\(fixtureIndex)-\(family.rawValue)-\(prefix)@\(scale)x.png"
    }

    private static func sceneScaleStem(
        family: MaterialFamily,
        colorCount: Int,
        background: BackgroundCondition
    ) -> String {
        "\(family.rawValue)-colors-\(colorCount)-\(background.rawValue)-layout-11"
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
            if path.hasPrefix("actor-crops/") { kind = "isolated-actor-crop" }
            else if path.hasPrefix("exact-topology-crops/") {
                kind = "exact-structural-actor-crop"
            }
            else if path.hasPrefix("scene-scale/") { kind = "scene-scale-render" }
            else if path.hasPrefix("renders/") { kind = "core-render" }
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
        directory: URL,
        columns requestedColumns: Int? = nil,
        cellWidth: Int = 132,
        cellHeight: Int = 286
    ) throws {
        try write(
            contactSheetData(
                paths: paths,
                directory: directory,
                columns: requestedColumns,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            ),
            path: outputPath,
            in: directory
        )
    }

    private static func contactSheetData(
        paths: [String],
        directory: URL,
        columns requestedColumns: Int? = nil,
        cellWidth: Int = 132,
        cellHeight: Int = 286
    ) throws -> Data {
        let columns = min(requestedColumns ?? 6, max(1, paths.count))
        let rows = Int(ceil(Double(paths.count) / Double(columns)))
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
        return data as Data
    }

    private static func decodedPNG(_ data: Data, path: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MaterialEvidenceError.cannotDecodeImage(path) }
        return image
    }

    private static func downsampled(
        _ image: CGImage,
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        return result
    }

    private static func transparentScene(
        _ layer: CGImage,
        actor: ActorCompositionRecipe,
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let centerX = actor.position.x * Double(width)
        let centerY = (1 - actor.position.y) * Double(height)
        context.draw(layer, in: CGRect(
            x: CGFloat(centerX - Double(layer.width) * 0.5),
            y: CGFloat(centerY - Double(layer.height) * 0.5),
            width: CGFloat(layer.width),
            height: CGFloat(layer.height)
        ))
        guard let result = context.makeImage() else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        return result
    }

    private static func encodedPNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MaterialEvidenceError.cannotCreateContactSheet
        }
        return data as Data
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
