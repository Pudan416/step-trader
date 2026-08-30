import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import EditorialFieldCore
@testable import EditorialFieldEvidence
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
        #expect(metrics.familyCrops.count == 27)
        #expect(Set(metrics.c3Acceptance.map(\.fixtureIndex)) == Set([2, 8, 11, 14, 20]))
        #expect(metrics.c3Acceptance.allSatisfy {
            $0.eligibleActorCount > 0 && $0.passRate >= 0.90
        })
        #expect(metrics.sceneScale.count == 81)
        #expect(Set(metrics.sceneScale.map(\.family)) == Set(MaterialFamily.allCases))
        #expect(Set(metrics.sceneScale.map(\.requestedColorCount)) == Set([1, 2, 3]))
        #expect(Set(metrics.sceneScale.map(\.background)) == Set([
            BackgroundCondition.light,
            .dark,
            .lowContrast,
        ]))
        #expect(metrics.sceneScale.allSatisfy {
            $0.sourceScale == 2
                && $0.pixelWidth == 393
                && $0.pixelHeight == 852
                && !$0.actors.isEmpty
                && $0.actors.contains(where: \.eligible)
                && $0.actors.allSatisfy(\.passes)
        })
        let structuralSceneScale = metrics.sceneScale.filter {
            [.halo, .outline, .counterform].contains($0.family)
        }
        #expect(structuralSceneScale.count == 27)
        #expect(structuralSceneScale.allSatisfy {
            !$0.topology.isEmpty
                && $0.topology.contains(where: \.eligible)
                && $0.topology.allSatisfy(\.passes)
        })
        #expect(metrics.sceneScale.filter {
            ![.halo, .outline, .counterform].contains($0.family)
        }.allSatisfy { $0.topology.isEmpty })
        #expect(metrics.c3Acceptance.flatMap(\.actors).allSatisfy {
            $0.duplicateTertiaryRejected && $0.passes
        })
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/material-atlas.png").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/outline-counterform.png").path
        ))
        let familyCropArtifacts = generated.manifest.artifacts.filter {
            $0.path.hasPrefix("actor-crops/") && $0.path.hasSuffix(".png")
        }
        #expect(familyCropArtifacts.count == 27)
        #expect(Set(familyCropArtifacts.map(\.kind)) == Set(["isolated-actor-crop"]))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/family-optics.png").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/scene-scale-full.png").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("contact-sheets/scene-scale-tile.png").path
        ))
        let sceneScaleArtifacts = generated.manifest.artifacts.filter {
            $0.path.hasPrefix("scene-scale/") && $0.path.hasSuffix(".png")
        }
        #expect(sceneScaleArtifacts.count == 162)
        #expect(Set(sceneScaleArtifacts.map(\.kind)) == Set(["scene-scale-render"]))

        let exemplar = try #require(metrics.sceneScale.first)
        let exemplarFull = try pixels(Data(contentsOf: directory.appendingPathComponent(exemplar.fullPath)))
        let exemplarTile = try pixels(Data(contentsOf: directory.appendingPathComponent(exemplar.tilePath)))
        #expect(exemplarFull.width == 393 && exemplarFull.height == 852)
        #expect(exemplarTile.width == 393 && exemplarTile.height == 393)
        #expect(exemplarFull.cropped(x: 0, y: (852 - 393) / 2, width: 393, height: 393) == exemplarTile)
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
            "671e1412431254056802475bf9f17074dc6b635b2ecaafe9580f04417d11f74d")
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

    @Test("critic target c3 actors expose three broad shifted color regions")
    func criticTargetC3ActorsExposeThreeBroadShiftedRegions() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let targetIndexes = Set([2, 8, 11, 14, 20])
        let fixtures = MaterialEvidencePackage.coverage(for: manifest).fixtures.filter {
            targetIndexes.contains($0.index)
        }
        #expect(Set(fixtures.map(\.index)) == targetIndexes)

        for fixture in fixtures {
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            let recipe = try #require(archive.fixtures.first {
                $0.fixtureIndex == fixture.layoutFixtureIndex
            }?.recipe)
            let eligibleActors = recipe.actors.filter { $0.diameter >= 0.15 }
            #expect(!eligibleActors.isEmpty)
            var passingActors = 0
            var diagnostics = [String]()
            for compositionActor in eligibleActors {
                let variants = try (1...3).map { count in
                    try #require(MaterialDNA.fixture(
                        daySeed: layout.seed,
                        eventIDs: layout.eventIDs,
                        family: fixture.family,
                        requestedColorCount: count
                    ).actor(compositionActor.eventID))
                }
                let assessment = try MaterialEvidencePackage.assessC3Actor(
                    oneColor: variants[0],
                    twoColor: variants[1],
                    threeColor: variants[2]
                )
                if assessment.passes { passingActors += 1 }
                diagnostics.append(
                    "\(compositionActor.eventID.prefix(8)) "
                        + "areas=\(assessment.secondaryAreaFraction)/\(assessment.tertiaryAreaFraction) "
                        + "peaks=\(assessment.secondaryPeakDifference)/\(assessment.tertiaryPeakDifference) "
                        + "center=\(assessment.ownershipCenterDistance) "
                        + "expected=\(assessment.tertiaryExpectedColorDistance) "
                        + "secondary=\(assessment.tertiarySecondaryColorDistance)"
                )
            }
            let passRate = Double(passingActors) / Double(eligibleActors.count)
            #expect(
                passRate >= 0.90,
                Comment(rawValue: "fixture \(fixture.index) \(fixture.family.rawValue) "
                    + "passed \(passingActors)/\(eligibleActors.count): "
                    + diagnostics.joined(separator: "; "))
            )
        }
    }

    @Test("c3 proxy rejects a duplicated secondary palette as tertiary ownership")
    func c3ProxyRejectsDuplicatedTertiaryAttack() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
            $0.index == 8
        })
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == fixture.layoutFixtureIndex
        }?.recipe)
        let substitutedPrefixes = Set(["0A9B16D9", "2C9F4B58", "4E6B83FD"])
        var accepted = 0

        for compositionActor in recipe.actors where compositionActor.diameter >= 0.15 {
            let variants = try (1...3).map { count in
                try #require(MaterialDNA.fixture(
                    daySeed: layout.seed,
                    eventIDs: layout.eventIDs,
                    family: fixture.family,
                    requestedColorCount: count
                ).actor(compositionActor.eventID))
            }
            let isSubstituted = substitutedPrefixes.contains(String(compositionActor.eventID.prefix(8)))
            let attackedThird = isSubstituted
                ? replacingTertiaryColorWithSecondary(variants[2])
                : variants[2]
            let assessment = try MaterialEvidencePackage.assessC3Actor(
                oneColor: variants[0],
                twoColor: variants[1],
                threeColor: attackedThird
            )
            if assessment.passes { accepted += 1 }

            if isSubstituted {
                #expect(
                    !assessment.passes,
                    "duplicate tertiary passed for \(compositionActor.eventID)"
                )
            } else {
                #expect(assessment.passes, "genuine tertiary failed for \(compositionActor.eventID)")
            }
        }
        #expect(accepted == 1, "attack must not preserve the legacy 4/4 false-positive")
    }

    @Test("same-layout c2 crops expose two broad regions for every non-solid family")
    func sameLayoutC2CropsExposeTwoBroadRegions() throws {
        let exemplar = CorpusManifest.visibleV1().breadth[0]
        let eventID = try #require(exemplar.eventIDs.first)
        let renderer = MaterialRenderer()

        for family in MaterialFamily.allCases where family != .solid {
            let oneColor = try #require(MaterialDNA.fixture(
                daySeed: exemplar.seed,
                eventIDs: [eventID],
                family: family,
                requestedColorCount: 1
            ).actor(eventID))
            let twoColor = try #require(MaterialDNA.fixture(
                daySeed: exemplar.seed,
                eventIDs: [eventID],
                family: family,
                requestedColorCount: 2
            ).actor(eventID))
            let baseImage = try pixels(renderer.renderActor(oneColor, pixelSize: 160).pngData)
            let twoColorImage = try pixels(renderer.renderActor(twoColor, pixelSize: 160).pngData)
            let secondary = colorContribution(from: baseImage, to: twoColorImage)
            let retainedBase = retainedBaseContribution(from: baseImage, to: twoColorImage)
            let centerDistance = hypot(
                secondary.center.x - retainedBase.center.x,
                secondary.center.y - retainedBase.center.y
            )
            let colorDistance = rgbDistance(secondary.color, retainedBase.color)
            let context = "\(family.rawValue): secondaryArea=\(secondary.areaFraction), "
                + "baseArea=\(retainedBase.areaFraction), peak=\(secondary.peakDifference), "
                + "center=\(centerDistance), color=\(colorDistance)"

            #expect(secondary.areaFraction >= 0.12, Comment(rawValue: context))
            #expect(retainedBase.areaFraction >= 0.12, Comment(rawValue: context))
            #expect(secondary.peakDifference >= 0.18, Comment(rawValue: context))
            #expect(centerDistance >= 0.14, Comment(rawValue: context))
            #expect(colorDistance >= 0.12, Comment(rawValue: context))
        }
    }

    @Test("mist rendering depends only on radial recipe, never event identity texture")
    func mistRenderingIsRadialAndEventIdentityInvariant() throws {
        let source = try #require(MaterialDNA.fixture(
            daySeed: 0x5157_5EED,
            eventIDs: ["mist-source"],
            family: .mist,
            requestedColorCount: 3
        ).actor("mist-source"))
        let renderer = MaterialRenderer()
        let first = replacingEventID(source, with: "mist-a")
        let second = replacingEventID(source, with: "mist-b")
        let firstData = try renderer.renderActor(first, pixelSize: 192).pngData
        let secondData = try renderer.renderActor(second, pixelSize: 192).pngData
        #expect(
            sha256Hex(firstData) == sha256Hex(secondData),
            "event identity changed pixels for an otherwise identical radial recipe"
        )

        let radial = ActorMaterialRecipe(
            eventID: "radial-mist",
            family: .mist,
            mutation: nil,
            colors: [.init(red: 0.18, green: 0.74, blue: 0.91)],
            fields: [.init(
                focus: .init(x: 0.5, y: 0.5),
                radius: 0.72,
                softness: 0.74,
                opacity: 1,
                colorIndex: 0,
                blend: .normal
            )],
            baseOpacity: 0.70,
            edgeSoftness: 0.075,
            contourWidth: 0,
            contourCount: 0,
            counterformRadius: nil,
            counterformSoftness: 0
        )
        let radialImage = try pixels(renderer.renderActor(radial, pixelSize: 192).pngData)
        let equalRadius = radialSamples(radialImage, radius: 0.24, count: 32)
        let maximumPairDistance = equalRadius.indices.flatMap { lhs in
            equalRadius.indices.filter { $0 > lhs }.map { rhs in
                rgbDistance(equalRadius[lhs], equalRadius[rhs])
            }
        }.max() ?? 0
        #expect(maximumPairDistance <= 0.008, "mist introduced non-radial texture: \(maximumPairDistance)")
    }

    @Test("luminous has a legible shifted core and outer emission unlike sphere")
    func luminousHasInternalAndOuterEmission() throws {
        let seed: UInt64 = 0x1A11_CE55
        let renderer = MaterialRenderer()
        let luminous = try #require(MaterialDNA.fixture(
            daySeed: seed,
            eventIDs: ["light"],
            family: .luminous,
            requestedColorCount: 3
        ).actor("light"))
        let sphere = try #require(MaterialDNA.fixture(
            daySeed: seed,
            eventIDs: ["light"],
            family: .sphere,
            requestedColorCount: 3
        ).actor("light"))
        let luminousImage = try pixels(renderer.renderActor(luminous, pixelSize: 192).pngData)
        let sphereImage = try pixels(renderer.renderActor(sphere, pixelSize: 192).pngData)

        let luminousCore = averageLuminance(luminousImage, around: .init(x: 0.43, y: 0.55), radius: 0.09)
        let luminousBody = averageLuminance(luminousImage, radialBand: 0.22...0.31)
        let luminousCorona = averageLuminance(luminousImage, radialBand: 0.39...0.46)
        let sphereCorona = averageLuminance(sphereImage, radialBand: 0.39...0.46)
        #expect(luminousCore - luminousBody >= 0.07)
        #expect(luminousCorona - luminousBody >= 0.04)
        #expect(luminousCorona - sphereCorona >= 0.04)
    }

    @Test("glass keeps a refractive rim visible on the low contrast field")
    func glassHasVisibleSurfaceTension() throws {
        let actor = try #require(MaterialDNA.fixture(
            daySeed: 0x61A5_5EED,
            eventIDs: ["glass"],
            family: .glass,
            requestedColorCount: 3
        ).actor("glass"))
        let renderer = MaterialRenderer()
        let transparent = try pixels(renderer.renderActor(actor, pixelSize: 192).pngData)
        let lowContrast = try pixels(renderer.renderActor(
            actor,
            pixelSize: 192,
            background: .lowContrast
        ).pngData)
        let rim = averageColor(transparent, radialBand: 0.41...0.46)
        let interior = averageColor(transparent, radialBand: 0.20...0.31)
        let background = lowContrast.pixel(x: 2, y: 2).straight
        let visibleRimFraction = radialSamples(lowContrast, radius: 0.44, count: 96).filter {
            rgbDistance($0, background) >= 0.11
        }.count

        #expect(rgbDistance(rim, interior) >= 0.10)
        #expect(Double(visibleRimFraction) / 96 >= 0.75)
    }

    @Test("fixture 23 large outline survives exact phone and tile presentation")
    func fixture23LargeOutlineSurvivesSceneScale() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
            $0.index == 23
        })
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == fixture.layoutFixtureIndex
        }?.recipe)
        let eventID = "4E6B83FD-19A8-4AA2-91FC-D297E6C15405"
        let actor = try #require(recipe.actor(eventID))
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let withoutActor = CompositionRecipe(
            daySeed: recipe.daySeed,
            grammar: recipe.grammar,
            viewport: recipe.viewport,
            actors: recipe.actors.filter { $0.eventID != eventID }
        )
        let renderer = MaterialRenderer()
        let full = try renderer.render(
            recipe: recipe,
            material: material,
            background: .light,
            configuration: .init(scale: 1)
        )
        let removed = try renderer.render(
            recipe: withoutActor,
            material: material,
            background: .light,
            configuration: .init(scale: 1)
        )
        let fullMetrics = try readabilityDifference(
            foreground: full.fullScreen.pngData,
            background: removed.fullScreen.pngData,
            expectedArea: Double.pi * pow(actor.diameter * 393 * 0.5, 2)
        )
        let tileMetrics = try readabilityDifference(
            foreground: full.calendarTile.pngData,
            background: removed.calendarTile.pngData,
            expectedArea: Double.pi * pow(actor.diameter * 393 * 0.5, 2)
        )
        let context = "full=\(fullMetrics), tile=\(tileMetrics)"

        #expect(fullMetrics.peakDifference >= 0.16, Comment(rawValue: context))
        #expect(fullMetrics.affectedAreaFraction >= 0.08, Comment(rawValue: context))
        #expect(fullMetrics.meanDifference >= 0.012, Comment(rawValue: context))
        #expect(tileMetrics.peakDifference >= 0.16, Comment(rawValue: context))
    }

    @Test("scene background contrast adjustment has no hard white wedge")
    func sceneContrastHasNoHardSpecularWedge() throws {
        let actor = try #require(MaterialDNA.fixture(
            daySeed: CorpusManifest.visibleV1().breadth[0].seed,
            eventIDs: ["sphere-wedge"],
            family: .sphere,
            requestedColorCount: 3
        ).actor("sphere-wedge"))
        let image = try pixels(MaterialRenderer().renderActor(
            actor,
            pixelSize: 192,
            background: .lowContrast
        ).pngData)
        let jump = maximumInteriorNeighbourJump(image, background: .lowContrast)
        #expect(jump <= 0.10, "hard scene-scale wedge jump \(jump)")
    }

    @Test("returned halo and outline actors keep an open center after frozen depth blur")
    func structuralFamiliesKeepOpenCentersAtExactSceneScale() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let cases: [(fixtureIndex: Int, eventID: String)] = [
            (15, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
            (15, "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02"),
            (21, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
            (23, "4E6B83FD-19A8-4AA2-91FC-D297E6C15405"),
        ]

        for item in cases {
            let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
                $0.index == item.fixtureIndex
            })
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            let approved = try #require(archive.fixtures.first {
                $0.fixtureIndex == fixture.layoutFixtureIndex
            }?.recipe)
            let actor = try #require(approved.actor(item.eventID))
            let isolated = CompositionRecipe(
                daySeed: approved.daySeed,
                grammar: approved.grammar,
                viewport: approved.viewport,
                actors: [actor]
            )
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: fixture.family,
                requestedColorCount: fixture.requestedColorCount
            )
            let actorMaterial = try #require(material.actor(item.eventID))
            let rendered = try MaterialRenderer().render(
                recipe: isolated,
                material: material,
                background: fixture.background,
                configuration: .init(scale: 2)
            )
            let full = try downsampledPixels(rendered.fullScreen.pngData, width: 393, height: 852)
            let tile = full.cropped(x: 0, y: 229, width: 393, height: 393)
            let fullMetrics = radialTopologyMetrics(
                full,
                actor: actor,
                background: fixture.background,
                centerYAdjustment: 0
            )
            let tileMetrics = radialTopologyMetrics(
                tile,
                actor: actor,
                background: fixture.background,
                centerYAdjustment: -229
            )
            let requiredMargin = actor.diameter < 0.15 ? 0.025 : 0.045
            let maximumCenterRatio = actor.diameter < 0.15 ? 0.68 : 0.55
            let requiredRimContrast = actor.diameter < 0.15 ? 0.14 : 0.25
            let maximumInteriorRatio = actorMaterial.family == .outline
                    && actorMaterial.contourCount > 1
                ? 1.10
                : 0.70
            let context = "fixture=\(item.fixtureIndex) actor=\(item.eventID.prefix(8)) "
                + "full=\(fullMetrics) tile=\(tileMetrics)"

            #expect(fullMetrics.rimContrast >= requiredRimContrast, Comment(rawValue: context))
            #expect(fullMetrics.openCenterMargin >= requiredMargin, Comment(rawValue: context))
            #expect(fullMetrics.centerToRimRatio <= maximumCenterRatio, Comment(rawValue: context))
            #expect(
                fullMetrics.interiorToRimRatio <= maximumInteriorRatio,
                Comment(rawValue: context)
            )
            #expect(tileMetrics.rimContrast >= requiredRimContrast, Comment(rawValue: context))
            #expect(tileMetrics.openCenterMargin >= requiredMargin, Comment(rawValue: context))
            #expect(tileMetrics.centerToRimRatio <= maximumCenterRatio, Comment(rawValue: context))
            #expect(
                tileMetrics.interiorToRimRatio <= maximumInteriorRatio,
                Comment(rawValue: context)
            )

            if item.fixtureIndex == 23 {
                let removedRecipe = CompositionRecipe(
                    daySeed: approved.daySeed,
                    grammar: approved.grammar,
                    viewport: approved.viewport,
                    actors: approved.actors.filter { $0.eventID != item.eventID }
                )
                let fullScene = try MaterialRenderer().render(
                    recipe: approved,
                    material: material,
                    background: fixture.background,
                    configuration: .init(scale: 2)
                )
                let removedScene = try MaterialRenderer().render(
                    recipe: removedRecipe,
                    material: material,
                    background: fixture.background,
                    configuration: .init(scale: 2)
                )
                let scenePixels = try downsampledPixels(
                    fullScene.fullScreen.pngData,
                    width: 393,
                    height: 852
                )
                let removedPixels = try downsampledPixels(
                    removedScene.fullScreen.pngData,
                    width: 393,
                    height: 852
                )
                let contribution = radialTopologyMetrics(
                    scenePixels,
                    actor: actor,
                    background: fixture.background,
                    centerYAdjustment: 0,
                    reference: removedPixels
                )
                let contributionContext = context + " contribution=\(contribution)"
                #expect(
                    contribution.rimContrast >= requiredRimContrast,
                    Comment(rawValue: contributionContext)
                )
                #expect(
                    contribution.openCenterMargin >= requiredMargin,
                    Comment(rawValue: contributionContext)
                )
                #expect(
                    contribution.centerToRimRatio <= maximumCenterRatio,
                    Comment(rawValue: contributionContext)
                )
                #expect(
                    contribution.interiorToRimRatio <= maximumInteriorRatio,
                    Comment(rawValue: contributionContext)
                )
            }
        }
    }

    @Test("gradient and mist stay filled rather than inheriting annular topology")
    func gradientAndMistRemainNonAnnularAfterSceneBlur() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let approved = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let actor = try #require(approved.actor("0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"))
        let isolated = CompositionRecipe(
            daySeed: approved.daySeed,
            grammar: approved.grammar,
            viewport: approved.viewport,
            actors: [actor]
        )

        for family in [MaterialFamily.gradient, .mist] {
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: family,
                requestedColorCount: 3
            )
            let rendered = try MaterialRenderer().render(
                recipe: isolated,
                material: material,
                background: .light,
                configuration: .init(scale: 2)
            )
            let full = try downsampledPixels(rendered.fullScreen.pngData, width: 393, height: 852)
            let metrics = radialTopologyMetrics(
                full,
                actor: actor,
                background: .light,
                centerYAdjustment: 0
            )
            #expect(
                metrics.centerToRimRatio >= 0.78,
                "\(family.rawValue) became annular: \(metrics)"
            )
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
    var luminance: Double { r * 0.2126 + g * 0.7152 + b * 0.0722 }

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

private struct PixelImage: Equatable {
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

    func cropped(x: Int, y: Int, width: Int, height: Int) -> PixelImage {
        precondition(x >= 0 && y >= 0 && x + width <= self.width && y + height <= self.height)
        var result = Data()
        result.reserveCapacity(width * height * 4)
        for row in y..<(y + height) {
            let start = (row * self.width + x) * 4
            result.append(rgba[start..<(start + width * 4)])
        }
        return PixelImage(width: width, height: height, rgba: result)
    }
}

private struct ColorContribution {
    let areaFraction: Double
    let peakDifference: Double
    let center: CompositionPoint
    let color: StraightRGB
}

private struct ReadabilityDifference: CustomStringConvertible {
    let peakDifference: Double
    let meanDifference: Double
    let affectedAreaFraction: Double

    var description: String {
        "peak=\(peakDifference), mean=\(meanDifference), area=\(affectedAreaFraction)"
    }
}

private struct RadialTopologyMetrics: CustomStringConvertible {
    let centerContrast: Double
    let interiorContrast: Double
    let rimContrast: Double

    var openCenterMargin: Double { rimContrast - centerContrast }
    var centerToRimRatio: Double { centerContrast / max(rimContrast, 0.000_001) }
    var interiorToRimRatio: Double { interiorContrast / max(rimContrast, 0.000_001) }
    var description: String {
        "center=\(centerContrast), interior=\(interiorContrast), rim=\(rimContrast), "
            + "margin=\(openCenterMargin), centerRatio=\(centerToRimRatio), "
            + "interiorRatio=\(interiorToRimRatio)"
    }
}

private func radialTopologyMetrics(
    _ image: PixelImage,
    actor: ActorCompositionRecipe,
    background: BackgroundCondition,
    centerYAdjustment: Double,
    reference: PixelImage? = nil
) -> RadialTopologyMetrics {
    let materialBackground = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: materialBackground.red,
        g: materialBackground.green,
        b: materialBackground.blue
    )
    let centerX = actor.position.x * 393
    let centerY = actor.position.y * 852 + centerYAdjustment
    let radius = actor.diameter * 393 * 0.5
    var centerSamples = [Double]()
    var interiorSamples = [Double]()
    var rimSamples = [Double]()
    let minX = max(0, Int(floor(centerX - radius * 1.05)))
    let maxX = min(image.width - 1, Int(ceil(centerX + radius * 1.05)))
    let minY = max(0, Int(floor(centerY - radius * 1.05)))
    let maxY = min(image.height - 1, Int(ceil(centerY + radius * 1.05)))
    for y in minY...maxY {
        for x in minX...maxX {
            let normalizedRadius = hypot(
                (Double(x) + 0.5 - centerX) / max(radius, 1),
                (Double(y) + 0.5 - centerY) / max(radius, 1)
            )
            let contrast = if let reference {
                rgbDistance(
                    image.pixel(x: x, y: y).straight,
                    reference.pixel(x: x, y: y).straight
                )
            } else {
                rgbDistance(image.pixel(x: x, y: y).straight, backgroundRGB)
            }
            if normalizedRadius <= 0.16 {
                centerSamples.append(contrast)
            }
            if normalizedRadius <= 0.52 {
                interiorSamples.append(contrast)
            } else if (0.60...0.98).contains(normalizedRadius) {
                rimSamples.append(contrast)
            }
        }
    }
    centerSamples.sort()
    rimSamples.sort()
    return RadialTopologyMetrics(
        centerContrast: percentile(centerSamples, fraction: 0.50),
        interiorContrast: percentile(interiorSamples, fraction: 0.50),
        rimContrast: percentile(rimSamples, fraction: 0.75)
    )
}

private func percentile(_ values: [Double], fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let index = min(values.count - 1, max(0, Int(Double(values.count - 1) * fraction)))
    return values[index]
}

private func readabilityDifference(
    foreground: Data,
    background: Data,
    expectedArea: Double
) throws -> ReadabilityDifference {
    let foregroundImage = try pixels(foreground)
    let backgroundImage = try pixels(background)
    precondition(
        foregroundImage.width == backgroundImage.width
            && foregroundImage.height == backgroundImage.height
    )
    var peak = 0.0
    var total = 0.0
    var affected = 0
    for y in 0..<foregroundImage.height {
        for x in 0..<foregroundImage.width {
            let difference = rgbDistance(
                foregroundImage.pixel(x: x, y: y).straight,
                backgroundImage.pixel(x: x, y: y).straight
            )
            peak = max(peak, difference)
            total += difference
            if difference >= 0.035 { affected += 1 }
        }
    }
    return ReadabilityDifference(
        peakDifference: peak,
        meanDifference: total / max(expectedArea, 1),
        affectedAreaFraction: Double(affected) / max(expectedArea, 1)
    )
}

private func maximumInteriorNeighbourJump(
    _ image: PixelImage,
    background: BackgroundCondition
) -> Double {
    let backgroundColor = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: backgroundColor.red,
        g: backgroundColor.green,
        b: backgroundColor.blue
    )
    var maximum = 0.0
    for y in 12..<(image.height - 12) {
        for x in 12..<(image.width - 12) {
            let u = (Double(x) + 0.5) / Double(image.width)
            let v = (Double(y) + 0.5) / Double(image.height)
            guard hypot(u - 0.5, v - 0.5) <= 0.42 else { continue }
            let center = image.pixel(x: x, y: y).straight
            guard rgbDistance(center, backgroundRGB) >= 0.04 else { continue }
            let right = image.pixel(x: x + 1, y: y).straight
            let down = image.pixel(x: x, y: y + 1).straight
            maximum = max(maximum, rgbDistance(center, right), rgbDistance(center, down))
        }
    }
    return maximum
}

private func colorContribution(from previous: PixelImage, to current: PixelImage) -> ColorContribution {
    precondition(previous.width == current.width && previous.height == current.height)
    var visibleCount = 0
    var peakDifference = 0.0
    var affected = [(difference: Double, x: Double, y: Double, color: StraightRGB)]()
    for y in stride(from: 0, to: current.height, by: 2) {
        for x in stride(from: 0, to: current.width, by: 2) {
            let old = previous.pixel(x: x, y: y)
            let new = current.pixel(x: x, y: y)
            guard min(old.alpha, new.alpha) >= 0.12 else { continue }
            visibleCount += 1
            let difference = rgbDistance(old.straight, new.straight)
            peakDifference = max(peakDifference, difference)
            guard difference >= 0.10 else { continue }
            affected.append((
                difference: difference,
                x: (Double(x) + 0.5) / Double(current.width),
                y: (Double(y) + 0.5) / Double(current.height),
                color: new.straight
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
        weightedRed += sample.color.r * salience
        weightedGreen += sample.color.g * salience
        weightedBlue += sample.color.b * salience
    }
    let divisor = max(weight, 0.000_001)
    return ColorContribution(
        areaFraction: Double(affected.count) / Double(max(visibleCount, 1)),
        peakDifference: peakDifference,
        center: CompositionPoint(x: weightedX / divisor, y: weightedY / divisor),
        color: StraightRGB(
            r: weightedRed / divisor,
            g: weightedGreen / divisor,
            b: weightedBlue / divisor
        )
    )
}

private func replacingTertiaryColorWithSecondary(
    _ actor: ActorMaterialRecipe
) -> ActorMaterialRecipe {
    precondition(actor.colors.count == 3)
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

private func replacingEventID(
    _ actor: ActorMaterialRecipe,
    with eventID: String
) -> ActorMaterialRecipe {
    ActorMaterialRecipe(
        eventID: eventID,
        family: actor.family,
        mutation: actor.mutation,
        colors: actor.colors,
        fields: actor.fields,
        baseOpacity: actor.baseOpacity,
        edgeSoftness: actor.edgeSoftness,
        contourWidth: actor.contourWidth,
        contourCount: actor.contourCount,
        counterformRadius: actor.counterformRadius,
        counterformSoftness: actor.counterformSoftness
    )
}

private func retainedBaseContribution(
    from previous: PixelImage,
    to current: PixelImage
) -> ColorContribution {
    precondition(previous.width == current.width && previous.height == current.height)
    var visibleCount = 0
    var samples = [(weight: Double, x: Double, y: Double, color: StraightRGB)]()
    for y in stride(from: 0, to: current.height, by: 2) {
        for x in stride(from: 0, to: current.width, by: 2) {
            let old = previous.pixel(x: x, y: y)
            let new = current.pixel(x: x, y: y)
            guard min(old.alpha, new.alpha) >= 0.12 else { continue }
            visibleCount += 1
            let difference = rgbDistance(old.straight, new.straight)
            guard difference <= 0.08 else { continue }
            samples.append((
                weight: max(0.001, 0.08 - difference),
                x: (Double(x) + 0.5) / Double(current.width),
                y: (Double(y) + 0.5) / Double(current.height),
                color: new.straight
            ))
        }
    }
    let totalWeight = max(samples.map(\.weight).reduce(0, +), 0.000_001)
    return ColorContribution(
        areaFraction: Double(samples.count) / Double(max(visibleCount, 1)),
        peakDifference: 0,
        center: CompositionPoint(
            x: samples.map { $0.x * $0.weight }.reduce(0, +) / totalWeight,
            y: samples.map { $0.y * $0.weight }.reduce(0, +) / totalWeight
        ),
        color: StraightRGB(
            r: samples.map { $0.color.r * $0.weight }.reduce(0, +) / totalWeight,
            g: samples.map { $0.color.g * $0.weight }.reduce(0, +) / totalWeight,
            b: samples.map { $0.color.b * $0.weight }.reduce(0, +) / totalWeight
        )
    )
}

private func averageLuminance(
    _ image: PixelImage,
    around point: CompositionPoint,
    radius: Double
) -> Double {
    let samples = pixels(image, around: point, radius: radius)
    return samples.map(\.luminance).reduce(0, +) / Double(max(samples.count, 1))
}

private func averageLuminance(_ image: PixelImage, radialBand: ClosedRange<Double>) -> Double {
    let samples = pixels(image, radialBand: radialBand)
    return samples.map(\.luminance).reduce(0, +) / Double(max(samples.count, 1))
}

private func averageColor(_ image: PixelImage, radialBand: ClosedRange<Double>) -> StraightRGB {
    let samples = pixels(image, radialBand: radialBand)
    let divisor = Double(max(samples.count, 1))
    return StraightRGB(
        r: samples.map(\.r).reduce(0, +) / divisor,
        g: samples.map(\.g).reduce(0, +) / divisor,
        b: samples.map(\.b).reduce(0, +) / divisor
    )
}

private func pixels(
    _ image: PixelImage,
    around point: CompositionPoint,
    radius: Double
) -> [StraightRGB] {
    var result = [StraightRGB]()
    for y in 0..<image.height {
        for x in 0..<image.width {
            let normalized = CompositionPoint(
                x: (Double(x) + 0.5) / Double(image.width),
                y: (Double(y) + 0.5) / Double(image.height)
            )
            guard hypot(normalized.x - point.x, normalized.y - point.y) <= radius else { continue }
            let sample = image.pixel(x: x, y: y)
            if sample.alpha >= 0.12 { result.append(sample.straight) }
        }
    }
    return result
}

private func pixels(_ image: PixelImage, radialBand: ClosedRange<Double>) -> [StraightRGB] {
    var result = [StraightRGB]()
    for y in 0..<image.height {
        for x in 0..<image.width {
            let u = (Double(x) + 0.5) / Double(image.width)
            let v = (Double(y) + 0.5) / Double(image.height)
            guard radialBand.contains(hypot(u - 0.5, v - 0.5)) else { continue }
            let sample = image.pixel(x: x, y: y)
            if sample.alpha >= 0.12 { result.append(sample.straight) }
        }
    }
    return result
}

private func radialSamples(_ image: PixelImage, radius: Double, count: Int) -> [StraightRGB] {
    (0..<count).map { index in
        let angle = Double(index) / Double(count) * Double.pi * 2
        let x = Int(((0.5 + cos(angle) * radius) * Double(image.width)).rounded(.down))
        let y = Int(((0.5 + sin(angle) * radius) * Double(image.height)).rounded(.down))
        return image.pixel(
            x: min(image.width - 1, max(0, x)),
            y: min(image.height - 1, max(0, y))
        ).straight
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

private func downsampledPixels(_ data: Data, width: Int, height: Int) throws -> PixelImage {
    let image = try decodePNG(data)
    let bytesPerRow = width * 4
    var rgba = Data(count: bytesPerRow * height)
    let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    #expect(rendered)
    return PixelImage(width: width, height: height, rgba: rgba)
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
