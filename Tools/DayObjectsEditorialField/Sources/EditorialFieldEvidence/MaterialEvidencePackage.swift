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

public struct MaterialSampleMeasurement: Codable, Equatable, Sendable {
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
        }
    }
}

public enum MaterialEvidencePackage {
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
        sourceCommit: String,
        outputDirectory: URL,
        scale: Int = 3
    ) throws -> GeneratedMaterialEvidence {
        try validateCorpus(manifest)
        try validateCompositionApproval(compositionApprovalData, corpusVersion: manifest.version)
        try validateSourceCommit(sourceCommit)
        guard scale > 0 else { throw MaterialEvidenceError.invalidPackage("scale must be positive") }
        try prepareEmptyDirectory(outputDirectory)

        let renderer = MaterialRenderer()
        let atlasCoverage = coverage(for: manifest)
        let approvalHash = sha256(compositionApprovalData)
        var fixtureMetrics = [MaterialFixtureMetrics]()
        var atlasFullPaths = [String]()
        var structuralFullPaths = [String]()

        try write(compositionApprovalData, path: "composition-approved.json", in: outputDirectory)
        try write(manifest.canonicalJSON(), path: "corpus-manifest.json", in: outputDirectory)

        for fixture in atlasCoverage.fixtures {
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            let recipe = CompositionPlanner.make(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                viewport: .phone
            )
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
            version: "material-metrics-v1",
            fixtureCount: atlasCoverage.fixtures.count,
            coreImageCount: atlasCoverage.coreImageCount,
            compositionApprovalSHA256: approvalHash,
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
            version: "material-evidence-v1",
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
        expectedCompositionApprovalData: Data
    ) throws -> String {
        try validateSourceCommit(expectedSourceCommit)
        let packageHash = try verifySealedArtifacts(in: directory)
        let actualApproval = try Data(contentsOf: directory.appendingPathComponent("composition-approved.json"))
        guard actualApproval == expectedCompositionApprovalData else {
            throw MaterialEvidenceError.invalidPackage("composition approval bytes changed")
        }

        let decoder = JSONDecoder()
        let corpus = try decoder.decode(
            CorpusManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("corpus-manifest.json"))
        )
        try validateCorpus(corpus)
        try validateCompositionApproval(actualApproval, corpusVersion: corpus.version)
        let manifest = try decoder.decode(
            MaterialEvidenceManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        let metrics = try decoder.decode(
            MaterialEvidenceMetrics.self,
            from: Data(contentsOf: directory.appendingPathComponent("metrics.json"))
        )
        let expectedCoverage = coverage(for: corpus)
        guard manifest.version == "material-evidence-v1",
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
                scale: manifest.viewport.scale,
                renderer: MaterialRenderer()
            )
        }
        guard metrics.version == "material-metrics-v1",
              metrics.fixtureCount == expectedCoverage.fixtures.count,
              metrics.coreImageCount == expectedCoverage.coreImageCount,
              metrics.compositionApprovalSHA256 == manifest.compositionApprovalSHA256,
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
        var points = [
            CompositionPoint(x: 0.5, y: 0.5),
            CompositionPoint(x: 0.72, y: 0.5),
            CompositionPoint(x: 0.92, y: 0.5),
        ]
        points.append(contentsOf: actor.fields.map(\.focus))
        return points.map { point in
            let x = min(size - 1, max(0, Int((point.x * Double(size)).rounded(.down))))
            let y = min(size - 1, max(0, Int((point.y * Double(size)).rounded(.down))))
            let offset = (y * size + x) * 4
            let alpha = Double(rgba[offset + 3]) / 255
            let divisor = max(1, Double(rgba[offset + 3]))
            return MaterialSampleMeasurement(
                point: point,
                red: Double(rgba[offset]) / divisor,
                green: Double(rgba[offset + 1]) / divisor,
                blue: Double(rgba[offset + 2]) / divisor,
                alpha: alpha
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
        scale: Int,
        renderer: MaterialRenderer
    ) throws -> MaterialFixtureMetrics {
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let recipe = CompositionPlanner.make(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            viewport: .phone
        )
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
        struct Approval: Decodable {
            let scope: String
            let corpusVersion: String
            let evidencePackageSHA256: String
            let frozen: Bool
        }
        let approval: Approval
        do {
            approval = try JSONDecoder().decode(Approval.self, from: data)
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
        for fixture in coverage.fixtures {
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
            guard full.width == fullWidth,
                  full.height == fullHeight,
                  tile.width == fullWidth,
                  tile.height == fullWidth,
                  let expectedTile = full.cropping(to: cropRect),
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
            options: [.skipsHiddenFiles]
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
