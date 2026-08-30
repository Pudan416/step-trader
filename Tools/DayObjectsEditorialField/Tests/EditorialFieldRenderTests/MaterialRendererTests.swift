import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import EditorialFieldCore
import EditorialFieldEvidence
@testable import EditorialFieldRender

@Suite("CoreGraphics editorial material renderer")
struct MaterialRendererTests {
    @Test("solid interior is spatially constant before edge antialiasing")
    func solidInteriorIsConstant() throws {
        let material = try #require(MaterialDNA.fixture(
            daySeed: 7,
            eventIDs: ["solid"],
            family: .solid,
            requestedColorCount: 3
        ).actor("solid"))
        let image = try pixels(MaterialRenderer().renderActor(material, pixelSize: 128).pngData)
        let samples = [(64, 64), (48, 64), (80, 64), (64, 48), (64, 80)].map {
            image.pixel(x: $0.0, y: $0.1)
        }

        #expect(Set(samples.map { $0.redByte }).count == 1)
        #expect(Set(samples.map { $0.greenByte }).count == 1)
        #expect(Set(samples.map { $0.blueByte }).count == 1)
        #expect(Set(samples.map { $0.alphaByte }).count == 1)
    }

    @Test("secondary radial fields contribute hue and chroma rather than a neutral luminance blob")
    func secondaryFieldContributesColor() throws {
        let base = fixtureActor(
            colors: [.init(red: 0.92, green: 0.08, blue: 0.16), .init(red: 0.04, green: 0.86, blue: 0.92)],
            fields: [
                .init(
                    focus: .init(x: 0.28, y: 0.40),
                    radius: 0.95,
                    softness: 0.70,
                    opacity: 1,
                    colorIndex: 0,
                    blend: .normal
                ),
            ]
        )
        let multicolor = fixtureActor(
            colors: base.colors,
            fields: base.fields + [
                .init(
                    focus: .init(x: 0.72, y: 0.55),
                    radius: 0.58,
                    softness: 0.68,
                    opacity: 0.96,
                    colorIndex: 1,
                    blend: .normal
                ),
            ]
        )
        let renderer = MaterialRenderer()
        let basePixels = try pixels(renderer.renderActor(base, pixelSize: 128).pngData)
        let multiPixels = try pixels(renderer.renderActor(multicolor, pixelSize: 128).pngData)
        let baseSample = basePixels.pixel(x: 92, y: 70).straight
        let colorSample = multiPixels.pixel(x: 92, y: 70).straight

        #expect(colorSample.chroma > 0.45)
        #expect(circularHueDistance(colorSample.hue, baseSample.hue) > 0.25)
    }

    @Test("shifted radial fields are smooth and have no angular seam")
    func radialFieldHasNoAngularSeam() throws {
        let material = fixtureActor(
            colors: [.init(red: 0.96, green: 0.20, blue: 0.44), .init(red: 0.12, green: 0.52, blue: 0.98)],
            fields: [
                .init(
                    focus: .init(x: 0.42, y: 0.47),
                    radius: 0.98,
                    softness: 0.72,
                    opacity: 1,
                    colorIndex: 0,
                    blend: .normal
                ),
                .init(
                    focus: .init(x: 0.42, y: 0.47),
                    radius: 0.62,
                    softness: 0.74,
                    opacity: 0.88,
                    colorIndex: 1,
                    blend: .screen
                ),
            ]
        )
        let image = try pixels(MaterialRenderer().renderActor(material, pixelSize: 128).pngData)
        let equalRadiusSamples = [(70, 60), (38, 60), (54, 76), (54, 44)]
            .map { image.pixel(x: $0.0, y: $0.1).straight }

        for sample in equalRadiusSamples.dropFirst() {
            #expect(rgbDistance(sample, equalRadiusSamples[0]) < 0.045)
        }

        var largestNeighbourJump = 0.0
        for x in 22..<106 {
            let lhs = image.pixel(x: x, y: 60).straight
            let rhs = image.pixel(x: x + 1, y: 60).straight
            largestNeighbourJump = max(largestNeighbourJump, rgbDistance(lhs, rhs))
        }
        #expect(largestNeighbourJump < 0.055)
    }

    @Test("transparent material silhouettes clear visibility floors on light dark and low-contrast backgrounds")
    func transparentFamiliesRemainVisible() throws {
        let transparentFamilies: [MaterialFamily] = [.glass, .mist, .halo, .luminous, .outline, .counterform]
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        let renderer = MaterialRenderer()

        for family in transparentFamilies {
            let material = try #require(MaterialDNA.fixture(
                daySeed: 0xC010_F00D,
                eventIDs: ["actor"],
                family: family,
                requestedColorCount: 3
            ).actor("actor"))
            for background in backgrounds {
                let image = try pixels(renderer.renderActor(
                    material,
                    pixelSize: 128,
                    background: background
                ).pngData)
                let backdrop = image.pixel(x: 2, y: 2).straight
                var maximumContrast = 0.0
                for y in stride(from: 12, to: 116, by: 3) {
                    for x in stride(from: 12, to: 116, by: 3) {
                        maximumContrast = max(
                            maximumContrast,
                            rgbDistance(image.pixel(x: x, y: y).straight, backdrop)
                        )
                    }
                }
                #expect(maximumContrast > 0.16, "\(family.rawValue) vanished on \(background.rawValue)")
            }
        }
    }

    @Test("outline and counterform have distinct alpha topology")
    func structuralAlphaTopologyIsDistinct() throws {
        let renderer = MaterialRenderer()
        let outline = try #require(MaterialDNA.fixture(
            daySeed: 11,
            eventIDs: ["actor"],
            family: .outline,
            requestedColorCount: 3
        ).actor("actor"))
        let counterform = try #require(MaterialDNA.fixture(
            daySeed: 11,
            eventIDs: ["actor"],
            family: .counterform,
            requestedColorCount: 3
        ).actor("actor"))
        let outlinePixels = try pixels(renderer.renderActor(outline, pixelSize: 160).pngData)
        let counterPixels = try pixels(renderer.renderActor(counterform, pixelSize: 160).pngData)

        let outlineCenter = outlinePixels.pixel(x: 80, y: 80).alpha
        let outlineMidBody = outlinePixels.pixel(x: 112, y: 80).alpha
        let outlineEdge = (145...157).map { outlinePixels.pixel(x: $0, y: 80).alpha }.max() ?? 0
        let counterCenter = counterPixels.pixel(x: 80, y: 80).alpha
        let counterMidBody = counterPixels.pixel(x: 118, y: 80).alpha

        #expect(outlineCenter < 0.05)
        #expect(outlineMidBody < 0.12)
        #expect(outlineEdge > 0.55)
        #expect(counterCenter < 0.08)
        #expect(counterMidBody > 0.55)
        #expect(counterMidBody - outlineMidBody > 0.40)
    }

    @Test("material render consumes frozen composition without changing its canonical bytes")
    func compositionBytesStayFrozen() throws {
        let recipe = CompositionPlanner.make(
            daySeed: 4_242,
            eventIDs: Array(CorpusManifest.canonicalEventIDs.prefix(5)),
            viewport: .phone
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let before = try encoder.encode(recipe)
        let material = MaterialDNA.fixture(
            daySeed: recipe.daySeed,
            eventIDs: recipe.actors.map(\.eventID),
            family: .gradient,
            requestedColorCount: 3
        )

        let rendered = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .dark,
            configuration: .init(scale: 1)
        )
        let after = try encoder.encode(recipe)

        #expect(before == after)
        #expect(rendered.fullScreen.pixelWidth == 393)
        #expect(rendered.fullScreen.pixelHeight == 852)
        #expect(rendered.calendarTile.pixelWidth == 393)
        #expect(rendered.calendarTile.pixelHeight == 393)
        let full = try decodePNG(rendered.fullScreen.pngData)
        let expectedTile = try #require(full.cropping(to: CGRect(
            x: rendered.tileCrop.x,
            y: rendered.tileCrop.y,
            width: rendered.tileCrop.width,
            height: rendered.tileCrop.height
        )))
        #expect(try rgbaBytes(expectedTile) == rgbaBytes(decodePNG(rendered.calendarTile.pngData)))
    }

    @Test("actor-local blur fades beyond the body bounds without a square clipping seam")
    func localBlurHasTransparentPadding() throws {
        let recipe = CompositionRecipe(
            daySeed: 99,
            grammar: .openField,
            viewport: .phone,
            actors: [
                ActorCompositionRecipe(
                    eventID: "blurred",
                    position: .init(x: 0.5, y: 0.5),
                    diameter: 0.5,
                    depth: 0.2,
                    localBlur: 0.04,
                    cropAllowance: 0,
                    drawOrder: 0
                ),
            ]
        )
        let material = MaterialDNA.fixture(
            daySeed: 99,
            eventIDs: ["blurred"],
            family: .solid,
            requestedColorCount: 1
        )
        let rendered = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .dark,
            configuration: .init(scale: 1)
        )
        let image = try pixels(rendered.fullScreen.pngData)
        let background = image.pixel(x: 50, y: 426).straight
        let justOutsideBody = image.pixel(x: 94, y: 426).straight
        var largestJump = 0.0
        for x in 88..<110 {
            largestJump = max(
                largestJump,
                rgbDistance(
                    image.pixel(x: x, y: 426).straight,
                    image.pixel(x: x + 1, y: 426).straight
                )
            )
        }

        #expect(rgbDistance(justOutsideBody, background) > 0.02)
        #expect(largestJump < 0.10)
    }

    @Test("material atlas coverage crosses every family with one two and three requested colors")
    func materialAtlasCoverageIsComplete() {
        let coverage = MaterialEvidencePackage.coverage(for: .visibleV1())

        #expect(coverage.fixtures.count == 27)
        #expect(coverage.coreImageCount == 54)
        #expect(Set(coverage.fixtures.map(\.family)) == Set(MaterialFamily.allCases))
        #expect(Set(coverage.fixtures.map(\.requestedColorCount)) == Set([1, 2, 3]))
        for colorCount in 1...3 {
            let backgrounds = Set(coverage.fixtures
                .filter { $0.requestedColorCount == colorCount }
                .map(\.background))
            #expect(backgrounds == Set([.light, .dark, .lowContrast]))
        }
        #expect(coverage.fixtures.filter {
            $0.family == .outline || $0.family == .counterform
        }.count == 6)
    }

    @Test("material atlas preserves frozen approval bytes and seals descriptors plus rendered samples")
    func materialAtlasWriterIsAuditable() throws {
        let testRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("editorial-material-atlas-\(UUID().uuidString)", isDirectory: true)
        let directory = testRoot
            .appendingPathComponent("atlas", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let authority = try canonicalCompositionAuthority()
        let approval = authority.approval

        let generated = try MaterialEvidencePackage.generate(
            manifest: .visibleV1(),
            compositionApprovalData: approval,
            compositionRecipeArchiveData: authority.recipes,
            sourceCommit: String(repeating: "a", count: 40),
            outputDirectory: directory,
            scale: 1
        )
        let copiedApproval = try Data(contentsOf: directory.appendingPathComponent("composition-approved.json"))
        let metrics = try JSONDecoder().decode(
            MaterialEvidenceMetrics.self,
            from: Data(contentsOf: directory.appendingPathComponent("metrics.json"))
        )

        #expect(copiedApproval == approval)
        #expect(generated.manifest.fixtureCount == 27)
        #expect(generated.manifest.coreImageCount == 54)
        #expect(metrics.fixtures.count == 27)
        #expect(metrics.fixtures.allSatisfy { !$0.actors.isEmpty })
        #expect(metrics.fixtures.flatMap(\.actors).allSatisfy { actor in
            !actor.colors.isEmpty && !actor.samples.isEmpty && actor.fields.count <= 3
        })
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/material-atlas.png").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/outline-counterform.png").path
        ))
        #expect(try MaterialEvidencePackage.verify(
            directory: directory,
            expectedSourceCommit: String(repeating: "a", count: 40),
            expectedCompositionApprovalData: approval,
            expectedCompositionRecipeArchiveData: authority.recipes
        ) == generated.packageHash)

        let metricsURL = directory.appendingPathComponent("metrics.json")
        var metricsObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: metricsURL)) as? [String: Any]
        )
        var metricFixtures = try #require(metricsObject["fixtures"] as? [[String: Any]])
        metricFixtures[0]["compositionRecipeSHA256"] = String(repeating: "f", count: 64)
        metricsObject["fixtures"] = metricFixtures
        let forgedMetrics = try canonicalJSONObject(metricsObject)
        try forgedMetrics.write(to: metricsURL, options: .atomic)

        let manifestURL = directory.appendingPathComponent("manifest.json")
        var manifestObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var artifacts = try #require(manifestObject["artifacts"] as? [[String: Any]])
        let metricsIndex = try #require(artifacts.firstIndex { ($0["path"] as? String) == "metrics.json" })
        artifacts[metricsIndex]["byteCount"] = forgedMetrics.count
        artifacts[metricsIndex]["sha256"] = SHA256.hash(data: forgedMetrics)
            .map { String(format: "%02x", $0) }
            .joined()
        manifestObject["artifacts"] = artifacts
        try canonicalJSONObject(manifestObject).write(to: manifestURL, options: .atomic)
        _ = try EvidencePackage.seal(directory: directory)

        #expect(throws: MaterialEvidenceError.self) {
            try MaterialEvidencePackage.verify(
                directory: directory,
                expectedSourceCommit: String(repeating: "a", count: 40),
                expectedCompositionApprovalData: approval,
                expectedCompositionRecipeArchiveData: authority.recipes
            )
        }
    }

    @Test("material verification rejects a checksum-valid blank full render and matching tile")
    func materialVerifierRejectsResealedBlankPixels() throws {
        let testRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("editorial-material-blank-substitution-\(UUID().uuidString)", isDirectory: true)
        let directory = testRoot.appendingPathComponent("atlas", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let authority = try canonicalCompositionAuthority()
        let approval = authority.approval
        let sourceCommit = String(repeating: "b", count: 40)

        _ = try MaterialEvidencePackage.generate(
            manifest: .visibleV1(),
            compositionApprovalData: approval,
            compositionRecipeArchiveData: authority.recipes,
            sourceCommit: sourceCommit,
            outputDirectory: directory,
            scale: 1
        )
        let fullPath = "renders/gradient/01-gradient-colors-02-dark-layout-01-full@1x.png"
        let tilePath = "renders/gradient/01-gradient-colors-02-dark-layout-01-tile@1x.png"
        try blankPNG(width: 393, height: 852).write(
            to: directory.appendingPathComponent(fullPath),
            options: .atomic
        )
        try blankPNG(width: 393, height: 393).write(
            to: directory.appendingPathComponent(tilePath),
            options: .atomic
        )
        try refreshArtifactRecordsAndSeal(
            paths: [fullPath, tilePath],
            directory: directory
        )

        #expect(throws: MaterialEvidenceError.self) {
            try MaterialEvidencePackage.verify(
                directory: directory,
                expectedSourceCommit: sourceCommit,
                expectedCompositionApprovalData: approval,
                expectedCompositionRecipeArchiveData: authority.recipes
            )
        }
    }

    @Test("material verification rejects a checksum-valid blank contact sheet")
    func materialVerifierRejectsResealedBlankContactSheet() throws {
        let authority = try canonicalCompositionAuthority()
        let testRoot = repositoryRoot()
            .appendingPathComponent("editorial-material-blank-sheet-\(UUID().uuidString)", isDirectory: true)
        let directory = testRoot.appendingPathComponent("atlas", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let sourceCommit = String(repeating: "e", count: 40)

        _ = try MaterialEvidencePackage.generate(
            manifest: .visibleV1(),
            compositionApprovalData: authority.approval,
            compositionRecipeArchiveData: authority.recipes,
            sourceCommit: sourceCommit,
            outputDirectory: directory,
            scale: 1
        )
        let sheetPath = "contact-sheets/material-atlas.png"
        try blankPNG(width: 792, height: 1_430).write(
            to: directory.appendingPathComponent(sheetPath),
            options: .atomic
        )
        try refreshArtifactRecordsAndSeal(paths: [sheetPath], directory: directory)

        #expect(throws: MaterialEvidenceError.self) {
            try MaterialEvidencePackage.verify(
                directory: directory,
                expectedSourceCommit: sourceCommit,
                expectedCompositionApprovalData: authority.approval,
                expectedCompositionRecipeArchiveData: authority.recipes
            )
        }
    }

    @Test("material atlas geometry and pixels come from the frozen recipe archive")
    func materialAtlasUsesFrozenRecipesInsteadOfLivePlanner() throws {
        let workspace = repositoryRoot()
        let approval = try Data(contentsOf: workspace.appendingPathComponent(
            "artifacts/day-objects-editorial-field/composition/composition-approved.json"
        ))
        let recipeArchive = try Data(contentsOf: workspace.appendingPathComponent(
            "artifacts/day-objects-editorial-field/composition/composition-recipes-approved.json"
        ))
        #expect(recipeArchive.count < 100_000)
        let testRoot = workspace
            .appendingPathComponent("editorial-material-frozen-recipes-\(UUID().uuidString)", isDirectory: true)
        let directory = testRoot.appendingPathComponent("atlas", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        _ = try MaterialEvidencePackage.generate(
            manifest: .visibleV1(),
            compositionApprovalData: approval,
            compositionRecipeArchiveData: recipeArchive,
            sourceCommit: String(repeating: "c", count: 40),
            outputDirectory: directory,
            scale: 1
        )
        let metrics = try JSONDecoder().decode(
            MaterialEvidenceMetrics.self,
            from: Data(contentsOf: directory.appendingPathComponent("metrics.json"))
        )
        let firstFull = try Data(contentsOf: directory.appendingPathComponent(
            "renders/gradient/00-gradient-colors-01-light-layout-00-full@1x.png"
        ))

        #expect(metrics.fixtures[0].compositionRecipeSHA256 ==
            "65eea0956acce3095862c92d27ec59aaf16ff8b6d53dfea02f0ed82e5d8d3886")
        #expect(sha256Hex(firstFull) ==
            "4a766210cb7631d5b96efa8fa9c2e21ad0e8c5ddc9e325040cfb99e6fecd16ba")
        #expect(try MaterialEvidencePackage.verify(
            directory: directory,
            expectedSourceCommit: String(repeating: "c", count: 40),
            expectedCompositionApprovalData: approval,
            expectedCompositionRecipeArchiveData: recipeArchive
        ) != "")
    }

    @Test("canonical material metrics sample visible topology and distinct secondary color for every multicolor actor")
    func materialMetricsSamplesFollowMaterialTopology() throws {
        let authority = try canonicalCompositionAuthority()
        let testRoot = repositoryRoot()
            .appendingPathComponent("editorial-material-topology-samples-\(UUID().uuidString)", isDirectory: true)
        let directory = testRoot.appendingPathComponent("atlas", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        _ = try MaterialEvidencePackage.generate(
            manifest: .visibleV1(),
            compositionApprovalData: authority.approval,
            compositionRecipeArchiveData: authority.recipes,
            sourceCommit: String(repeating: "d", count: 40),
            outputDirectory: directory,
            scale: 1
        )
        let metrics = try JSONDecoder().decode(
            MaterialEvidenceMetrics.self,
            from: Data(contentsOf: directory.appendingPathComponent("metrics.json"))
        )
        let outlineActors = metrics.fixtures
            .filter { $0.fixture.family == .outline }
            .flatMap(\.actors)
        #expect(!outlineActors.isEmpty)
        for actor in outlineActors {
            #expect(
                actor.samples.contains { $0.alpha > 0.18 },
                "outline samples missed the visible ring for \(actor.eventID)"
            )
        }

        let multicolorFixtures = metrics.fixtures.filter {
            $0.fixture.family != .solid && $0.fixture.requestedColorCount >= 2
        }
        #expect(multicolorFixtures.count == 16)
        for fixture in multicolorFixtures {
            for actor in fixture.actors {
                let minimumVisibleAlpha: Double = switch actor.family {
                case .glass, .mist, .halo, .luminous: 0.10
                case .outline, .counterform: 0.16
                case .gradient, .sphere: 0.50
                case .solid: 1
                }
                let visible = actor.samples.filter { $0.alpha >= minimumVisibleAlpha }.map {
                    StraightRGB(r: $0.red, g: $0.green, b: $0.blue)
                }
                #expect(visible.count >= 2)
                var maximumColorDistance = 0.0
                var maximumHueDistance = 0.0
                var maximumChromaDifference = 0.0
                for lhs in visible.indices {
                    for rhs in visible.indices where rhs > lhs {
                        maximumColorDistance = max(
                            maximumColorDistance,
                            rgbDistance(visible[lhs], visible[rhs])
                        )
                        if min(visible[lhs].chroma, visible[rhs].chroma) > 0.12 {
                            maximumHueDistance = max(
                                maximumHueDistance,
                                circularHueDistance(visible[lhs].hue, visible[rhs].hue)
                            )
                        }
                        maximumChromaDifference = max(
                            maximumChromaDifference,
                            abs(visible[lhs].chroma - visible[rhs].chroma)
                        )
                    }
                }
                let context = "fixture \(fixture.fixture.index) \(actor.eventID): "
                    + "rgb=\(maximumColorDistance), hue=\(maximumHueDistance), "
                    + "chroma=\(maximumChromaDifference)"
                #expect(maximumColorDistance > 0.08, Comment(rawValue: context))
                #expect(
                    maximumHueDistance > 0.04 || maximumChromaDifference > 0.06,
                    Comment(rawValue: context)
                )
                #expect(visible.contains { $0.chroma > 0.25 })
            }
        }
    }
}

private func fixtureActor(
    colors: [MaterialColor],
    fields: [RadialField]
) -> ActorMaterialRecipe {
    ActorMaterialRecipe(
        eventID: "fixture",
        family: .gradient,
        mutation: nil,
        colors: colors,
        fields: fields,
        baseOpacity: 1,
        edgeSoftness: 0.01,
        contourWidth: 0,
        contourCount: 0,
        counterformRadius: nil,
        counterformSoftness: 0
    )
}

private struct StraightRGB {
    let r: Double
    let g: Double
    let b: Double

    var chroma: Double { max(r, g, b) - min(r, g, b) }

    var hue: Double {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        guard delta > 0.000_001 else { return 0 }
        let raw: Double
        if maximum == r {
            raw = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == g {
            raw = (b - r) / delta + 2
        } else {
            raw = (r - g) / delta + 4
        }
        return (raw / 6 + 1).truncatingRemainder(dividingBy: 1)
    }
}

private struct SampledRGBA: Hashable {
    let redByte: UInt8
    let greenByte: UInt8
    let blueByte: UInt8
    let alphaByte: UInt8

    var alpha: Double { Double(alphaByte) / 255 }

    var straight: StraightRGB {
        guard alphaByte > 0 else { return StraightRGB(r: 0, g: 0, b: 0) }
        let divisor = Double(alphaByte)
        return StraightRGB(
            r: min(1, Double(redByte) / divisor),
            g: min(1, Double(greenByte) / divisor),
            b: min(1, Double(blueByte) / divisor)
        )
    }
}

private struct PixelImage {
    let width: Int
    let height: Int
    let rgba: Data

    func pixel(x: Int, y: Int) -> SampledRGBA {
        precondition((0..<width).contains(x) && (0..<height).contains(y))
        let offset = (y * width + x) * 4
        return SampledRGBA(
            redByte: rgba[offset],
            greenByte: rgba[offset + 1],
            blueByte: rgba[offset + 2],
            alphaByte: rgba[offset + 3]
        )
    }
}

private func circularHueDistance(_ lhs: Double, _ rhs: Double) -> Double {
    let delta = abs(lhs - rhs)
    return min(delta, 1 - delta)
}

private func rgbDistance(_ lhs: StraightRGB, _ rhs: StraightRGB) -> Double {
    sqrt(
        (lhs.r - rhs.r) * (lhs.r - rhs.r)
            + (lhs.g - rhs.g) * (lhs.g - rhs.g)
            + (lhs.b - rhs.b) * (lhs.b - rhs.b)
    )
}

private func decodePNG(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private func pixels(_ data: Data) throws -> PixelImage {
    let image = try decodePNG(data)
    return PixelImage(width: image.width, height: image.height, rgba: try rgbaBytes(image))
}

private func rgbaBytes(_ image: CGImage) throws -> Data {
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
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    #expect(rendered)
    return data
}

private func canonicalJSONObject(_ object: Any) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    data.append(0x0A)
    return data
}

private func blankPNG(width: Int, height: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func refreshArtifactRecordsAndSeal(paths: [String], directory: URL) throws {
    let manifestURL = directory.appendingPathComponent("manifest.json")
    var manifestObject = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    var artifacts = try #require(manifestObject["artifacts"] as? [[String: Any]])
    for path in paths {
        let data = try Data(contentsOf: directory.appendingPathComponent(path))
        let index = try #require(artifacts.firstIndex { ($0["path"] as? String) == path })
        artifacts[index]["byteCount"] = data.count
        artifacts[index]["sha256"] = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
    manifestObject["artifacts"] = artifacts
    try canonicalJSONObject(manifestObject).write(to: manifestURL, options: .atomic)
    _ = try EvidencePackage.seal(directory: directory)
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func canonicalCompositionAuthority() throws -> (approval: Data, recipes: Data) {
    let workspace = repositoryRoot()
    return (
        approval: try Data(contentsOf: workspace.appendingPathComponent(
            "artifacts/day-objects-editorial-field/composition/composition-approved.json"
        )),
        recipes: try Data(contentsOf: workspace.appendingPathComponent(
            "artifacts/day-objects-editorial-field/composition/composition-recipes-approved.json"
        ))
    )
}

private func repositoryRoot() -> URL {
    URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
