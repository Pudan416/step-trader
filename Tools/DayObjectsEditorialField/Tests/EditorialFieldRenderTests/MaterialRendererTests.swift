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
        let outlineLayer = try #require(renderer.renderStructuralAlphaLayers(
            outline,
            pixelSize: 160,
            blurRadius: 0
        ).first)
        let outlinePixels = try pixels(outlineLayer.pngData)
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

    @Test("decoded structural recipes reject malformed family topology before rendering")
    func malformedDecodedTopologyNeverRenders() throws {
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[9]
        let outline = try #require(MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 1
        ).actor("0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"))
        let outlineTopology = try #require(outline.organicTopology)
        #expect(outline.contourCount == 3)
        let firstContour = try #require(outlineTopology.contours.first)
        let halo = try #require(MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: ["halo"],
            family: .halo,
            requestedColorCount: 2
        ).actor("halo"))
        let gradient = try #require(MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: ["gradient"],
            family: .gradient,
            requestedColorCount: 2
        ).actor("gradient"))

        let malformed = [
            replacingOrganicTopology(outline, with: OrganicRadialTopology(
                outerCenter: outlineTopology.outerCenter,
                outerRadius: outlineTopology.outerRadius,
                innerCenter: outlineTopology.innerCenter,
                innerRadius: outlineTopology.innerRadius,
                contours: []
            )),
            replacingOrganicTopology(outline, with: OrganicRadialTopology(
                outerCenter: outlineTopology.outerCenter,
                outerRadius: outlineTopology.outerRadius,
                innerCenter: outlineTopology.innerCenter,
                innerRadius: outlineTopology.innerRadius,
                contours: Array(outlineTopology.contours.prefix(2))
            )),
            replacingOrganicTopology(outline, with: OrganicRadialTopology(
                outerCenter: outlineTopology.outerCenter,
                outerRadius: outlineTopology.outerRadius,
                innerCenter: outlineTopology.innerCenter,
                innerRadius: outlineTopology.innerRadius,
                contours: [
                    replacingContourCenters(
                        firstContour,
                        outerCenter: .init(x: 2, y: 2),
                        innerCenter: firstContour.innerCenter
                    ),
                ] + Array(outlineTopology.contours.dropFirst())
            )),
            replacingOrganicTopology(outline, with: OrganicRadialTopology(
                outerCenter: outlineTopology.outerCenter,
                outerRadius: outlineTopology.outerRadius,
                innerCenter: outlineTopology.innerCenter,
                innerRadius: outlineTopology.innerRadius,
                contours: [
                    replacingContourCenters(
                        firstContour,
                        outerCenter: firstContour.outerCenter,
                        innerCenter: .init(x: -1, y: -1)
                    ),
                ] + Array(outlineTopology.contours.dropFirst())
            )),
            replacingOrganicTopology(outline, with: OrganicRadialTopology(
                outerCenter: .init(
                    x: outlineTopology.outerCenter.x + 0.01,
                    y: outlineTopology.outerCenter.y
                ),
                outerRadius: outlineTopology.outerRadius,
                innerCenter: outlineTopology.innerCenter,
                innerRadius: outlineTopology.innerRadius,
                contours: outlineTopology.contours
            )),
            replacingOrganicTopology(
                halo,
                with: OrganicRadialTopology(
                    outerCenter: try #require(halo.organicTopology).outerCenter,
                    outerRadius: try #require(halo.organicTopology).outerRadius,
                    innerCenter: try #require(halo.organicTopology).innerCenter,
                    innerRadius: try #require(halo.organicTopology).innerRadius,
                    contours: [firstContour]
                )
            ),
            replacingOrganicTopology(gradient, with: outlineTopology),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let renderer = MaterialRenderer()
        for recipe in malformed {
            let decoded = try decoder.decode(
                ActorMaterialRecipe.self,
                from: encoder.encode(recipe)
            )
            #expect(throws: MaterialRendererError.self) {
                _ = try renderer.renderActor(decoded, pixelSize: 128)
            }
        }
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
        #expect(metrics.fixtures.flatMap(\.actors).allSatisfy { actor in
            let structural = [MaterialFamily.halo, .outline, .counterform].contains(actor.family)
            return structural == (actor.organicTopology != nil)
        })
        #expect(metrics.familyCrops.count == 27)
        #expect(metrics.exactTopologyCrops.count == 6)
        #expect(Set(metrics.exactTopologyCrops.map(\.fixtureIndex)) == Set([15, 16, 21, 22, 23]))
        #expect(metrics.exactTopologyCrops.allSatisfy {
            $0.scale == 1 && $0.pixelWidth > 0 && $0.pixelHeight > 0
        })
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
        #expect(structuralSceneScale.allSatisfy { scene in
            !scene.topology.isEmpty
                && scene.topology.contains(where: \.eligible)
                && scene.topology.allSatisfy { topology in
                    topology.passes
                        && !topology.fullAlphaBands.isEmpty
                        && topology.fullAlphaBands.count == topology.tileAlphaBands.count
                        && (scene.family == .outline || (
                            topology.fullAlphaBands.allSatisfy(\.passes)
                                && topology.tileAlphaBands.allSatisfy(\.passes)
                        ))
                        && topology.fullThicknessRange >= 0.025
                        && topology.tileThicknessRange >= 0.025
                }
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
        let exactTopologyArtifacts = generated.manifest.artifacts.filter {
            $0.path.hasPrefix("exact-topology-crops/") && $0.path.hasSuffix(".png")
        }
        #expect(exactTopologyArtifacts.count == 6)
        #expect(Set(exactTopologyArtifacts.map(\.kind)) == Set(["exact-structural-actor-crop"]))
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

    @Test("same-layout c2 crops preserve two owned regions, including contour pixels")
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

    @Test("mist keeps radial color ownership while stable actor-local grain survives")
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
        let repeatedData = try renderer.renderActor(first, pixelSize: 192).pngData
        #expect(
            sha256Hex(firstData) == sha256Hex(secondData),
            "event identity changed pixels for an otherwise identical radial recipe"
        )
        #expect(
            sha256Hex(firstData) == sha256Hex(repeatedData),
            "actor-local grain was not deterministic"
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
        let signature = sealedSignature(
            radialImage,
            centerX: 96,
            centerY: 96,
            radius: 192 * 0.48,
            background: .light
        )
        #expect(sealedMetrics(signature).grainEnergy >= 0.006)

        let sectorMeans = radialSectorMeans(
            radialImage,
            radialBand: 0.18...0.36,
            sectorCount: 16
        )
        let maximumAngularHueStep = sectorMeans.indices.map { index in
            circularHueDistance(
                sectorMeans[index].hue,
                sectorMeans[(index + 1) % sectorMeans.count].hue
            )
        }.max() ?? 0
        #expect(
            maximumAngularHueStep <= 0.008,
            "mist introduced an angular color seam: \(maximumAngularHueStep)"
        )
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
        _ = try #require(recipe.actor(eventID))
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let renderer = MaterialRenderer()
        let full = try renderer.render(
            recipe: recipe,
            material: material,
            background: .light,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                presentationEvidenceRequest: .perActor
            )
        )
        let fullReadability = try MaterialEvidencePackage
            .presentationSceneScaleReadabilityForTesting(
                source: full,
                recipe: recipe,
                material: material,
                background: .light
        )
        let metrics = try #require(fullReadability?.first { $0.eventID == eventID })
        #expect(!metrics.eligible)
        #expect(metrics.fullPresentation?.inFrameRayCount == 0)
        #expect(metrics.tilePresentation?.inFrameRayCount == 0)
        #expect(metrics.fullPresentation?.croppedRayCount == 96)
        #expect(metrics.tilePresentation?.croppedRayCount == 96)
        #expect(metrics.passes, Comment(rawValue: "native fixture23 metrics=\(metrics)"))
        #expect(
            try pixels(full.calendarTile.pngData)
                == pixels(full.fullScreen.pngData).cropped(
                    x: full.tileCrop.x,
                    y: full.tileCrop.y,
                    width: full.tileCrop.width,
                    height: full.tileCrop.height
                )
        )
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

    @Test("normal halo stays filled while outline keeps a cut center after frozen depth blur")
    func structuralFamiliesKeepFilledCentersAtExactSceneScale() throws {
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
                configuration: .init(
                    scale: 1,
                    supersampling: 2,
                    presentationEvidenceRequest: actorMaterial.family == .outline
                        ? .perActor
                        : .none
                )
            )
            let full = try pixels(rendered.fullScreen.pngData)
            let tile = try pixels(rendered.calendarTile.pngData)
            let fullMetrics = radialTopologyMetrics(
                full,
                actor: actor,
                material: actorMaterial,
                background: fixture.background,
                centerYAdjustment: 0
            )
            let tileMetrics = radialTopologyMetrics(
                tile,
                actor: actor,
                material: actorMaterial,
                background: fixture.background,
                centerYAdjustment: -229
            )
            let context = "fixture=\(item.fixtureIndex) actor=\(item.eventID.prefix(8)) "
                + "full=\(fullMetrics) tile=\(tileMetrics)"

            if actorMaterial.family == .halo {
                #expect(fullMetrics.centerContrast >= 0.11, Comment(rawValue: context))
                #expect(fullMetrics.centerToRimRatio >= 0.64, Comment(rawValue: context))
                #expect(fullMetrics.openCenterMargin <= 0.18, Comment(rawValue: context))
                #expect(tileMetrics.centerContrast >= 0.11, Comment(rawValue: context))
                #expect(tileMetrics.centerToRimRatio >= 0.64, Comment(rawValue: context))
                #expect(tileMetrics.openCenterMargin <= 0.18, Comment(rawValue: context))
            } else {
                let nativeReadability = try MaterialEvidencePackage
                    .presentationSceneScaleReadabilityForTesting(
                        source: rendered,
                        recipe: isolated,
                        material: material,
                        background: fixture.background
                    )
                let native = try #require(nativeReadability)
                #expect(native.allSatisfy { $0.passes }, Comment(rawValue: context))
            }

            if item.fixtureIndex == 23 {
                let fullScene = try MaterialRenderer().render(
                    recipe: approved,
                    material: material,
                    background: fixture.background,
                    configuration: .init(
                        scale: 1,
                        supersampling: 2,
                        presentationEvidenceRequest: .perActor
                    )
                )
                let nativeReadability = try MaterialEvidencePackage
                    .presentationSceneScaleReadabilityForTesting(
                        source: fullScene,
                        recipe: approved,
                        material: material,
                        background: fixture.background
                    )
                let native = try #require(nativeReadability?.first {
                    $0.eventID == actor.eventID
                })
                #expect(native.passes, Comment(rawValue: context))
            }
        }
    }

    @Test("normal exact outlines keep a visible cut contour distinct from filled bodies and counterform")
    func exactOutlinesKeepVisibleContourAccentAtSceneScale() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let cases: [(fixtureIndex: Int, eventID: String)] = [
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
                configuration: .init(
                    scale: 1,
                    supersampling: 2,
                    presentationEvidenceRequest: .perActor
                )
            )
            let full = try pixels(rendered.fullScreen.pngData)
            let tile = full.cropped(x: 0, y: 229, width: 393, height: 393)
            let fullMetrics = outlineContourAccentMetrics(
                full,
                actor: actor,
                material: actorMaterial,
                centerYAdjustment: 0
            )
            let outlineSignature = sealedSignature(
                full,
                centerX: actor.position.x * 393,
                centerY: actor.position.y * 852,
                radius: actor.diameter * 393 * 0.48,
                background: fixture.background
            )
            let context = "fixture=\(item.fixtureIndex) actor=\(item.eventID.prefix(8)) "
                + "full=\(fullMetrics) tileSize=\(tile.width)x\(tile.height)"

            let nativeReadability = try MaterialEvidencePackage
                .presentationSceneScaleReadabilityForTesting(
                    source: rendered,
                    recipe: isolated,
                    material: material,
                    background: fixture.background
                )
            let native = try #require(nativeReadability?.first)
            #expect(native.passes, Comment(rawValue: context))
            #expect(fullMetrics.angularPresence >= 0.30, Comment(rawValue: context))
            for comparisonFamily in [MaterialFamily.gradient, .counterform] {
                let comparisonMaterial = MaterialDNA.fixture(
                    daySeed: layout.seed,
                    eventIDs: layout.eventIDs,
                    family: comparisonFamily,
                    requestedColorCount: fixture.requestedColorCount
                )
                let comparisonRendered = try MaterialRenderer().render(
                    recipe: isolated,
                    material: comparisonMaterial,
                    background: fixture.background,
                    configuration: .init(scale: 1, supersampling: 2)
                )
                let comparisonFull = try pixels(comparisonRendered.fullScreen.pngData)
                let comparisonSignature = sealedSignature(
                    comparisonFull,
                    centerX: actor.position.x * 393,
                    centerY: actor.position.y * 852,
                    radius: actor.diameter * 393 * 0.48,
                    background: fixture.background
                )
                #expect(
                    sealedDistance(outlineSignature, comparisonSignature) >= 0.020,
                    Comment(rawValue: context + " comparison=\(comparisonFamily.rawValue)")
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

    @Test("returned halo and outline recipes reject mechanical concentric topology")
    func returnedStructuralRecipesAreEccentricAtNativeScale() throws {
        let manifest = CorpusManifest.visibleV1()
        let cases: [(fixtureIndex: Int, eventID: String)] = [
            (15, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
            (15, "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02"),
            (16, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
            (21, "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"),
            (22, "2C9F4B58-ABF5-4F7E-8CA9-6D415C7B3D03"),
            (23, "4E6B83FD-19A8-4AA2-91FC-D297E6C15405"),
        ]

        for item in cases {
            let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
                $0.index == item.fixtureIndex
            })
            let layout = manifest.breadth[fixture.layoutFixtureIndex]
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: fixture.family,
                requestedColorCount: fixture.requestedColorCount
            )
            let actorMaterial = try #require(material.actor(item.eventID))
            let renderedBands: [PixelImage]
            if actorMaterial.family == .halo || actorMaterial.family == .outline {
                renderedBands = try MaterialRenderer().renderStructuralAlphaLayers(
                    actorMaterial,
                    pixelSize: 384,
                    blurRadius: 0
                ).map { try pixels($0.pngData) }
            } else {
                renderedBands = [try pixels(MaterialRenderer().renderActor(
                    actorMaterial,
                    pixelSize: 384
                ).pngData)]
            }
            let topology = try #require(actorMaterial.organicTopology)
            let authorityOffset: Double
            let authorityBandWidth: Double?
            if actorMaterial.family == .outline {
                let outermost = try #require(topology.contours.first)
                authorityOffset = hypot(
                    outermost.innerCenter.x - outermost.outerCenter.x,
                    outermost.innerCenter.y - outermost.outerCenter.y
                )
                authorityBandWidth = outermost.outerRadius - outermost.innerRadius
            } else {
                authorityOffset = hypot(
                    topology.innerCenter.x - topology.outerCenter.x,
                    topology.innerCenter.y - topology.outerCenter.y
                )
                authorityBandWidth = nil
            }

            if actorMaterial.family == .outline {
                let output = try pixels(MaterialRenderer().renderActor(
                    actorMaterial,
                    pixelSize: 384,
                    background: .light
                ).pngData)
                let signature = sealedSignature(
                    output,
                    centerX: 192,
                    centerY: 192,
                    radius: 384 * 0.48,
                    background: .light
                )
                let metrics = sealedMetrics(signature)
                let context = "fixture=\(item.fixtureIndex) actor=\(item.eventID.prefix(8)) \(metrics)"
                #expect(metrics.centerToRimRatio <= 0.22, Comment(rawValue: context))
                #expect(metrics.activeAreaFraction <= 0.34, Comment(rawValue: context))
                #expect(
                    sealedOutlineContinuity(signature).supportedAngularCoverage >= 0.82,
                    Comment(rawValue: context)
                )
            } else {
                for (bandIndex, image) in renderedBands.enumerated() {
                    let metrics = organicRimMetrics(image)
                    let context = "fixture=\(item.fixtureIndex) actor=\(item.eventID.prefix(8)) band=\(bandIndex) \(metrics)"
                    #expect(metrics.alphaCentroidOffset >= 0.045, Comment(rawValue: context))
                    #expect(metrics.alphaCentroidOffset <= 0.16, Comment(rawValue: context))
                    #expect(metrics.thicknessRange >= 0.080, Comment(rawValue: context))
                    #expect(metrics.thicknessVariation >= 0.18, Comment(rawValue: context))
                    #expect(metrics.angularCoverage >= 0.88, Comment(rawValue: context))
                    #expect(metrics.minimumThickness >= 0.010, Comment(rawValue: context))
                }
            }
            if let authorityBandWidth {
                let presentationFloor = 2.0 / 384.0
                let authoredFractionFloor = authorityBandWidth * 0.45
                #expect(authorityOffset >= max(presentationFloor, authoredFractionFloor))
                #expect(authorityOffset < authorityBandWidth)
            } else {
                #expect(authorityOffset >= 0.10)
            }
        }
    }

    @Test("multi-outline uses unequal related circle spacing")
    func multiOutlineSpacingIsNotMechanical() throws {
        let manifest = CorpusManifest.visibleV1()
        let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
            $0.index == 21
        })
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 1
        )
        let actor = try #require(material.actor("0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"))
        #expect(actor.contourCount == 3)
        let layers = try MaterialRenderer().renderStructuralAlphaLayers(
            actor,
            pixelSize: 512,
            blurRadius: 0
        ).map { try pixels($0.pngData) }
        let image = try #require(combinedAlphaImage(layers))
        let imbalance = maximumContourSpacingImbalance(image)
        let normalizedImbalance = imbalance / max(actor.contourWidth, 0.000_001)

        let topology = try #require(actor.organicTopology)
        let outerCenters = topology.contours.map(\.outerCenter)
        let centerSpan = outerCenters.enumerated().flatMap { lhsIndex, lhs in
            outerCenters.dropFirst(lhsIndex + 1).map { rhs in
                hypot(lhs.x - rhs.x, lhs.y - rhs.y)
            }
        }.max() ?? 0

        let controlCenter = CompositionPoint(x: 0.5, y: 0.5)
        let controlBandWidth = actor.contourWidth * 0.10
        let controlCenterGap = actor.contourWidth * 0.32
        let controlContours = (0..<actor.contourCount).map { index in
            let outerRadius = 0.475 - Double(index) * (controlBandWidth + controlCenterGap)
            return OrganicRadialContour(
                outerCenter: controlCenter,
                outerRadius: outerRadius,
                innerCenter: controlCenter,
                innerRadius: outerRadius - controlBandWidth,
                opacity: 1
            )
        }
        let controlActor = replacingOrganicTopology(
            actor,
            with: OrganicRadialTopology(
                outerCenter: controlCenter,
                outerRadius: controlContours[0].outerRadius,
                innerCenter: controlCenter,
                innerRadius: controlContours[controlContours.count - 1].innerRadius,
                contours: controlContours
            )
        )
        let controlLayers = try MaterialRenderer().renderStructuralAlphaLayers(
            controlActor,
            pixelSize: 512,
            blurRadius: 0
        ).map { try pixels($0.pngData) }
        let controlImage = try #require(combinedAlphaImage(controlLayers))
        let controlNormalizedImbalance = maximumContourSpacingImbalance(controlImage)
            / max(controlActor.contourWidth, 0.000_001)

        #expect(normalizedImbalance >= 0.25, "mechanical equal contour spacing: \(normalizedImbalance)")
        #expect(controlNormalizedImbalance < 0.25)
        #expect(centerSpan >= 2.0 / 512.0, "nested contours share one target center: \(centerSpan)")
        #expect(centerSpan < actor.contourWidth)
    }

    @Test("organic topology proxy rejects a perfect mechanical torus")
    func organicProxyRejectsMechanicalRingControl() {
        let metrics = organicRimMetrics(mechanicalRingControl(size: 384))

        #expect(metrics.alphaCentroidOffset < 0.006)
        #expect(metrics.thicknessRange < 0.012)
        #expect(metrics.thicknessVariation < 0.04)
    }

    @Test("packaged topology proxy rejects concentric alpha under shifted chroma")
    func packagedProxyRejectsChromaShiftedConcentricAlpha() throws {
        let actor = ActorCompositionRecipe(
            eventID: "concentric-attack",
            position: .init(x: 0.5, y: 0.5),
            diameter: 0.72,
            depth: 0.5,
            localBlur: 0,
            cropAllowance: 0,
            drawOrder: 0
        )
        let image = try concentricTorusWithShiftedChroma(
            width: 393,
            height: 393,
            center: .init(x: 196.5, y: 197),
            diameter: actor.diameter * 393
        )
        let assessment = try MaterialEvidencePackage.organicTopologyBands(
            image: image,
            actor: actor,
            background: .dark,
            centerYAdjustment: -229
        )

        #expect(
            assessment.centerOffset < 0.010 || assessment.thicknessRange < 0.025,
            "concentric alpha false-passed through chroma: \(assessment)"
        )
        #expect(!assessment.passes)
    }

    @Test("post-blur alpha evidence isolates every outline contour and ignores RGB")
    func postBlurAlphaEvidenceIsPerContourAndColorIndependent() throws {
        let manifest = CorpusManifest.visibleV1()
        let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
            $0.index == 21
        })
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let actorID = "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801"
        let actor = try #require(MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 1
        ).actor(actorID))
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let composition = try #require(archive.fixtures.first {
            $0.fixtureIndex == fixture.layoutFixtureIndex
        }?.recipe.actor(actorID))
        let sourceDiameter = Int(ceil(composition.diameter * 393 * 2))
        let blurRadius = composition.localBlur * 393 * 2
        let shiftedChroma = replacingSurface(
            actor,
            colors: [
                .init(red: 0.98, green: 0.04, blue: 0.15),
                .init(red: 0.02, green: 0.82, blue: 0.98),
            ],
            fields: [
                .init(
                    focus: .init(x: 0.77, y: 0.24),
                    radius: 0.48,
                    softness: 0.66,
                    opacity: 1,
                    colorIndex: 1,
                    blend: .normal
                ),
            ]
        )
        let renderer = MaterialRenderer()
        let baseLayers = try renderer.renderStructuralAlphaLayers(
            actor,
            pixelSize: sourceDiameter,
            blurRadius: blurRadius
        )
        let shiftedLayers = try renderer.renderStructuralAlphaLayers(
            shiftedChroma,
            pixelSize: sourceDiameter,
            blurRadius: blurRadius
        )

        #expect(baseLayers.count == actor.contourCount)
        #expect(shiftedLayers.count == actor.contourCount)
        for (base, shifted) in zip(baseLayers, shiftedLayers) {
            #expect(try alphaBytes(base.pngData) == alphaBytes(shifted.pngData))
        }
    }

    @Test("scene-scale structural alpha bands survive every family and palette count")
    func structuralAlphaBandsSurviveSceneScaleMatrix() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let actor = try #require(recipe.actor("5FA2D140-7C0E-45B9-BE3D-8124A937EF06"))

        for family in [MaterialFamily.halo, .outline, .counterform] {
            for colorCount in 1...3 {
                let material = MaterialDNA.fixture(
                    daySeed: layout.seed,
                    eventIDs: layout.eventIDs,
                    family: family,
                    requestedColorCount: colorCount
                )
                let actorMaterial = try #require(material.actor(actor.eventID))
                let topology = try MaterialEvidencePackage.sceneScaleAlphaTopology(
                    actor: actor,
                    material: actorMaterial,
                    background: .lowContrast,
                    renderer: MaterialRenderer()
                )
                let context = "\(family.rawValue)/c\(colorCount) full=\(topology.full) tile=\(topology.tile)"
                #expect(!topology.full.isEmpty, Comment(rawValue: context))
                #expect(topology.full.count == topology.tile.count, Comment(rawValue: context))
                if family != .outline {
                    #expect(topology.full.allSatisfy { $0.passes }, Comment(rawValue: context))
                    #expect(topology.tile.allSatisfy { $0.passes }, Comment(rawValue: context))
                }
                for background in [BackgroundCondition.light, .dark, .lowContrast] {
                    let sceneTopology = try MaterialEvidencePackage.sceneScaleTopology(
                        family: family,
                        recipe: recipe,
                        material: material,
                        background: background,
                        renderer: MaterialRenderer()
                    )
                    let sceneContext = "\(family.rawValue)/c\(colorCount)/\(background.rawValue) \(sceneTopology)"
                    #expect(sceneTopology.allSatisfy { $0.passes }, Comment(rawValue: sceneContext))
                    #expect(!sceneTopology.isEmpty, Comment(rawValue: sceneContext))
                    let containsEligibleTopology = sceneTopology.contains { $0.eligible }
                    #expect(containsEligibleTopology, Comment(rawValue: sceneContext))
                    for topology in sceneTopology {
                        let aggregateContext = [
                            "family=\(family.rawValue)",
                            "c\(colorCount)",
                            "background=\(background.rawValue)",
                            "event=\(topology.eventID)",
                            "eligible=\(topology.eligible)",
                            "passes=\(topology.passes)",
                            "fullAlphaBands=\(topology.fullAlphaBands)",
                            "tileAlphaBands=\(topology.tileAlphaBands)",
                            "fullThicknessRange=\(topology.fullThicknessRange)",
                            "tileThicknessRange=\(topology.tileThicknessRange)",
                        ].joined(separator: " ")
                        #expect(topology.passes, Comment(rawValue: aggregateContext))
                        #expect(!topology.fullAlphaBands.isEmpty, Comment(rawValue: aggregateContext))
                        #expect(
                            topology.fullAlphaBands.count == topology.tileAlphaBands.count,
                            Comment(rawValue: aggregateContext)
                        )
                        if family != .outline {
                            let fullAlphaBandsPass = topology.fullAlphaBands.allSatisfy { $0.passes }
                            let tileAlphaBandsPass = topology.tileAlphaBands.allSatisfy { $0.passes }
                            #expect(
                                fullAlphaBandsPass,
                                Comment(rawValue: aggregateContext)
                            )
                            #expect(
                                tileAlphaBandsPass,
                                Comment(rawValue: aggregateContext)
                            )
                        }
                        #expect(
                            topology.fullThicknessRange >= 0.025,
                            Comment(rawValue: aggregateContext)
                        )
                        #expect(
                            topology.tileThicknessRange >= 0.025,
                            Comment(rawValue: aggregateContext)
                        )
                    }
                }
            }
        }
    }

    @Test("fixture 11 outline presentation separates identity from intentional crop and overlap")
    func fixture11OutlinePresentationSeparatesIdentityFromCropAndOverlap() throws {
        // Regressions caught here: deliberate crop being mistaken for a broken
        // contour, an overlapping neighbour impersonating actor ownership, a
        // true in-frame arc break passing continuity, and final low-contrast
        // blur erasing an otherwise authored/open contour.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let actors = recipe.actors.filter { $0.diameter >= 0.15 }
        let renderer = MaterialRenderer()
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        var failures = [String]()
        var observations = [String: Fixture11OutlinePresentationMetrics]()

        for colorCount in 1...3 {
            let dna = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .outline,
                requestedColorCount: colorCount
            )
            for background in backgrounds {
                let presented = try renderer.render(
                    recipe: recipe,
                    material: dna,
                    background: background,
                    configuration: .init(
                        scale: 1,
                        supersampling: 2,
                        presentationEvidenceRequest: .perActor
                    )
                )
                let composed = try pixels(presented.fullScreen.pngData)
                let presentationEvidence = try #require(presented.presentationEvidence)
                for actor in actors {
                    let material = try #require(dna.actor(actor.eventID))
                    let actorEvidence = try #require(
                        presentationEvidence.actors.first { $0.eventID == actor.eventID }
                    )
                    let isolated = try pixels(actorEvidence.isolated.fullScreen.pngData)
                    let alphaLayers = try renderer.renderStructuralAlphaLayers(
                        material,
                        pixelSize: actorPixelDiameter(actor),
                        blurRadius: actor.localBlur * 393
                    ).map { try pixels($0.pngData) }
                    let alpha = try #require(combinedAlphaImage(alphaLayers))
                    let metrics = fixture11OutlinePresentationMetrics(
                        alpha: alpha,
                        isolated: isolated,
                        composed: composed,
                        actor: actor,
                        background: background
                    )
                    let key = "c\(colorCount)/\(background.rawValue)/\(actor.eventID.prefix(4))"
                    observations[key] = metrics
                    if metrics.identityCoverage < 0.82 || metrics.percentile90Contrast < 0.16 {
                        failures.append(
                            "\(key) p90=\(metrics.percentile90Contrast) "
                                + "identityCoverage=\(metrics.identityCoverage) "
                                + "eligible=\(metrics.eligibleRays) owned=\(metrics.identitySupportedRays) "
                                + "composedOwned=\(metrics.composedOwnedCoverage) "
                                + "rawComposed=\(metrics.rawComposedCoverage)"
                        )
                    }

                    let direct = try pixels(renderer.renderActor(
                        material,
                        pixelSize: actorPixelDiameter(actor),
                        background: background
                    ).pngData)
                    let signature = sealedSignature(
                        direct,
                        centerX: Double(direct.width) * 0.5,
                        centerY: Double(direct.height) * 0.5,
                        radius: Double(actorPixelDiameter(actor)) * 0.48,
                        background: background
                    )
                    #expect(sealedMetrics(signature).centerToRimRatio <= 0.22)
                    #expect(material.colors.count == colorCount)
                }
            }
        }

        for prefix in ["0A9B", "4E6B", "71E4"] {
            for (key, metrics) in observations
            where key.hasSuffix(prefix) && metrics.percentile90Contrast >= 0.16 {
                #expect(
                    metrics.identityCoverage >= 0.82,
                    Comment(rawValue: "intentional crop failed identity \(key): \(metrics)")
                )
            }
        }

        let controlActor = try #require(actors.first { $0.eventID.hasPrefix("82F5") })
        let controlDNA = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let controlMaterial = try #require(controlDNA.actor(controlActor.eventID))
        let controlRecipe = CompositionRecipe(
            daySeed: recipe.daySeed,
            grammar: recipe.grammar,
            viewport: recipe.viewport,
            actors: [controlActor]
        )
        let controlImage = try pixels(renderer.render(
            recipe: controlRecipe,
            material: controlDNA,
            background: .dark,
            configuration: .init(scale: 1)
        ).fullScreen.pngData)
        let controlAlpha = try #require(combinedAlphaImage(
            try renderer.renderStructuralAlphaLayers(
                controlMaterial,
                pixelSize: actorPixelDiameter(controlActor),
                blurRadius: controlActor.localBlur * 393
            ).map { try pixels($0.pngData) }
        ))
        let brokenAlpha = fixture11BrokenArcMutation(controlAlpha)
        let brokenImage = fixture11ArcColorMutation(
            controlImage,
            actor: controlActor,
            color: MaterialRenderer.backgroundColor(for: .dark)
        )
        let neighbourImage = fixture11ArcColorMutation(
            brokenImage,
            actor: controlActor,
            color: .init(red: 1, green: 1, blue: 1)
        )
        let broken = fixture11OutlinePresentationMetrics(
            alpha: brokenAlpha,
            isolated: brokenImage,
            composed: brokenImage,
            actor: controlActor,
            background: .dark
        )
        let overlap = fixture11OutlinePresentationMetrics(
            alpha: brokenAlpha,
            isolated: brokenImage,
            composed: neighbourImage,
            actor: controlActor,
            background: .dark
        )
        #expect(broken.identityCoverage < 0.82)
        #expect(overlap.rawComposedCoverage > broken.rawComposedCoverage)
        #expect(overlap.composedOwnedCoverage < 0.82)

        let alphaFixture = (0...255).map { alphaValue in
            let alpha = UInt8(alphaValue)
            return OutlineVisibilityPixel(
                red: UInt8(alphaValue * 193 / 255),
                green: UInt8(alphaValue * 117 / 255),
                blue: UInt8(alphaValue * 61 / 255),
                alpha: alpha
            )
        }
        let adjustedAlphaFixture = alphaFixture.map {
            MaterialRenderer.outlineVisibilityPixel($0, background: .init(
                red: 0.49,
                green: 0.50,
                blue: 0.47
            ))
        }
        let originalAlpha = alphaFixture.map(\.alpha)
        let adjustedAlpha = adjustedAlphaFixture.map(\.alpha)
        #expect(originalAlpha == adjustedAlpha)
        #expect(fixture11AlphaHistogram(originalAlpha) == fixture11AlphaHistogram(adjustedAlpha))
        #expect(fixture11AlphaQuantiles(originalAlpha) == fixture11AlphaQuantiles(adjustedAlpha))
        #expect(zip(alphaFixture, adjustedAlphaFixture).contains { lhs, rhs in
            lhs.red != rhs.red || lhs.green != rhs.green || lhs.blue != rhs.blue
        })
        let alphaScalingMutation = adjustedAlphaFixture.map { pixel in
            OutlineVisibilityPixel(
                red: pixel.red,
                green: pixel.green,
                blue: pixel.blue,
                alpha: UInt8((Double(pixel.alpha) * 0.75).rounded())
            )
        }
        #expect(alphaScalingMutation.map(\.alpha) != adjustedAlpha)

        let lowContrast = MaterialColor(red: 0.49, green: 0.50, blue: 0.47)
        let representativeColors = [
            MaterialColor(red: 0.812, green: 0.938, blue: 0.188),
            MaterialColor(red: 0.438, green: 0.594, blue: 0.125),
            MaterialColor(red: 0.412, green: 0.559, blue: 0.088),
            MaterialColor(red: 0.083, green: 0.222, blue: 0.611),
        ]
        for color in representativeColors {
            let target = MaterialRenderer.outlineVisibilityTarget(
                color: color,
                background: lowContrast
            )
            let adjusted = MaterialRenderer.outlineVisibilityAdjustedColor(
                color,
                alpha: 0.125,
                background: lowContrast
            )
            #expect(fixture11CompositedDistance(
                adjusted,
                alpha: 0.125,
                background: lowContrast
            ) >= fixture11CompositedDistance(
                color,
                alpha: 0.125,
                background: lowContrast
            ))
            #expect((0...1).contains(target.red))
            #expect((0...1).contains(target.green))
            #expect((0...1).contains(target.blue))
            #expect(fixture11ProjectionCrossMagnitude(
                color: color,
                target: target,
                background: lowContrast
            ) <= 0.000_001)
        }

        #expect(
            failures.isEmpty,
            Comment(rawValue: "fixture11 presentation failures=\(failures.count)\n" + failures.joined(separator: "\n"))
        )
    }

    @Test("default outline visibility placement is byte-identical to explicit none")
    func defaultOutlineVisibilityPlacementIsExplicitRawOutput() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let dna = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let renderer = MaterialRenderer()
        let defaultOutput = try renderer.render(
            recipe: recipe,
            material: dna,
            background: .lowContrast,
            configuration: .init(scale: 2)
        )
        let explicitRaw = try renderer.render(
            recipe: recipe,
            material: dna,
            background: .lowContrast,
            configuration: .init(
                scale: 2,
                outlineVisibilityPlacement: .none
            )
        )

        #expect(defaultOutput.fullScreen.pngData == explicitRaw.fullScreen.pngData)
        #expect(defaultOutput.calendarTile.pngData == explicitRaw.calendarTile.pngData)
        #expect(defaultOutput.tileCrop == explicitRaw.tileCrop)
        #expect(defaultOutput.drawSequence == explicitRaw.drawSequence)
    }

    @Test("scene-scale evidence consumes renderer-owned presentation bytes")
    func sceneScaleEvidenceMatchesRendererPresentationBytes() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let renderer = MaterialRenderer()
        let direct = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(scale: 1, supersampling: 2)
        )
        let evidence = try MaterialEvidencePackage.sceneScaleRenderedScene(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            renderer: renderer
        )

        #expect(evidence.fullScreen.pngData == direct.fullScreen.pngData)
        #expect(evidence.calendarTile.pngData == direct.calendarTile.pngData)
        #expect(evidence.tileCrop == direct.tileCrop)
        #expect(evidence.drawSequence == direct.drawSequence)
        let full = try pixels(direct.fullScreen.pngData)
        #expect(try pixels(direct.calendarTile.pngData) ==
            full.cropped(x: 0, y: 229, width: 393, height: 393))

        let actor = try #require(recipe.actors.first { $0.eventID.hasPrefix("4E6B") })
        let actorMaterial = try #require(material.actor(actor.eventID))
        let directActor = try pixels(renderer.renderActor(
            actorMaterial,
            pixelSize: actorPixelDiameter(actor),
            background: .lowContrast,
            supersampling: 2
        ).pngData)
        let signature = sealedSignature(
            directActor,
            centerX: Double(directActor.width) * 0.5,
            centerY: Double(directActor.height) * 0.5,
            radius: Double(directActor.width) * 0.48,
            background: .lowContrast
        )
        #expect(sealedMetrics(signature).centerToRimRatio <= 0.22)
        #expect(sealedOutlineContinuity(signature).supportedAngularCoverage >= 0.82)
    }

    @Test("fixture 11 outline modes expose one deterministic same-render authority trace")
    func fixture11OutlineCapturedPrefixesEliminateRecursiveCounterfactualRenders() throws {
        // Both legacy mode values must resolve to the sole authoritative path:
        // actor layers captured by the canonical supersampled render, followed
        // by the same whole-scene downsample. Neither value may resurrect a
        // recursive or counterfactual render.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        #expect(recipe.actors.count == 10)
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let renderer = MaterialRenderer()
        let referenceInstrumentation = MaterialRenderInstrumentation()
        let reference = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                outlineCounterfactualMode: .actorRemovedReference,
                instrumentation: referenceInstrumentation
            )
        )
        let capturedInstrumentation = MaterialRenderInstrumentation()
        let captured = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                outlineCounterfactualMode: .capturedActorReplay,
                instrumentation: capturedInstrumentation
            )
        )
        let expectedOrder = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }.map(\.eventID)
        let referenceTrace = try #require(referenceInstrumentation.ownershipTrace)
        let capturedTrace = try #require(capturedInstrumentation.ownershipTrace)
        let referenceAlpha = try alphaBytes(reference.fullScreen.pngData)
        let capturedAlpha = try alphaBytes(captured.fullScreen.pngData)

        let referencePixels = try pixels(reference.fullScreen.pngData)
        let capturedPixels = try pixels(captured.fullScreen.pngData)
        if let firstPixelIndex = (0..<(referencePixels.width * referencePixels.height)).first(
            where: { pixelIndex in
                let offset = pixelIndex * 4
                return (0..<4).contains { channel in
                    referencePixels.rgba[offset + channel] != capturedPixels.rgba[offset + channel]
                }
            }
        ) {
            let x = firstPixelIndex % referencePixels.width
            let y = firstPixelIndex / referencePixels.width
            let referencePixel = referencePixels.pixel(x: x, y: y)
            let capturedPixel = capturedPixels.pixel(x: x, y: y)
            let referenceOwner = referenceTrace.ownerLabels[firstPixelIndex]
            let capturedOwner = capturedTrace.ownerLabels[firstPixelIndex]
            let ownerName: (UInt8, MaterialOutlineOwnershipTrace) -> String = { label, trace in
                label == 255 ? "unowned" : trace.ownerEventIDs[Int(label)]
            }
            let rgbaDescription: (SampledRGBA) -> String = { pixel in
                "[\(pixel.redByte),\(pixel.greenByte),\(pixel.blueByte),\(pixel.alphaByte)]"
            }
            let traceBackground: (MaterialOutlineOwnershipTrace, Int) -> SampledRGBA = {
                trace, pixelIndex in
                let offset = pixelIndex * 4
                return SampledRGBA(
                    redByte: trace.counterfactualBackgroundRGBA[offset],
                    greenByte: trace.counterfactualBackgroundRGBA[offset + 1],
                    blueByte: trace.counterfactualBackgroundRGBA[offset + 2],
                    alphaByte: trace.counterfactualBackgroundRGBA[offset + 3]
                )
            }
            let firstOwnerLabelDiff = referenceTrace.ownerLabels.indices.first {
                referenceTrace.ownerLabels[$0] != capturedTrace.ownerLabels[$0]
            }
            let firstBackgroundByteDiff = referenceTrace.counterfactualBackgroundRGBA.indices.first {
                referenceTrace.counterfactualBackgroundRGBA[$0]
                    != capturedTrace.counterfactualBackgroundRGBA[$0]
            }

            let rawCapture = MaterialRawSceneCapture()
            let raw = try renderer.render(
                recipe: recipe,
                material: material,
                background: .lowContrast,
                configuration: .init(
                    scale: 2,
                    outlineVisibilityPlacement: .none,
                    rawSceneCapture: rawCapture
                )
            )
            let canonicalPixels = try downsampledPixels(
                raw.fullScreen.pngData,
                width: 393,
                height: 852
            )
            let sourceLayers = try rawCapture.actorLayers.map { layer in
                PixelImage(
                    width: layer.image.width,
                    height: layer.image.height,
                    rgba: try rgbaBytes(layer.image)
                )
            }
            let downsampledLayers = try sourceLayers.map { layer in
                try fixture11Resized(
                    layer,
                    width: 393,
                    height: 852
                )
            }
            let selectedOwnerIndex = referenceOwner == 255 ? nil : Int(referenceOwner)
            let selectedAlpha = selectedOwnerIndex.map {
                downsampledLayers[$0].pixel(x: x, y: y).alphaByte
            }
            let laterSupport = selectedOwnerIndex.map { ownerIndex in
                ((ownerIndex + 1)..<downsampledLayers.count).map { actorIndex in
                    let downsampled = downsampledLayers[actorIndex].pixel(x: x, y: y).alphaByte
                    let sourcePixels = sourceLayers[actorIndex]
                    let sourceX = min(sourcePixels.width - 1, x * 2)
                    let sourceY = min(sourcePixels.height - 1, y * 2)
                    let sourceSupport = (sourceY...min(sourcePixels.height - 1, sourceY + 1)).flatMap {
                        sampleY in
                        (sourceX...min(sourcePixels.width - 1, sourceX + 1)).map {
                            sampleX in sourcePixels.pixel(x: sampleX, y: sampleY).alphaByte
                        }
                    }
                    return "\(actorIndex):\(expectedOrder[actorIndex]) down=\(downsampled) source2x=\(sourceSupport)"
                }
            } ?? []
            let ownerDiffDescription = firstOwnerLabelDiff.map { pixelIndex in
                let ownerX = pixelIndex % referencePixels.width
                let ownerY = pixelIndex / referencePixels.width
                return "(\(ownerX),\(ownerY)) ref=\(referenceTrace.ownerLabels[pixelIndex]):\(ownerName(referenceTrace.ownerLabels[pixelIndex], referenceTrace)) cap=\(capturedTrace.ownerLabels[pixelIndex]):\(ownerName(capturedTrace.ownerLabels[pixelIndex], capturedTrace))"
            } ?? "none"
            let backgroundDiffDescription = firstBackgroundByteDiff.map { byteIndex in
                let pixelIndex = byteIndex / 4
                let backgroundX = pixelIndex % referencePixels.width
                let backgroundY = pixelIndex / referencePixels.width
                return "(\(backgroundX),\(backgroundY)) channel=\(byteIndex % 4) ref=\(rgbaDescription(traceBackground(referenceTrace, pixelIndex))) cap=\(rgbaDescription(traceBackground(capturedTrace, pixelIndex)))"
            } ?? "none"
            let diagnostic = [
                "first-final-pixel=(\(x),\(y))",
                "canonical=\(rgbaDescription(canonicalPixels.pixel(x: x, y: y)))",
                "reference=\(rgbaDescription(referencePixel))",
                "captured=\(rgbaDescription(capturedPixel))",
                "reference-owner=\(referenceOwner):\(ownerName(referenceOwner, referenceTrace))",
                "captured-owner=\(capturedOwner):\(ownerName(capturedOwner, capturedTrace))",
                "reference-background=\(rgbaDescription(traceBackground(referenceTrace, firstPixelIndex)))",
                "captured-prefix-background=\(rgbaDescription(traceBackground(capturedTrace, firstPixelIndex)))",
                "selected-owner-alpha=\(selectedAlpha.map(String.init) ?? "none")",
                "later-support=\(laterSupport)",
                "first-owner-label-diff=\(ownerDiffDescription)",
                "first-counterfactual-background-diff=\(backgroundDiffDescription)",
            ].joined(separator: "\n")
            #expect(referencePixel == capturedPixel, Comment(rawValue: diagnostic))
            return
        }

        // The mode switch is now deliberately observationally inert: there is
        // only one same-render structural-authority trace.
        #expect(captured.fullScreen.pngData == reference.fullScreen.pngData)
        #expect(captured.calendarTile.pngData == reference.calendarTile.pngData)
        #expect(capturedAlpha == referenceAlpha)
        #expect(captured.drawSequence == reference.drawSequence)
        #expect(captured.tileCrop == reference.tileCrop)
        #expect(capturedTrace == referenceTrace)
        #expect(reference.drawSequence == expectedOrder)
        #expect(referenceTrace.ownerEventIDs == expectedOrder)
        #expect(referenceTrace.width == 393)
        #expect(referenceTrace.height == 852)
        #expect(referenceTrace.ownerLabels.count == 393 * 852)
        #expect(referenceTrace.counterfactualBackgroundRGBA.count == 393 * 852 * 4)

        var ownedPixelCount = 0
        for pixelIndex in referenceTrace.ownerLabels.indices {
            let owner = referenceTrace.ownerLabels[pixelIndex]
            guard owner != 255 else { continue }
            ownedPixelCount += 1
            #expect(Int(owner) < expectedOrder.count)
            #expect(referenceTrace.counterfactualBackgroundRGBA[pixelIndex * 4 + 3] == 255)
        }
        #expect(ownedPixelCount > 0)

        let referenceFull = try pixels(reference.fullScreen.pngData)
        #expect(try pixels(reference.calendarTile.pngData) == referenceFull.cropped(
            x: reference.tileCrop.x,
            y: reference.tileCrop.y,
            width: reference.tileCrop.width,
            height: reference.tileCrop.height
        ))

        #expect(sha256Hex(referenceTrace.ownerLabels) ==
            sha256Hex(capturedTrace.ownerLabels))
        #expect(sha256Hex(referenceTrace.counterfactualBackgroundRGBA) ==
            sha256Hex(capturedTrace.counterfactualBackgroundRGBA))

        #expect(referenceInstrumentation.canonicalRawSceneRenders == 1)
        #expect(referenceInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(referenceInstrumentation.capturedActorLayerBuilds == 10)
        #expect(referenceInstrumentation.counterfactualCompositePasses == 0)
        #expect(referenceInstrumentation.isolatedPresentationComposites == 0)

        #expect(capturedInstrumentation.canonicalRawSceneRenders == 1)
        #expect(capturedInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(capturedInstrumentation.capturedActorLayerBuilds == 10)
        #expect(capturedInstrumentation.counterfactualCompositePasses == 0)
        #expect(capturedInstrumentation.isolatedPresentationComposites == 0)
    }

    @Test("fixture 11 presentation evidence packages deterministic same-render authority")
    func fixture11PresentationEvidencePayloadMatchesLegacyActorRenders() throws {
        // Evidence must package the exact sampled authority and underlay traces
        // from one canonical render. It may not compare against separately
        // rendered isolated or actor-removed scenes.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        #expect(recipe.actors.count == 10)
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let renderer = MaterialRenderer()
        let expectedOrder = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }.map(\.eventID)

        let defaultOff = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                presentationEvidenceRequest: .none
            )
        )
        let requestedInstrumentation = MaterialRenderInstrumentation()
        let requestOn = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                outlineCounterfactualMode: .capturedActorReplay,
                instrumentation: requestedInstrumentation,
                presentationEvidenceRequest: .perActor
            )
        )

        #expect(requestOn.fullScreen.pngData == defaultOff.fullScreen.pngData)
        #expect(requestOn.calendarTile.pngData == defaultOff.calendarTile.pngData)
        #expect(try alphaBytes(requestOn.fullScreen.pngData) == alphaBytes(defaultOff.fullScreen.pngData))
        #expect(try alphaBytes(requestOn.calendarTile.pngData) == alphaBytes(defaultOff.calendarTile.pngData))
        #expect(requestOn.tileCrop == defaultOff.tileCrop)
        #expect(requestOn.drawSequence == defaultOff.drawSequence)
        #expect(requestOn.drawSequence == expectedOrder)

        let payload = try #require(requestOn.presentationEvidence)
        let trace = try #require(requestedInstrumentation.ownershipTrace)
        #expect(payload.actors.map(\.eventID) == expectedOrder)
        #expect(trace.ownerEventIDs == expectedOrder)
        #expect(payload.actors.count == 10)
        var derivedOwnerLabels = Data(repeating: 255, count: trace.width * trace.height)
        var payloadDigests = [String: String]()
        for (actorIndex, actorPayload) in payload.actors.enumerated() {
            #expect(actorPayload.isolated.drawSequence == expectedOrder)
            #expect(actorPayload.removed.drawSequence == Array(expectedOrder.prefix(actorIndex)))
            #expect(actorPayload.isolated.ownership.ownerEventIDs == expectedOrder)
            #expect(actorPayload.isolated.ownership.ownerLabels == trace.ownerLabels)
            let fullAlpha = try alphaBytes(actorPayload.isolated.fullScreen.pngData)
            let tileAlpha = try alphaBytes(actorPayload.isolated.calendarTile.pngData)
            #expect(fullAlpha.contains(0))
            #expect(fullAlpha.contains { $0 > 0 })
            #expect(tileAlpha == fixture11CroppedBytes(
                fullAlpha,
                sourceWidth: trace.width,
                crop: actorPayload.isolated.tileCrop,
                bytesPerPixel: 1
            ))
            #expect(try alphaBytes(actorPayload.projected.fullScreen.pngData) == fullAlpha)
            #expect(
                try pixels(actorPayload.projected.calendarTile.pngData)
                    == pixels(actorPayload.projected.fullScreen.pngData).cropped(
                        x: actorPayload.projected.tileCrop.x,
                        y: actorPayload.projected.tileCrop.y,
                        width: actorPayload.projected.tileCrop.width,
                        height: actorPayload.projected.tileCrop.height
                    )
            )
            #expect(!actorPayload.palettePoles.isEmpty)
            for pole in actorPayload.palettePoles {
                #expect(try alphaBytes(pole.fullScreen.pngData) == fullAlpha)
                #expect(
                    try pixels(pole.calendarTile.pngData)
                        == pixels(pole.fullScreen.pngData).cropped(
                            x: pole.tileCrop.x,
                            y: pole.tileCrop.y,
                            width: pole.tileCrop.width,
                            height: pole.tileCrop.height
                        )
                )
            }
            for pixelIndex in fullAlpha.indices where fullAlpha[pixelIndex] > 0 {
                derivedOwnerLabels[pixelIndex] = UInt8(actorIndex)
            }
            payloadDigests[actorPayload.eventID] = try fixture11PresentationEvidenceDigest(
                eventID: actorPayload.eventID,
                isolated: actorPayload.isolated,
                removed: actorPayload.removed,
                projected: actorPayload.projected,
                palettePoles: actorPayload.palettePoles
            )
        }
        #expect(derivedOwnerLabels == trace.ownerLabels)

        // A missing authority owner is a real negative control: it changes the
        // renderer-owned trace digest even when all presentation pixels remain.
        let firstOwnedPixel = try #require(trace.ownerLabels.firstIndex { $0 != 255 })
        var ownershipMutation = trace.ownerLabels
        ownershipMutation[firstOwnedPixel] = 255
        #expect(sha256Hex(ownershipMutation) != sha256Hex(trace.ownerLabels))

        let repeatedInstrumentation = MaterialRenderInstrumentation()
        let repeated = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                instrumentation: repeatedInstrumentation,
                presentationEvidenceRequest: .perActor
            )
        )
        let repeatedPayload = try #require(repeated.presentationEvidence)
        let repeatedDigests = try Dictionary(uniqueKeysWithValues: repeatedPayload.actors.map {
            actorPayload in
            (
                actorPayload.eventID,
                try fixture11PresentationEvidenceDigest(
                    eventID: actorPayload.eventID,
                    isolated: actorPayload.isolated,
                    removed: actorPayload.removed,
                    projected: actorPayload.projected,
                    palettePoles: actorPayload.palettePoles
                )
            )
        })
        #expect(repeated.fullScreen.pngData == requestOn.fullScreen.pngData)
        #expect(repeated.calendarTile.pngData == requestOn.calendarTile.pngData)
        #expect(repeatedDigests == payloadDigests)

        #expect(requestedInstrumentation.canonicalRawSceneRenders == 1)
        #expect(requestedInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(requestedInstrumentation.capturedActorLayerBuilds == 10)
        #expect(requestedInstrumentation.counterfactualCompositePasses == 0)
        #expect(requestedInstrumentation.isolatedPresentationComposites == 0)
        #expect(repeatedInstrumentation.canonicalRawSceneRenders == 1)
        #expect(repeatedInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(repeatedInstrumentation.capturedActorLayerBuilds == 10)
        #expect(repeatedInstrumentation.counterfactualCompositePasses == 0)
        #expect(repeatedInstrumentation.isolatedPresentationComposites == 0)
    }

    @Test("fixture 11 payload readability deterministically consumes exact authority")
    func fixture11PayloadReadabilityMatchesLegacyMetricsWithoutRerenders() throws {
        // Readability must consume exact structural authority and owner labels
        // already packaged by the renderer. It may not compare against a
        // separately sampled isolated or actor-removed scene.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 3
        )
        let renderer = MaterialRenderer()
        let instrumentation = MaterialRenderInstrumentation()
        let source = try renderer.render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                outlineCounterfactualMode: .capturedActorReplay,
                instrumentation: instrumentation,
                presentationEvidenceRequest: .perActor
            )
        )
        #expect(source.presentationEvidence != nil)
        #expect(instrumentation.canonicalRawSceneRenders == 1)
        #expect(instrumentation.actorRemovedFullSceneRenders == 0)
        #expect(instrumentation.capturedActorLayerBuilds == 10)
        #expect(instrumentation.counterfactualCompositePasses == 0)
        #expect(instrumentation.isolatedPresentationComposites == 0)
        #expect(!MaterialEvidencePackage.outlineStructuralSupport(alpha: 19.0 / 255.0))
        #expect(MaterialEvidencePackage.outlineStructuralSupport(alpha: 20.0 / 255.0))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let countersBeforePayload = [
            instrumentation.canonicalRawSceneRenders,
            instrumentation.actorRemovedFullSceneRenders,
            instrumentation.capturedActorLayerBuilds,
            instrumentation.counterfactualCompositePasses,
            instrumentation.isolatedPresentationComposites,
        ]
        let firstPayload = try MaterialEvidencePackage.presentationSceneScaleReadabilityForTesting(
            source: source,
            recipe: recipe,
            material: material,
            background: .lowContrast
        )
        let secondPayload = try MaterialEvidencePackage.presentationSceneScaleReadabilityForTesting(
            source: source,
            recipe: recipe,
            material: material,
            background: .lowContrast
        )
        let countersAfterPayload = [
            instrumentation.canonicalRawSceneRenders,
            instrumentation.actorRemovedFullSceneRenders,
            instrumentation.capturedActorLayerBuilds,
            instrumentation.counterfactualCompositePasses,
            instrumentation.isolatedPresentationComposites,
        ]
        #expect(countersAfterPayload == countersBeforePayload)
        let first = try #require(firstPayload)
        let second = try #require(secondPayload)
        #expect(first.count == 10)
        #expect(first.map(\.eventID) == recipe.actors.map(\.eventID))
        #expect(try encoder.encode(first) == encoder.encode(second))
        #expect(first == second)
        let failures = first.filter { $0.eligible && !$0.passes }
        #expect(failures.isEmpty, Comment(rawValue: "authority readability failures=\(failures)"))
    }

    @Test("below-cutoff authority tails do not rescue a missing outline arc")
    func belowCutoffAuthorityTailsDoNotRescueMissingOutlineArc() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let fixture = try #require(MaterialEvidencePackage.coverage(for: manifest).fixtures.first {
            $0.index == 23
        })
        let layout = manifest.breadth[fixture.layoutFixtureIndex]
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == fixture.layoutFixtureIndex
        }?.recipe)
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: fixture.requestedColorCount
        )
        let source = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .light,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                presentationEvidenceRequest: .perActor
            )
        )
        let payload = try #require(source.presentationEvidence)
        let actor = try #require(recipe.actors.first { actor in
            let radius = actor.diameter * 393 * 0.56
            let centerX = actor.position.x * 393
            let centerY = actor.position.y * 852
            return actor.diameter >= 0.15
                && centerX - radius >= 0
                && centerX + radius < 393
                && centerY - radius >= 0
                && centerY + radius < 852
        })
        let baseline = try #require(
            MaterialEvidencePackage.presentationSceneScaleReadabilityForTesting(
                source: source,
                recipe: recipe,
                material: material,
                background: .light
            )?.first { $0.eventID == actor.eventID }
        )
        #expect(baseline.visibleAreaFraction >= 0.82)

        let actorEvidence = try #require(payload.actors.first { $0.eventID == actor.eventID })
        let brokenAuthority = try outlineBelowCutoffMissingArcMutation(
            actorEvidence.isolated,
            actor: actor
        )
        let brokenProjected = try outlineBelowCutoffMissingArcMutation(
            actorEvidence.projected,
            actor: actor
        )
        let brokenPoles = try actorEvidence.palettePoles.map {
            try outlineBelowCutoffMissingArcMutation($0, actor: actor)
        }
        let mutatedActorEvidence = MaterialActorPresentationEvidence(
            eventID: actorEvidence.eventID,
            isolated: brokenAuthority,
            removed: actorEvidence.removed,
            projected: brokenProjected,
            palettePoles: brokenPoles
        )
        let mutatedPayload = MaterialPresentationEvidence(actors: payload.actors.map {
            $0.eventID == actor.eventID ? mutatedActorEvidence : $0
        })
        let mutatedByID = Dictionary(uniqueKeysWithValues: mutatedPayload.actors.map {
            ($0.eventID, $0)
        })
        let projectionBase = try pixels(
            #require(mutatedByID[source.drawSequence[0]]).removed.fullScreen.pngData
        )
        let mutatedFullPixels = try source.drawSequence.reduce(projectionBase) { prefix, eventID in
            let layer = try pixels(#require(mutatedByID[eventID]).projected.fullScreen.pngData)
            return outlineSourceOver(source: layer, underlay: prefix)
        }
        let mutatedFull = try outlineRenderedImage(mutatedFullPixels)
        let mutatedTile = try outlineCroppedRenderedImage(mutatedFull, crop: source.tileCrop)
        let mutatedSource = MaterialRenderedScene(
            fullScreen: mutatedFull,
            calendarTile: mutatedTile,
            tileCrop: source.tileCrop,
            drawSequence: source.drawSequence,
            presentationEvidence: mutatedPayload
        )
        let mutated = try #require(
            MaterialEvidencePackage.presentationSceneScaleReadabilityForTesting(
                source: mutatedSource,
                recipe: recipe,
                material: material,
                background: .light
            )?.first { $0.eventID == actor.eventID }
        )

        #expect(mutated.visibleAreaFraction < 0.82, Comment(rawValue:
            "below-cutoff missing arc retained identity coverage: baseline="
                + "\(baseline.visibleAreaFraction) mutated=\(mutated.visibleAreaFraction)"
        ))
    }

    @Test("outline evidence owns the exact presented structural-authority trace")
    func outlineEvidenceOwnsExactPresentedStructuralAuthorityTrace() throws {
        // Production regression caught: rebuilding isolated or actor-removed
        // scenes creates a different sampling path from the canonical
        // supersampled presentation. Evidence must expose the transparent
        // authority planes captured by that one render, after its whole-scene
        // downsample and exact tile crop, and ownership must derive from those
        // same planes.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let frozenRecipe = try #require(
            archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe
        )
        let representativePrefixes = ["2C9F"]
        let representativeActors = frozenRecipe.actors.filter { actor in
            representativePrefixes.contains { actor.eventID.hasPrefix($0) }
        }
        #expect(representativeActors.count == representativePrefixes.count)
        let recipe = CompositionRecipe(
            daySeed: frozenRecipe.daySeed,
            grammar: frozenRecipe.grammar,
            viewport: frozenRecipe.viewport,
            actors: representativeActors
        )
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: representativeActors.map(\.eventID),
            family: .outline,
            requestedColorCount: 3
        )
        let instrumentation = MaterialRenderInstrumentation()
        let rendered = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                outlineCounterfactualMode: .capturedActorReplay,
                instrumentation: instrumentation,
                presentationEvidenceRequest: .perActor
            )
        )
        let evidence = try #require(rendered.presentationEvidence)
        let presentedTrace = try #require(instrumentation.ownershipTrace)

        #expect(evidence.actors.map(\.eventID) == presentedTrace.ownerEventIDs)
        #expect(evidence.actors.count == recipe.actors.count)
        #expect(instrumentation.preProjectionAuthorityAlphaPlanes.count == evidence.actors.count)
        var derivedOwnerLabels = Data(
            repeating: 255,
            count: presentedTrace.width * presentedTrace.height
        )
        for (ownerIndex, actorEvidence) in evidence.actors.enumerated() {
            let fullAlpha = try alphaBytes(actorEvidence.isolated.fullScreen.pngData)
            let tileAlpha = try alphaBytes(actorEvidence.isolated.calendarTile.pngData)
            let preProjectionAlpha = instrumentation.preProjectionAuthorityAlphaPlanes[ownerIndex]
            #expect(fullAlpha == preProjectionAlpha)
            #expect(sha256Hex(fullAlpha) == sha256Hex(preProjectionAlpha))
            #expect(fullAlpha.contains(0))
            #expect(fullAlpha.contains { $0 > 0 })
            #expect(
                try pixels(actorEvidence.isolated.calendarTile.pngData)
                    == pixels(actorEvidence.isolated.fullScreen.pngData).cropped(
                        x: actorEvidence.isolated.tileCrop.x,
                        y: actorEvidence.isolated.tileCrop.y,
                        width: actorEvidence.isolated.tileCrop.width,
                        height: actorEvidence.isolated.tileCrop.height
                    )
            )
            #expect(tileAlpha.count == actorEvidence.isolated.tileCrop.width
                * actorEvidence.isolated.tileCrop.height)
            #expect(tileAlpha == fixture11CroppedBytes(
                preProjectionAlpha,
                sourceWidth: presentedTrace.width,
                crop: actorEvidence.isolated.tileCrop,
                bytesPerPixel: 1
            ))
            for pixelIndex in fullAlpha.indices where fullAlpha[pixelIndex] > 0 {
                derivedOwnerLabels[pixelIndex] = UInt8(ownerIndex)
            }
        }
        #expect(sha256Hex(presentedTrace.ownerLabels) == sha256Hex(derivedOwnerLabels))

        #expect(instrumentation.canonicalRawSceneRenders == 1)
        #expect(instrumentation.actorRemovedFullSceneRenders == 0)
        #expect(instrumentation.capturedActorLayerBuilds == recipe.actors.count)
        #expect(instrumentation.counterfactualCompositePasses == 0)
        #expect(instrumentation.isolatedPresentationComposites == 0)
    }

    @Test("overlapping outline accents compose nonexclusively in canonical draw order")
    func overlappingOutlineAccentsComposeEveryProjectedCapturedLayer() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let frozen = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let sourceActors = Array(frozen.actors.prefix(2))
        try #require(sourceActors.count == 2)
        let actors = sourceActors.enumerated().map { index, actor in
            ActorCompositionRecipe(
                eventID: actor.eventID,
                position: .init(x: 0.5, y: 0.5),
                diameter: 0.42,
                depth: index == 0 ? 0.35 : 0.72,
                localBlur: index == 0 ? 0.012 : 0.036,
                cropAllowance: actor.cropAllowance,
                drawOrder: index
            )
        }
        let recipe = CompositionRecipe(
            daySeed: frozen.daySeed,
            grammar: frozen.grammar,
            viewport: frozen.viewport,
            actors: actors
        )
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: actors.map(\.eventID),
            family: .outline,
            requestedColorCount: 3
        )
        let instrumentation = MaterialRenderInstrumentation()
        let rendered = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                instrumentation: instrumentation,
                presentationEvidenceRequest: .perActor
            )
        )
        let evidence = try #require(rendered.presentationEvidence)
        try #require(instrumentation.projectedActorLayers.count == 2)
        let projected = try instrumentation.projectedActorLayers.map { image in
            PixelImage(width: image.width, height: image.height, rgba: try rgbaBytes(image))
        }
        let base = try pixels(evidence.actors[0].removed.fullScreen.pngData)
        let afterLower = outlineSourceOver(source: projected[0], underlay: base)
        let expected = outlineSourceOver(source: projected[1], underlay: afterLower)
        let withoutLower = outlineSourceOver(source: projected[1], underlay: base)
        let actual = try pixels(rendered.fullScreen.pngData)

        #expect(actual.rgba == expected.rgba)
        #expect(rendered.drawSequence == actors.map(\.eventID))
        for actorIndex in projected.indices {
            #expect(
                projected[actorIndex].rgba.enumerated().compactMap { offset, byte in
                    offset % 4 == 3 ? byte : nil
                } == Array(try alphaBytes(
                    evidence.actors[actorIndex].isolated.fullScreen.pngData
                ))
            )
            for pixelIndex in 0..<(projected[actorIndex].width * projected[actorIndex].height)
                where projected[actorIndex].rgba[pixelIndex * 4 + 3] == 0 {
                #expect(projected[actorIndex].rgba[pixelIndex * 4] == 0)
                #expect(projected[actorIndex].rgba[pixelIndex * 4 + 1] == 0)
                #expect(projected[actorIndex].rgba[pixelIndex * 4 + 2] == 0)
            }
        }

        var overlapPixel: Int?
        for pixelIndex in 0..<(actual.width * actual.height) {
            let offset = pixelIndex * 4
            let lowerAlpha = projected[0].rgba[offset + 3]
            let upperAlpha = projected[1].rgba[offset + 3]
            guard lowerAlpha > 0, upperAlpha > 0, upperAlpha < 255 else { continue }
            let alpha = Double(lowerAlpha) / 255
            if (0..<3).contains(where: { channel in
                abs(
                    Double(projected[0].rgba[offset + channel]) / 255
                        - Double(base.rgba[offset + channel]) / 255 * alpha
                ) > 0.03
            }) {
                overlapPixel = pixelIndex
                break
            }
        }
        let overlapOffset = try #require(overlapPixel) * 4
        let laterTransmission = 1 - Double(projected[1].rgba[overlapOffset + 3]) / 255
        for channel in 0..<3 {
            let lowerAlpha = Double(projected[0].rgba[overlapOffset + 3]) / 255
            let rawLowerDelta = Double(projected[0].rgba[overlapOffset + channel]) / 255
                - Double(base.rgba[overlapOffset + channel]) / 255 * lowerAlpha
            let effectiveLowerDelta = Double(expected.rgba[overlapOffset + channel]) / 255
                - Double(withoutLower.rgba[overlapOffset + channel]) / 255
            #expect(
                abs(effectiveLowerDelta - rawLowerDelta * laterTransmission)
                    <= Double(2) / 255
            )
        }

        let scale3Instrumentation = MaterialRenderInstrumentation()
        _ = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .lowContrast,
            configuration: .init(
                scale: 3,
                outlineVisibilityPlacement: .none,
                instrumentation: scale3Instrumentation,
                presentationEvidenceRequest: .perActor
            )
        )
        #expect(
            instrumentation.outlineVisibilitySelectedPaletteIndices
                == scale3Instrumentation.outlineVisibilitySelectedPaletteIndices
        )
    }

    @Test("fixture 11 outline visibility is owned by the renderer after whole-scene downsampling")
    func fixture11OutlineVisibilityIsPostDownsampleAndRendererOwned() throws {
        // Regression caught: applying the correct RGB transfer only to the
        // supersampled actor still lets 1x filtering erase outline identity.
        // Evidence may consume final renderer pixels, but may not repair them.
        let authority = try canonicalCompositionAuthority()
        #expect(sha256Hex(authority.approval) ==
            "c4f4c95c2431701587a3c366dcc4d82ae21b9a5735d840a995a0aae52346124c")
        #expect(sha256Hex(authority.recipes) ==
            "7faef26a612768b67b73b520c7889e569594516bde3745f8a75b4ff2a24aeccd")
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first { $0.fixtureIndex == 11 }?.recipe)
        let renderer = MaterialRenderer()
        let cases: [(colorCount: Int, eventPrefix: String)] = [
            (1, "4E6B"), (2, "4E6B"), (3, "4E6B"),
            (1, "71E4"), (2, "71E4"), (3, "71E4"),
            (3, "9346"),
        ]
        let expectedPreFailures = Set(cases.map {
            "c\($0.colorCount)/lowContrast/\($0.eventPrefix)"
        })
        var preOnlyFailures = Set<String>()
        var packagedFailures = Set<String>()

        for colorCount in Set(cases.map(\.colorCount)).sorted() {
            let dna = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .outline,
                requestedColorCount: colorCount
            )
            let composed = try renderer.render(
                recipe: recipe,
                material: dna,
                background: .lowContrast,
                configuration: .init(scale: 2)
            )
            let expectedOrder = recipe.actors.sorted {
                if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
                if $0.depth != $1.depth { return $0.depth < $1.depth }
                if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
                return $0.eventID < $1.eventID
            }.map(\.eventID)
            #expect(composed.drawSequence == expectedOrder)
        }

        for item in cases {
            let actor = try #require(recipe.actors.first { $0.eventID.hasPrefix(item.eventPrefix) })
            let dna = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .outline,
                requestedColorCount: item.colorCount
            )
            let material = try #require(dna.actor(actor.eventID))
            let isolatedRecipe = CompositionRecipe(
                daySeed: recipe.daySeed,
                grammar: recipe.grammar,
                viewport: recipe.viewport,
                actors: [actor]
            )
            let removedRecipe = CompositionRecipe(
                daySeed: recipe.daySeed,
                grammar: recipe.grammar,
                viewport: recipe.viewport,
                actors: []
            )
            let source = try renderer.render(
                recipe: isolatedRecipe,
                material: dna,
                background: .lowContrast,
                configuration: .init(scale: 2)
            )
            let removedSource = try renderer.render(
                recipe: removedRecipe,
                material: dna,
                background: .lowContrast,
                configuration: .init(scale: 2)
            )
            let preSource = try renderer.render(
                recipe: isolatedRecipe,
                material: dna,
                background: .lowContrast,
                configuration: .init(
                    scale: 2,
                    outlineVisibilityPlacement: .actorLayerPreComposite
                )
            )
            let presented = try renderer.render(
                recipe: isolatedRecipe,
                material: dna,
                background: .lowContrast,
                configuration: .init(
                    scale: 1,
                    supersampling: 2,
                    presentationEvidenceRequest: .perActor
                )
            )
            #expect(source.drawSequence == [actor.eventID])
            #expect(removedSource.drawSequence.isEmpty)
            #expect(preSource.drawSequence == source.drawSequence)
            #expect(preSource.tileCrop == source.tileCrop)

            let alpha2x = try #require(combinedAlphaImage(
                try renderer.renderStructuralAlphaLayers(
                    material,
                    pixelSize: actorPixelDiameter(actor) * 2,
                    blurRadius: actor.localBlur * 786
                ).map { try pixels($0.pngData) }
            ))
            let alpha1x = try fixture11Resized(
                alpha2x,
                width: max(1, alpha2x.width / 2),
                height: max(1, alpha2x.height / 2)
            )
            // The internal renderer seam invokes the transfer exactly once on
            // the real fractional-alpha actor layer. The post witness invokes
            // that same transfer exactly once after raw whole-scene downsample.
            let preOnly1x = try downsampledPixels(
                preSource.fullScreen.pngData,
                width: 393,
                height: 852
            )
            let current1x = try downsampledPixels(
                source.fullScreen.pngData,
                width: 393,
                height: 852
            )
            let removed1x = try downsampledPixels(
                removedSource.fullScreen.pngData,
                width: 393,
                height: 852
            )
            let localPostWitness1x = fixture11OwnedVisibilityWitness(
                canonical: current1x,
                owners: [.init(actor: actor, alpha: alpha1x, removed: removed1x)]
            )
            let presented1x = try pixels(presented.fullScreen.pngData)
            let localPostIdentity = fixture11IsolatedIdentityMetrics(
                alpha: alpha1x,
                image: localPostWitness1x,
                centerX: actor.position.x * 393,
                centerY: actor.position.y * 852,
                pixelRadius: actor.diameter * 393 * 0.48,
                background: .lowContrast
            )
            #expect(localPostIdentity.passes)
            #expect(presented.drawSequence == source.drawSequence)
            #expect(presented.tileCrop == PixelRect(x: 0, y: 229, width: 393, height: 393))

            #expect(fixture11AlphaBytes(current1x) == fixture11AlphaBytes(presented1x))
            #expect(fixture11AlphaHistogram(fixture11AlphaBytes(current1x)) ==
                fixture11AlphaHistogram(fixture11AlphaBytes(presented1x)))
            // Native and supersampled presentations intentionally use their
            // own exact sampling paths. Their structural alpha support is
            // authoritative within each path; RGB difference bounds need not
            // be byte-identical across filters.

            let key = "c\(item.colorCount)/lowContrast/\(item.eventPrefix)"
            let packagedReadability = try MaterialEvidencePackage
                .presentationSceneScaleReadabilityForTesting(
                    source: presented,
                    recipe: isolatedRecipe,
                    material: dna,
                    background: .lowContrast
                )
            let packaged = try #require(packagedReadability?.first)
            if !packaged.passes { packagedFailures.insert(key) }
            let views = fixture11PresentationViews(
                current: current1x,
                preOnly: preOnly1x,
                postWitness: presented1x,
                alpha: alpha1x,
                actor: actor
            )
            for view in views {
                let preOnly = fixture11IsolatedIdentityMetrics(
                    alpha: view.alpha,
                    image: view.preOnly,
                    centerX: view.centerX,
                    centerY: view.centerY,
                    pixelRadius: view.pixelRadius,
                    background: .lowContrast
                )
                if !preOnly.passes { preOnlyFailures.insert(key) }
            }

            let tile = presented1x.cropped(x: 0, y: 229, width: 393, height: 393)
            #expect(tile == views.first { $0.view == .tile }?.postWitness)
            #expect(try pixels(presented.calendarTile.pngData) == tile)
            let exact = try #require(views.first { $0.view == .exact })
            #expect(exact.postWitness == presented1x.cropped(
                x: exact.originX,
                y: exact.originY,
                width: exact.postWitness.width,
                height: exact.postWitness.height
            ))
        }

        // A lower actor must never claim a pixel already owned by a top actor,
        // even when the top actor's exact canonical-minus-removed delta is zero.
        let opaque = fixture11SolidPixel(red: 120, green: 126, blue: 118, alpha: 255)
        let lowerRemoved = fixture11SolidPixel(red: 10, green: 20, blue: 30, alpha: 255)
        let topAlpha = fixture11SolidPixel(red: 1, green: 1, blue: 1, alpha: 1)
        let lowerAlpha = fixture11SolidPixel(red: 255, green: 255, blue: 255, alpha: 255)
        let noFallthrough = fixture11OwnedVisibilityWitness(
            canonical: opaque,
            owners: [
                .init(actor: recipe.actors[0], alpha: lowerAlpha, removed: lowerRemoved),
                .init(actor: recipe.actors[1], alpha: topAlpha, removed: opaque),
            ]
        )
        #expect(noFallthrough == opaque)

        #expect(preOnlyFailures == expectedPreFailures, Comment(rawValue:
            "pre-downsample-only mutation failures=\(preOnlyFailures.sorted())"
        ))
        #expect(packagedFailures.isEmpty, Comment(rawValue:
            "renderer-owned packaged presentation failures=\(packagedFailures.sorted())"
        ))
        #expect(!packagedFailures.contains("c3/lowContrast/9346"))
        #expect(preOnlyFailures.contains("c3/lowContrast/9346"))
    }

    @Test("sealed 1x material families remain optically identifiable in every presentation")
    func sealedSceneScaleMaterialIdentityMatrix() throws {
        // Production regressions caught here, before the body:
        // - a family branch reusing another family's pixels;
        // - solid gaining a hidden brightness ramp;
        // - radial ownership becoming directional;
        // - mist losing its fine tactile grain;
        // - transparent bodies losing readable saturated silhouettes;
        // - filled families acquiring a hole;
        // - outline becoming a softly filled disc or counterform becoming filled.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layoutIndex = 10
        let eventID = "2C9F4B58-ABF5-4F7E-8CA9-6D415C7B3D03"
        let layout = manifest.breadth[layoutIndex]
        let approved = try #require(archive.fixtures.first {
            $0.fixtureIndex == layoutIndex
        }?.recipe)
        let actor = try #require(approved.actor(eventID))
        let isolated = CompositionRecipe(
            daySeed: approved.daySeed,
            grammar: approved.grammar,
            viewport: approved.viewport,
            actors: [actor]
        )
        let renderer = MaterialRenderer()
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        var observations = [SealedMaterialKey: SealedOpticalSignature]()
        var failures = [String]()

        for colorCount in 1...3 {
            for background in backgrounds {
                for family in MaterialFamily.allCases {
                    let dna = MaterialDNA.fixture(
                        daySeed: layout.seed,
                        eventIDs: layout.eventIDs,
                        family: family,
                        requestedColorCount: colorCount
                    )
                    let material = try #require(dna.actor(eventID))
                    let rendered = try renderer.render(
                        recipe: isolated,
                        material: dna,
                        background: background,
                        configuration: .init(scale: 1)
                    )
                    let full = try pixels(rendered.fullScreen.pngData)
                    let tile = try pixels(rendered.calendarTile.pngData)
                    let sceneCenterX = actor.position.x * 393
                    let sceneCenterY = actor.position.y * 852
                    let sceneRadius = actor.diameter * 393 * 0.48
                    let actorPixelSize = max(1, Int(ceil(actor.diameter * 393)))
                    let actorImage = try pixels(renderer.renderActor(
                        material,
                        pixelSize: actorPixelSize,
                        background: background
                    ).pngData)
                    let cropPadding = sceneRadius * 1.35
                    let cropX = max(0, Int(floor(sceneCenterX - cropPadding)))
                    let cropY = max(0, Int(floor(sceneCenterY - cropPadding)))
                    let cropMaxX = min(full.width, Int(ceil(sceneCenterX + cropPadding)))
                    let cropMaxY = min(full.height, Int(ceil(sceneCenterY + cropPadding)))
                    let exact = full.cropped(
                        x: cropX,
                        y: cropY,
                        width: cropMaxX - cropX,
                        height: cropMaxY - cropY
                    )
                    let viewImages: [(SealedMaterialView, PixelImage, Double, Double, Double)] = [
                        (.full, full, sceneCenterX, sceneCenterY, sceneRadius),
                        (.tile, tile, sceneCenterX, sceneCenterY - Double(rendered.tileCrop.y), sceneRadius),
                        (
                            .actor,
                            actorImage,
                            Double(actorImage.width) * 0.5,
                            Double(actorImage.height) * 0.5,
                            Double(actorPixelSize) * 0.48
                        ),
                        (
                            .exact,
                            exact,
                            sceneCenterX - Double(cropX),
                            sceneCenterY - Double(cropY),
                            sceneRadius
                        ),
                    ]
                    for (view, image, centerX, centerY, radius) in viewImages {
                        let key = SealedMaterialKey(
                            colorCount: colorCount,
                            background: background,
                            family: family,
                            view: view
                        )
                        let signature = sealedSignature(
                            image,
                            centerX: centerX,
                            centerY: centerY,
                            radius: radius,
                            background: background
                        )
                        observations[key] = signature
                        let metrics = sealedMetrics(signature)
                        let label = "c\(colorCount)/\(background.rawValue)/\(family.rawValue)/\(view.rawValue)"

                        if family == .solid, metrics.coreRange > 0.018 {
                            failures.append("solid-flat \(label) range=\(metrics.coreRange)")
                        }
                        if [.gradient, .solid, .sphere, .glass, .mist, .halo, .luminous].contains(family),
                           metrics.centerToRimRatio < 0.42 {
                            failures.append("filled-center \(label) ratio=\(metrics.centerToRimRatio)")
                        }
                        if family == .outline,
                           metrics.centerToRimRatio > 0.22 || metrics.activeAreaFraction > 0.34 {
                            failures.append(
                                "outline-opening \(label) ratio=\(metrics.centerToRimRatio) area=\(metrics.activeAreaFraction)"
                            )
                        }
                        if family == .counterform,
                           metrics.centerToRimRatio > 0.24 || metrics.activeAreaFraction < 0.22 {
                            failures.append(
                                "counterform-opening \(label) ratio=\(metrics.centerToRimRatio) area=\(metrics.activeAreaFraction)"
                            )
                        }
                        if [.glass, .mist, .halo, .luminous, .outline, .counterform].contains(family),
                           !sealedTransparentBodyIsReadable(metrics, family: family) {
                            failures.append(
                                "transparent-silhouette \(label) peak=\(metrics.peakContrast) area=\(metrics.activeAreaFraction) chroma=\(metrics.meanChroma)"
                            )
                        }
                        if family == .outline {
                            let continuity = sealedOutlineContinuity(signature)
                            if continuity.supportedAngularCoverage < 0.82 {
                                failures.append(
                                    "outline-continuity \(label) coverage=\(continuity.supportedAngularCoverage) minSupport=\(continuity.minimumNormalizedSupport)"
                                )
                            }
                        }
                    }
                }
            }
        }

        for colorCount in 1...3 {
            for background in backgrounds {
                for view in SealedMaterialView.allCases {
                    for (index, lhs) in MaterialFamily.allCases.enumerated() {
                        for rhs in MaterialFamily.allCases.dropFirst(index + 1) {
                            let lhsKey = SealedMaterialKey(
                                colorCount: colorCount,
                                background: background,
                                family: lhs,
                                view: view
                            )
                            let rhsKey = SealedMaterialKey(
                                colorCount: colorCount,
                                background: background,
                                family: rhs,
                                view: view
                            )
                            let lhsSignature = try #require(observations[lhsKey])
                            let rhsSignature = try #require(observations[rhsKey])
                            let separation = sealedDistance(lhsSignature, rhsSignature)
                            if separation < 0.020 {
                                failures.append(
                                    "family-collapse c\(colorCount)/\(background.rawValue)/\(view.rawValue)/\(lhs.rawValue)~\(rhs.rawValue) distance=\(separation)"
                                )
                            }
                        }
                    }
                }
            }
        }

        // Mutation controls prove these pixel predicates reject the named
        // regressions rather than merely accepting the current renderer.
        let controlKey = SealedMaterialKey(
            colorCount: 3,
            background: .lowContrast,
            family: .solid,
            view: .actor
        )
        let solidControl = try #require(observations[controlKey])
        #expect(sealedMetrics(solidControl).coreRange <= 0.018)
        #expect(sealedMetrics(sealedRadialRampMutation(solidControl)).coreRange > 0.018)
        #expect(sealedDistance(solidControl, solidControl) < 0.020)

        let transparentKey = SealedMaterialKey(
            colorCount: 3,
            background: .lowContrast,
            family: .glass,
            view: .actor
        )
        let transparentControl = try #require(observations[transparentKey])
        #expect(!sealedTransparentBodyIsReadable(
            sealedMetrics(sealedDesaturatedSilhouetteMutation(transparentControl)),
            family: .glass
        ))

        let outlineKey = SealedMaterialKey(
            colorCount: 3,
            background: .lowContrast,
            family: .outline,
            view: .actor
        )
        let outlineControl = try #require(observations[outlineKey])
        #expect(sealedOutlineContinuity(outlineControl).supportedAngularCoverage >= 0.82)
        #expect(
            sealedOutlineContinuity(sealedBrokenContourMutation(outlineControl))
                .supportedAngularCoverage < 0.82
        )

        let radialActor = fixtureActor(
            colors: [
                .init(red: 0.94, green: 0.18, blue: 0.24),
                .init(red: 0.08, green: 0.54, blue: 0.96),
            ],
            fields: [
                .init(
                    focus: .init(x: 0.5, y: 0.5),
                    radius: 0.58,
                    softness: 0.72,
                    opacity: 1,
                    colorIndex: 1,
                    blend: .normal
                ),
            ]
        )
        let radialPixels = try pixels(renderer.renderActor(
            radialActor,
            pixelSize: actorPixelDiameter(actor),
            background: .dark
        ).pngData)
        let radialControl = sealedSignature(
            radialPixels,
            centerX: Double(radialPixels.width) * 0.5,
            centerY: Double(radialPixels.height) * 0.5,
            radius: Double(radialPixels.width) * 0.48,
            background: .dark
        )
        #expect(sealedAngularResidual(radialControl) < 0.012)
        #expect(sealedAngularResidual(sealedDirectionalMutation(radialControl)) > 0.035)

        let countsByDimension = Dictionary(grouping: failures) { failure in
            failure.split(separator: " ").first.map(String.init) ?? "unknown"
        }.mapValues(\.count)
        #expect(
            failures.isEmpty,
            Comment(rawValue:
                "sealed 1x matrix failures=\(failures.count) dimensions=\(countsByDimension)\n"
                    + failures.prefix(160).joined(separator: "\n")
            )
        )
    }

    @Test("mist fixtures 12 through 14 keep fine actor-local grain at native 1x")
    func mistFixtures12Through14RejectCoarseCheckerGrainAtNativeScale() throws {
        // Production regressions caught here, before the body:
        // - post-blur lattice noise expanding into visible square/checker cells;
        // - antialiasing or downsampling erasing tactile high-frequency grain;
        // - grain leaking into the background or changing between identical renders;
        // - c2/c3 mist losing shifted radial color ownership;
        // - local blur no longer separating soft and sharp depth planes.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let renderer = MaterialRenderer()
        let fixtures = [
            (number: 12, colorCount: 1, layoutIndex: 0),
            (number: 13, colorCount: 2, layoutIndex: 1),
            (number: 14, colorCount: 3, layoutIndex: 2),
        ]
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        var failures = [String]()
        var observationCount = 0

        let fineControl = mistFineStableControl(side: 48)
        let fineMetrics = mistTextureMetrics(luminance: fineControl, side: 48)
        #expect(mistFineGrainPasses(fineMetrics), Comment(rawValue: "fine control \(fineMetrics)"))
        #expect(!mistFineGrainPasses(mistTextureMetrics(
            luminance: mistBrokenGrainMutation(fineControl),
            side: 48
        )))
        #expect(!mistFineGrainPasses(mistTextureMetrics(
            luminance: mistCoarseCellMutation(fineControl, side: 48, cellSide: 6),
            side: 48
        )))
        #expect(!mistFineGrainPasses(mistTextureMetrics(
            luminance: mistCheckerMutation(fineControl, side: 48, cellSide: 4),
            side: 48
        )))

        for fixture in fixtures {
            let layout = manifest.breadth[fixture.layoutIndex]
            let approved = try #require(archive.fixtures.first {
                $0.fixtureIndex == fixture.layoutIndex
            }?.recipe)
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .mist,
                requestedColorCount: fixture.colorCount
            )
            let previousMaterial = fixture.colorCount > 1 ? MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .mist,
                requestedColorCount: fixture.colorCount - 1
            ) : nil

            for background in backgrounds {
                for actor in approved.actors {
                    let isolated = CompositionRecipe(
                        daySeed: approved.daySeed,
                        grammar: approved.grammar,
                        viewport: approved.viewport,
                        actors: [actor]
                    )
                    let rendered = try renderer.render(
                        recipe: isolated,
                        material: material,
                        background: background,
                        configuration: .init(scale: 1, supersampling: 2)
                    )
                    let repeated = try renderer.render(
                        recipe: isolated,
                        material: material,
                        background: background,
                        configuration: .init(scale: 1, supersampling: 2)
                    )
                    #expect(rendered.fullScreen.pngData == repeated.fullScreen.pngData)
                    #expect(rendered.calendarTile.pngData == repeated.calendarTile.pngData)

                    let full = try pixels(rendered.fullScreen.pngData)
                    let tile = try pixels(rendered.calendarTile.pngData)
                    let centerX = actor.position.x * 393
                    let centerY = actor.position.y * 852
                    let diameter = actor.diameter * 393
                    let actorRect = fixture11CenteredCrop(
                        centerX: centerX,
                        centerY: centerY,
                        side: max(16, Int(ceil(diameter * 1.16))),
                        width: full.width,
                        height: full.height
                    )
                    let zoomRect = fixture11CenteredCrop(
                        centerX: centerX,
                        centerY: centerY,
                        side: max(16, Int(ceil(diameter * 0.54))),
                        width: full.width,
                        height: full.height
                    )
                    let actorCrop = full.cropped(
                        x: actorRect.x,
                        y: actorRect.y,
                        width: actorRect.width,
                        height: actorRect.height
                    )
                    let zoomDetail = full.cropped(
                        x: zoomRect.x,
                        y: zoomRect.y,
                        width: zoomRect.width,
                        height: zoomRect.height
                    )
                    let views: [(String, PixelImage, Double, Double)] = [
                        ("full", full, centerX, centerY),
                        ("tile", tile, centerX, centerY - Double(rendered.tileCrop.y)),
                        (
                            "actor-crop",
                            actorCrop,
                            centerX - Double(actorRect.x),
                            centerY - Double(actorRect.y)
                        ),
                        (
                            "zoom-detail",
                            zoomDetail,
                            centerX - Double(zoomRect.x),
                            centerY - Double(zoomRect.y)
                        ),
                    ]
                    let previousViews: [String: PixelImage]
                    if let previousMaterial {
                        let previous = try renderer.render(
                            recipe: isolated,
                            material: previousMaterial,
                            background: background,
                            configuration: .init(scale: 1, supersampling: 2)
                        )
                        let previousFull = try pixels(previous.fullScreen.pngData)
                        let previousTile = try pixels(previous.calendarTile.pngData)
                        previousViews = [
                            "full": previousFull,
                            "tile": previousTile,
                            "actor-crop": previousFull.cropped(
                                x: actorRect.x,
                                y: actorRect.y,
                                width: actorRect.width,
                                height: actorRect.height
                            ),
                            "zoom-detail": previousFull.cropped(
                                x: zoomRect.x,
                                y: zoomRect.y,
                                width: zoomRect.width,
                                height: zoomRect.height
                            ),
                        ]
                    } else {
                        previousViews = [:]
                    }

                    let eventLabel = String(actor.eventID.prefix(4))
                    for (viewName, image, viewCenterX, viewCenterY) in views {
                        observationCount += 1
                        let label = "fixture\(fixture.number)/c\(fixture.colorCount)/"
                            + "\(background.rawValue)/\(eventLabel)/\(viewName)"
                        let texture = mistTextureMetrics(
                            image: image,
                            centerX: viewCenterX,
                            centerY: viewCenterY,
                            diameter: diameter,
                            background: background
                        )
                        if !mistFineGrainPasses(texture) {
                            failures.append("coarse-grain \(label) \(texture)")
                        }
                        let signature = sealedSignature(
                            image,
                            centerX: viewCenterX,
                            centerY: viewCenterY,
                            radius: diameter * 0.48,
                            background: background
                        )
                        if !sealedTransparentBodyIsReadable(
                            sealedMetrics(signature),
                            family: .mist
                        ) {
                            failures.append("silhouette \(label) \(sealedMetrics(signature))")
                        }
                        if let previousImage = previousViews[viewName] {
                            let previousSignature = sealedSignature(
                                previousImage,
                                centerX: viewCenterX,
                                centerY: viewCenterY,
                                radius: diameter * 0.48,
                                background: background
                            )
                            let radialShift = sealedDistance(signature, previousSignature)
                            if radialShift < 0.012 {
                                failures.append("radial-palette \(label) distance=\(radialShift)")
                            }
                        }
                    }

                    for (viewName, image, backgroundCenterY) in [
                        ("full", full, centerY),
                        ("tile", tile, centerY - Double(rendered.tileCrop.y)),
                    ] {
                        let cleanliness = mistBackgroundCleanliness(
                            image,
                            centerX: centerX,
                            centerY: backgroundCenterY,
                            diameter: diameter,
                            localBlur: actor.localBlur,
                            background: background
                        )
                        if cleanliness.contaminated > 0 {
                            failures.append(
                                "background \(fixture.number)/\(background.rawValue)/"
                                    + "\(eventLabel)/\(viewName) eligible=\(cleanliness.eligible) "
                                    + "contaminated=\(cleanliness.contaminated)"
                            )
                        }
                    }
                }
            }
        }

        let depthFixture = manifest.breadth[0]
        let depthApproved = try #require(archive.fixtures.first {
            $0.fixtureIndex == 0
        }?.recipe)
        let depthActor = try #require(depthApproved.actors.first)
        let sharpActor = ActorCompositionRecipe(
            eventID: depthActor.eventID,
            position: depthActor.position,
            diameter: depthActor.diameter,
            depth: 0.15,
            localBlur: 0.006,
            cropAllowance: depthActor.cropAllowance,
            drawOrder: depthActor.drawOrder
        )
        let softActor = ActorCompositionRecipe(
            eventID: depthActor.eventID,
            position: depthActor.position,
            diameter: depthActor.diameter,
            depth: 0.85,
            localBlur: 0.060,
            cropAllowance: depthActor.cropAllowance,
            drawOrder: depthActor.drawOrder
        )
        let depthMaterial = MaterialDNA.fixture(
            daySeed: depthFixture.seed,
            eventIDs: depthFixture.eventIDs,
            family: .mist,
            requestedColorCount: 3
        )
        let sharp = try renderer.render(
            recipe: CompositionRecipe(
                daySeed: depthApproved.daySeed,
                grammar: depthApproved.grammar,
                viewport: depthApproved.viewport,
                actors: [sharpActor]
            ),
            material: depthMaterial,
            background: .lowContrast,
            configuration: .init(scale: 1, supersampling: 2)
        )
        let soft = try renderer.render(
            recipe: CompositionRecipe(
                daySeed: depthApproved.daySeed,
                grammar: depthApproved.grammar,
                viewport: depthApproved.viewport,
                actors: [softActor]
            ),
            material: depthMaterial,
            background: .lowContrast,
            configuration: .init(scale: 1, supersampling: 2)
        )
        let sharpPixels = try pixels(sharp.fullScreen.pngData)
        let softPixels = try pixels(soft.fullScreen.pngData)
        let depthCenterX = depthActor.position.x * 393
        let depthCenterY = depthActor.position.y * 852
        let depthDiameter = depthActor.diameter * 393
        let sharpness = mistRadialEdgeSharpness(
            sharpPixels,
            centerX: depthCenterX,
            centerY: depthCenterY,
            diameter: depthDiameter,
            background: .lowContrast
        )
        let softness = mistRadialEdgeSharpness(
            softPixels,
            centerX: depthCenterX,
            centerY: depthCenterY,
            diameter: depthDiameter,
            background: .lowContrast
        )
        #expect(sharpness >= softness * 1.20, "sharp=\(sharpness) soft=\(softness)")
        #expect(observationCount == 48)

        let failureClasses = Dictionary(grouping: failures) {
            $0.split(separator: " ").first.map(String.init) ?? "unknown"
        }.mapValues(\.count)
        #expect(failures.isEmpty, Comment(rawValue:
            "mist native-1x failures=\(failures.count) classes=\(failureClasses)\n"
                + failures.prefix(160).joined(separator: "\n")
        ))
    }

    @Test("mist fine-field invariants preserve alpha scale isotropy and radial ownership")
    func mistFineFieldInvariantControlsAreObservable() {
        let side = 48
        let background = MaterialRenderer.backgroundColor(for: .lowContrast)
        let fixture = mistRadialColorFixture(side: side, background: background)
        let actorID = "mist-invariant-actor"
        let directField = mistIsotropicFineField(
            side: side,
            presentationScale: 1,
            actorID: actorID,
            alpha: fixture.pixels.map(\.alpha)
        )
        let supersampledAlpha = mistUpsampledAlpha(fixture.pixels.map(\.alpha), side: side, scale: 2)
        let supersampledField = mistIsotropicFineField(
            side: side * 2,
            presentationScale: 2,
            actorID: actorID,
            alpha: supersampledAlpha
        )
        let downsampledField = mistDownsampledField(supersampledField, side: side * 2, scale: 2)
        let direct = mistRayGrainWitness(
            fixture.pixels,
            radialColors: fixture.radialColors,
            field: directField,
            background: background
        )
        let originalAlpha = fixture.pixels.map(\.alpha)
        let finalAlpha = direct.map(\.alpha)

        #expect(originalAlpha == finalAlpha)
        #expect(fixture11AlphaHistogram(originalAlpha) == fixture11AlphaHistogram(finalAlpha))
        #expect(fixture11AlphaQuantiles(originalAlpha) == fixture11AlphaQuantiles(finalAlpha))

        let dc = mistAlphaWeightedDC(directField, alpha: originalAlpha)
        let quantizationBound = 1.0 / (255.0 * sqrt(Double(max(originalAlpha.filter { $0 > 0 }.count, 1))))
        #expect(abs(dc) <= quantizationBound, "dc=\(dc) bound=\(quantizationBound)")
        #expect(mistAllSamplesRemainOnRadialRay(
            original: fixture.pixels,
            candidate: direct,
            radialColors: fixture.radialColors,
            background: background
        ))

        let directionalSpread = mistDirectionalEnergySpread(directField, side: side)
        let rotatedSpread = mistDirectionalEnergySpread(
            mistRotatedQuarterTurn(directField, side: side),
            side: side
        )
        #expect(directionalSpread <= 0.35, "directional spread=\(directionalSpread)")
        #expect(abs(directionalSpread - rotatedSpread) <= 0.000_000_001)
        #expect(zip(directField, downsampledField).allSatisfy {
            abs($0 - $1) <= Double.ulpOfOne * 8
        })
        let directMetrics = mistTextureMetrics(luminance: directField, side: side)
        let downsampledMetrics = mistTextureMetrics(luminance: downsampledField, side: side)
        #expect(mistFineGrainPasses(directMetrics), Comment(rawValue: "direct \(directMetrics)"))
        #expect(mistFineGrainPasses(downsampledMetrics), Comment(rawValue: "ss2 \(downsampledMetrics)"))

        let tinySide = 16
        let tinyAlpha = Array(repeating: UInt8.max, count: tinySide * tinySide)
        let tinyDirect = mistIsotropicFineField(
            side: tinySide,
            presentationScale: 1,
            actorID: actorID,
            alpha: tinyAlpha
        )
        let tinySupersampled = mistIsotropicFineField(
            side: tinySide * 2,
            presentationScale: 2,
            actorID: actorID,
            alpha: mistUpsampledAlpha(tinyAlpha, side: tinySide, scale: 2)
        )
        let tinyDownsampled = mistDownsampledField(
            tinySupersampled,
            side: tinySide * 2,
            scale: 2
        )
        #expect(mistFineGrainPasses(mistTextureMetrics(luminance: tinyDirect, side: tinySide)))
        #expect(mistFineGrainPasses(mistTextureMetrics(
            luminance: tinyDownsampled,
            side: tinySide
        )))

        let repeated = mistIsotropicFineField(
            side: side,
            presentationScale: 1,
            actorID: actorID,
            alpha: originalAlpha
        )
        let siblingInserted = mistIsotropicFineField(
            side: side,
            presentationScale: 1,
            actorID: actorID,
            alpha: originalAlpha,
            siblingEventIDs: ["unrelated-before", actorID, "unrelated-after"]
        )
        #expect(directField == repeated)
        #expect(directField == siblingInserted)

        #expect(!mistFineGrainPasses(mistTextureMetrics(
            luminance: mistBrokenGrainMutation(directField),
            side: side
        )))
        #expect(!mistFineGrainPasses(mistTextureMetrics(
            luminance: mistCoarseCellMutation(directField, side: side, cellSide: 6),
            side: side
        )))
        #expect(!mistFineGrainPasses(mistTextureMetrics(
            luminance: mistCheckerMutation(directField, side: side, cellSide: 4),
            side: side
        )))
    }

    @Test("mist canonical grain seed follows appearance rather than actor labels")
    func mistCanonicalGrainSeedContractIsObservable() throws {
        let renderer = MaterialRenderer()
        let source = try #require(MaterialDNA.fixture(
            daySeed: 0x5157_5EED,
            eventIDs: ["mist-seed-source"],
            family: .mist,
            requestedColorCount: 3
        ).actor("mist-seed-source"))

        func copy(
            _ actor: ActorMaterialRecipe,
            eventID: String? = nil,
            family: MaterialFamily? = nil,
            mutation: MaterialMutation?? = nil,
            colors: [MaterialColor]? = nil,
            fields: [RadialField]? = nil,
            baseOpacity: Double? = nil,
            edgeSoftness: Double? = nil,
            contourWidth: Double? = nil,
            contourCount: Int? = nil,
            counterformRadius: Double?? = nil,
            counterformSoftness: Double? = nil
        ) -> ActorMaterialRecipe {
            ActorMaterialRecipe(
                eventID: eventID ?? actor.eventID,
                family: family ?? actor.family,
                mutation: mutation ?? actor.mutation,
                colors: colors ?? actor.colors,
                fields: fields ?? actor.fields,
                baseOpacity: baseOpacity ?? actor.baseOpacity,
                edgeSoftness: edgeSoftness ?? actor.edgeSoftness,
                contourWidth: contourWidth ?? actor.contourWidth,
                contourCount: contourCount ?? actor.contourCount,
                counterformRadius: counterformRadius ?? actor.counterformRadius,
                counterformSoftness: counterformSoftness ?? actor.counterformSoftness,
                organicTopology: nil
            )
        }

        let ascii = copy(source, eventID: "mist-label-ascii")
        let unicode = copy(source, eventID: "туман-霧-🌫️")
        let asciiBytes = try renderer.renderActor(ascii, pixelSize: 128).pngData
        let unicodeBytes = try renderer.renderActor(unicode, pixelSize: 128).pngData
        let repeatedAsciiBytes = try renderer.renderActor(ascii, pixelSize: 128).pngData
        #expect(mistCanonicalSeedDigest(ascii) == mistCanonicalSeedDigest(unicode))
        #expect(asciiBytes == unicodeBytes, "label-only eventID change rerolled grain")
        #expect(asciiBytes == repeatedAsciiBytes)

        let firstField = try #require(source.fields.first)
        func replacingFirstField(_ replacement: RadialField) -> [RadialField] {
            [replacement] + source.fields.dropFirst()
        }
        let appearanceVariants = [
            copy(source, family: .gradient, mutation: .some(nil)),
            copy(source, colors: source.colors.reversed()),
            copy(source, fields: source.fields.reversed()),
            copy(source, fields: replacingFirstField(.init(
                focus: .init(x: firstField.focus.x + 0.03125, y: firstField.focus.y),
                radius: firstField.radius,
                softness: firstField.softness,
                opacity: firstField.opacity,
                colorIndex: firstField.colorIndex,
                blend: firstField.blend
            ))),
            copy(source, fields: replacingFirstField(.init(
                focus: .init(x: firstField.focus.x, y: firstField.focus.y + 0.03125),
                radius: firstField.radius,
                softness: firstField.softness,
                opacity: firstField.opacity,
                colorIndex: firstField.colorIndex,
                blend: firstField.blend
            ))),
            copy(source, fields: replacingFirstField(.init(
                focus: firstField.focus,
                radius: firstField.radius * 0.91,
                softness: firstField.softness,
                opacity: firstField.opacity,
                colorIndex: firstField.colorIndex,
                blend: firstField.blend
            ))),
            copy(source, fields: replacingFirstField(.init(
                focus: firstField.focus,
                radius: firstField.radius,
                softness: firstField.softness * 0.89,
                opacity: firstField.opacity,
                colorIndex: firstField.colorIndex,
                blend: firstField.blend
            ))),
            copy(source, fields: replacingFirstField(.init(
                focus: firstField.focus,
                radius: firstField.radius,
                softness: firstField.softness,
                opacity: firstField.opacity * 0.87,
                colorIndex: firstField.colorIndex,
                blend: firstField.blend
            ))),
            copy(source, fields: replacingFirstField(.init(
                focus: firstField.focus,
                radius: firstField.radius,
                softness: firstField.softness,
                opacity: firstField.opacity,
                colorIndex: (firstField.colorIndex + 1) % source.colors.count,
                blend: firstField.blend
            ))),
            copy(source, fields: replacingFirstField(.init(
                focus: firstField.focus,
                radius: firstField.radius,
                softness: firstField.softness,
                opacity: firstField.opacity,
                colorIndex: firstField.colorIndex,
                blend: firstField.blend == .screen ? .multiply : .screen
            ))),
            copy(source, baseOpacity: source.baseOpacity * 0.83),
            copy(source, edgeSoftness: source.edgeSoftness + 0.0275),
        ]
        let sourceSeed = mistCanonicalSeedDigest(source)
        let sourcePixels = try renderer.renderActor(
            source,
            pixelSize: 128,
            background: .lowContrast
        ).pngData
        for variant in appearanceVariants {
            #expect(mistCanonicalSeedDigest(variant) != sourceSeed)
            let variantPixels = try renderer.renderActor(
                variant,
                pixelSize: 128,
                background: .lowContrast
            ).pngData
            #expect(variantPixels != sourcePixels)
        }

        let provenanceOnly = copy(source, mutation: .some(nil))
        let unusedStructureOnly = copy(
            source,
            contourWidth: 0.37,
            contourCount: 3,
            counterformRadius: .some(0.21),
            counterformSoftness: 0.19
        )
        for equivalent in [provenanceOnly, unusedStructureOnly] {
            #expect(mistCanonicalSeedDigest(equivalent) == sourceSeed)
            let equivalentPixels = try renderer.renderActor(
                equivalent,
                pixelSize: 128,
                background: .lowContrast
            ).pngData
            #expect(equivalentPixels == sourcePixels)
        }

        let retained = copy(source, eventID: "retained")
        let sibling = copy(source, eventID: "sibling")
        let retainedActor = ActorCompositionRecipe(
            eventID: retained.eventID,
            position: .init(x: 0.24, y: 0.28),
            diameter: 0.20,
            depth: 0.25,
            localBlur: 0.012,
            cropAllowance: 0,
            drawOrder: 1
        )
        let siblingActor = ActorCompositionRecipe(
            eventID: sibling.eventID,
            position: .init(x: 0.78, y: 0.72),
            diameter: 0.16,
            depth: 0.70,
            localBlur: 0.018,
            cropAllowance: 0,
            drawOrder: 2
        )
        func scene(_ actors: [ActorCompositionRecipe], materialActors: [ActorMaterialRecipe]) throws -> PixelImage {
            let recipe = CompositionRecipe(
                daySeed: 17,
                grammar: .openField,
                viewport: .phone,
                actors: actors
            )
            let dna = DailyMaterialDNA(
                daySeed: 17,
                family: .mist,
                accentMutation: .diffuseMist,
                requestedColorCount: 3,
                actors: materialActors
            )
            return try pixels(renderer.render(
                recipe: recipe,
                material: dna,
                background: .dark,
                configuration: .init(scale: 1, supersampling: 2)
            ).fullScreen.pngData)
        }
        let isolatedScene = try scene([retainedActor], materialActors: [retained])
        let insertedScene = try scene(
            [retainedActor, siblingActor],
            materialActors: [retained, sibling]
        )
        let reorderedScene = try scene(
            [siblingActor, retainedActor],
            materialActors: [sibling, retained]
        )
        let crop = fixture11CenteredCrop(
            centerX: retainedActor.position.x * 393,
            centerY: retainedActor.position.y * 852,
            side: 96,
            width: isolatedScene.width,
            height: isolatedScene.height
        )
        let isolatedCrop = isolatedScene.cropped(
            x: crop.x, y: crop.y, width: crop.width, height: crop.height
        ).rgba
        #expect(insertedScene.cropped(
            x: crop.x, y: crop.y, width: crop.width, height: crop.height
        ).rgba == isolatedCrop)
        #expect(reorderedScene.cropped(
            x: crop.x, y: crop.y, width: crop.width, height: crop.height
        ).rgba == isolatedCrop)

        let representative = ActorMaterialRecipe(
            eventID: "excluded-label",
            family: .mist,
            mutation: .diffuseMist,
            colors: [
                .init(red: 0.125, green: 0.5, blue: 0.875),
                .init(red: 1, green: 0, blue: 0.25),
            ],
            fields: [.init(
                focus: .init(x: 0.25, y: 0.75),
                radius: 0.625,
                softness: 0.5,
                opacity: 0.875,
                colorIndex: 1,
                blend: .screen
            )],
            baseOpacity: 0.7,
            edgeSoftness: 0.095,
            contourWidth: 0,
            contourCount: 0,
            counterformRadius: nil,
            counterformSoftness: 0
        )
        #expect(mistCanonicalSeedBytes(representative).count == 163)
        #expect(mistCanonicalSeedDigest(representative) ==
            "50a633c7b812775d8788c0eaeaf963a4e95bae096e1b9d213a3a751732faa95d")

        let distinctDigests = Set((0..<2_048).map { index in
            copy(source, colors: [
                .init(
                    red: Double(index + 1) / 2_049,
                    green: source.colors[0].green,
                    blue: source.colors[0].blue
                ),
            ] + source.colors.dropFirst())
        }.map(mistCanonicalSeedDigest))
        #expect(distinctDigests.count == 2_048)
    }

    @Test("halo fixtures 15 through 17 retain a compact body and surrounding aura at sealed 1x")
    func haloFixtures15Through17RetainCompactBodyAndAuraAtSceneScale() throws {
        // Production regressions caught here, before the body:
        // - halo collapsing to one soft filled disc with no compact body;
        // - the surrounding aura disappearing after blur or 1x sampling;
        // - medium/tiny halo pixels becoming interchangeable with gradient,
        //   mist, or luminous in any canonical presentation.
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let renderer = MaterialRenderer()
        let fixtures = [
            (number: 15, colorCount: 1, layoutIndex: 3),
            (number: 16, colorCount: 2, layoutIndex: 4),
            (number: 17, colorCount: 3, layoutIndex: 5),
        ]
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        let controls: [MaterialFamily] = [.gradient, .mist, .luminous]
        let families = [MaterialFamily.halo] + controls
        var observations = [HaloMatrixKey: SealedOpticalSignature]()
        var identityFailures = [String]()
        var separationFailures = [String]()

        for fixture in fixtures {
            let layout = manifest.breadth[fixture.layoutIndex]
            let approved = try #require(archive.fixtures.first {
                $0.fixtureIndex == fixture.layoutIndex
            }?.recipe)
            let actors = approved.actors.filter { $0.diameter <= 0.36 }
            #expect(!actors.isEmpty)

            for background in backgrounds {
                for actor in actors {
                    let sizeClass = actor.diameter < 0.12 ? "tiny" : "medium"
                    let isolated = CompositionRecipe(
                        daySeed: approved.daySeed,
                        grammar: approved.grammar,
                        viewport: approved.viewport,
                        actors: [actor]
                    )
                    for family in families {
                        let dna = MaterialDNA.fixture(
                            daySeed: layout.seed,
                            eventIDs: layout.eventIDs,
                            family: family,
                            requestedColorCount: fixture.colorCount
                        )
                        let material = try #require(dna.actor(actor.eventID))
                        let rendered = try renderer.render(
                            recipe: isolated,
                            material: dna,
                            background: background,
                            configuration: .init(scale: 1)
                        )
                        let full = try pixels(rendered.fullScreen.pngData)
                        let tile = try pixels(rendered.calendarTile.pngData)
                        let centerX = actor.position.x * 393
                        let centerY = actor.position.y * 852
                        let diameter = actor.diameter * 393
                        let actorPixels = try pixels(renderer.renderActor(
                            material,
                            pixelSize: actorPixelDiameter(actor),
                            background: background
                        ).pngData)
                        let exactRect = fixture11CenteredCrop(
                            centerX: centerX,
                            centerY: centerY,
                            side: max(1, Int(ceil(diameter * 1.15))),
                            width: full.width,
                            height: full.height
                        )
                        let exact = full.cropped(
                            x: exactRect.x,
                            y: exactRect.y,
                            width: exactRect.width,
                            height: exactRect.height
                        )
                        let views: [(SealedMaterialView, PixelImage, Double, Double, Double)] = [
                            (.full, full, centerX, centerY, diameter),
                            (.tile, tile, centerX, centerY - Double(rendered.tileCrop.y), diameter),
                            (
                                .actor,
                                actorPixels,
                                Double(actorPixels.width) * 0.5,
                                Double(actorPixels.height) * 0.5,
                                Double(actorPixels.width)
                            ),
                            (
                                .exact,
                                exact,
                                centerX - Double(exactRect.x),
                                centerY - Double(exactRect.y),
                                diameter
                            ),
                        ]
                        for (view, image, viewCenterX, viewCenterY, viewDiameter) in views {
                            let key = HaloMatrixKey(
                                fixture: fixture.number,
                                eventID: actor.eventID,
                                background: background,
                                family: family,
                                view: view
                            )
                            observations[key] = sealedSignature(
                                image,
                                centerX: viewCenterX,
                                centerY: viewCenterY,
                                radius: viewDiameter * 0.48,
                                background: background
                            )
                            guard family == .halo else { continue }
                            let metrics = haloBodyAuraMetrics(
                                image,
                                centerX: viewCenterX,
                                centerY: viewCenterY,
                                diameter: viewDiameter,
                                material: material,
                                background: background
                            )
                            if !haloBodyAuraPasses(metrics) {
                                identityFailures.append(
                                    "fixture\(fixture.number)/c\(fixture.colorCount)/\(background.rawValue)/"
                                        + "\(sizeClass)-\(actor.eventID.prefix(4))/\(view.rawValue) "
                                        + "bodyP50=\(metrics.bodyP50) auraP50=\(metrics.auraP50) "
                                        + "auraP75=\(metrics.auraP75) coverage=\(metrics.auraAngularCoverage) "
                                        + "bodyChroma=\(metrics.bodyChromaP50)"
                                )
                            }
                        }
                    }

                    for view in SealedMaterialView.allCases {
                        let haloKey = HaloMatrixKey(
                            fixture: fixture.number,
                            eventID: actor.eventID,
                            background: background,
                            family: .halo,
                            view: view
                        )
                        let halo = try #require(observations[haloKey])
                        for control in controls {
                            let controlKey = HaloMatrixKey(
                                fixture: fixture.number,
                                eventID: actor.eventID,
                                background: background,
                                family: control,
                                view: view
                            )
                            let distance = sealedDistance(halo, try #require(observations[controlKey]))
                            if distance < 0.030 {
                                separationFailures.append(
                                    "fixture\(fixture.number)/c\(fixture.colorCount)/\(background.rawValue)/"
                                        + "\(sizeClass)-\(actor.eventID.prefix(4))/\(view.rawValue)/"
                                        + "halo~\(control.rawValue) distance=\(distance)"
                                )
                            }
                        }
                    }
                }
            }
        }

        let readable = HaloBodyAuraMetrics(
            bodyP50: 0.24,
            auraP50: 0.10,
            auraP75: 0.12,
            auraAngularCoverage: 0.90,
            bodyChromaP50: 0.18
        )
        #expect(haloBodyAuraPasses(readable))
        #expect(!haloBodyAuraPasses(HaloBodyAuraMetrics(
            bodyP50: 0.12,
            auraP50: 0.10,
            auraP75: 0.12,
            auraAngularCoverage: 0.90,
            bodyChromaP50: 0.18
        )))
        #expect(!haloBodyAuraPasses(HaloBodyAuraMetrics(
            bodyP50: 0.24,
            auraP50: 0.01,
            auraP75: 0.02,
            auraAngularCoverage: 0.20,
            bodyChromaP50: 0.18
        )))
        #expect(identityFailures.isEmpty, Comment(rawValue:
            "halo compact-body/aura failures=\(identityFailures.count)\n"
                + identityFailures.joined(separator: "\n")
        ))
        #expect(separationFailures.isEmpty, Comment(rawValue:
            "halo matched-control collapse failures=\(separationFailures.count)\n"
                + separationFailures.joined(separator: "\n")
        ))
    }

    @Test("halo nucleus joins its aura without an inner-radius contrast ridge")
    func haloNucleusHasBroadContinuousSceneScaleTransition() throws {
        // Production regression caught here: compositing a separately sharpened
        // compact body after actor-local depth blur creates a pasted-disc edge at
        // the authored inner radius even though the nucleus and aura both remain.
        let smoothControl = haloNucleusContinuityControl(.broadTransition)
        let sharpDiscControl = haloNucleusContinuityControl(.sharpPastedDisc)
        let missingNucleusControl = haloNucleusContinuityControl(.missingNucleus)
        let collapsedBlurControl = haloNucleusContinuityControl(.collapsedSingleBlur)
        #expect(haloNucleusContinuityPasses(smoothControl))
        #expect(!haloNucleusContinuityPasses(sharpDiscControl))
        #expect(!haloNucleusContinuityPasses(missingNucleusControl))
        #expect(!haloNucleusContinuityPasses(collapsedBlurControl))

        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let renderer = MaterialRenderer()
        let fixtureCases = [
            (label: "fixture15", colorCount: 1, layoutIndex: 3, eventID: nil as String?),
            (label: "fixture16", colorCount: 2, layoutIndex: 4, eventID: nil as String?),
            (label: "fixture17", colorCount: 3, layoutIndex: 5, eventID: nil as String?),
            (
                label: "layout11-c1",
                colorCount: 1,
                layoutIndex: 11,
                eventID: "5FA2D140-7C0E-45B9-BE3D-8124A937EF06"
            ),
            (
                label: "layout11-c2",
                colorCount: 2,
                layoutIndex: 11,
                eventID: "5FA2D140-7C0E-45B9-BE3D-8124A937EF06"
            ),
            (
                label: "layout11-c3",
                colorCount: 3,
                layoutIndex: 11,
                eventID: "5FA2D140-7C0E-45B9-BE3D-8124A937EF06"
            ),
        ]
        var failures = [String]()

        for fixture in fixtureCases {
            let layout = manifest.breadth[fixture.layoutIndex]
            let approved = try #require(archive.fixtures.first {
                $0.fixtureIndex == fixture.layoutIndex
            }?.recipe)
            let actors = approved.actors.filter { actor in
                if let eventID = fixture.eventID { return actor.eventID == eventID }
                return actor.diameter <= 0.36
            }
            #expect(!actors.isEmpty)
            let dna = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .halo,
                requestedColorCount: fixture.colorCount
            )

            for background in [BackgroundCondition.light, .dark, .lowContrast] {
                for scale in [1, 3] {
                    for actor in actors {
                        let material = try #require(dna.actor(actor.eventID))
                        let topology = try #require(material.organicTopology)
                        let isolated = CompositionRecipe(
                            daySeed: approved.daySeed,
                            grammar: approved.grammar,
                            viewport: approved.viewport,
                            actors: [actor]
                        )
                        let rendered = try renderer.render(
                            recipe: isolated,
                            material: dna,
                            background: background,
                            configuration: .init(scale: scale)
                        )
                        let image = try pixels(rendered.fullScreen.pngData)
                        let sceneDiameter = actor.diameter * 393 * Double(scale)
                        let actorCenterX = actor.position.x * 393 * Double(scale)
                        let actorCenterY = actor.position.y * 852 * Double(scale)
                        let metrics = haloNucleusContinuityMetrics(
                            image,
                            nucleusCenterX: actorCenterX
                                + (topology.innerCenter.x - 0.5) * sceneDiameter,
                            nucleusCenterY: actorCenterY
                                + (topology.innerCenter.y - 0.5) * sceneDiameter,
                            innerRadius: topology.innerRadius * sceneDiameter,
                            background: background
                        )
                        if !haloNucleusContinuityPasses(metrics) {
                            failures.append(
                                "\(fixture.label)/\(background.rawValue)/\(scale)x/"
                                    + "\(actor.eventID.prefix(4)) \(metrics)"
                            )
                        }
                    }
                }
            }
        }

        let cropLayout = manifest.breadth[0]
        let cropEventID = try #require(cropLayout.eventIDs.first)
        for colorCount in 1...3 {
            let cropMaterial = try #require(MaterialDNA.fixture(
                daySeed: cropLayout.seed,
                eventIDs: [cropEventID],
                family: .halo,
                requestedColorCount: colorCount
            ).actor(cropEventID))
            let cropTopology = try #require(cropMaterial.organicTopology)
            for scale in [1, 3] {
                let pixelSize = 160 * scale
                let crop = try pixels(renderer.renderActor(
                    cropMaterial,
                    pixelSize: pixelSize,
                    background: .lowContrast
                ).pngData)
                let metrics = haloNucleusContinuityMetrics(
                    crop,
                    nucleusCenterX: (0.5 + cropTopology.innerCenter.x - 0.5)
                        * Double(pixelSize),
                    nucleusCenterY: (0.5 + cropTopology.innerCenter.y - 0.5)
                        * Double(pixelSize),
                    innerRadius: cropTopology.innerRadius * Double(pixelSize),
                    background: .lowContrast
                )
                if !haloNucleusContinuityPasses(metrics) {
                    failures.append("actor-crop/c\(colorCount)/\(scale)x \(metrics)")
                }
            }
        }

        #expect(failures.isEmpty, Comment(rawValue:
            "halo inner-radius continuity failures=\(failures.count)\n"
                + failures.joined(separator: "\n")
        ))
    }

    @Test("native outline presentation keeps thin open contours in every core condition")
    func outlineSceneScaleKeepsOpenCenterAcrossNativePresentations() throws {
        let controlSide = 129
        let controlCenter = Double(controlSide) * 0.5
        let controlRadius = 54.0
        let emptyControl = outlineNativeControl(side: controlSide) { _, _ in 0 }
        let thinOpenContour = outlineNativeControl(side: controlSide) { radius, _ in
            (0.78...0.84).contains(radius) ? 1 : 0
        }
        let filledTorus = outlineNativeControl(side: controlSide) { radius, _ in
            (0.30...1.02).contains(radius) ? 1 : 0
        }
        let rippleFilledDisc = outlineNativeControl(side: controlSide) { radius, _ in
            [0.18, 0.34, 0.50, 0.66, 0.82, 0.98].contains {
                abs(radius - $0) <= 0.035
            } ? 1 : 0
        }
        let vanishedContour = emptyControl
        let brokenArc = outlineNativeControl(side: controlSide) { radius, angle in
            (0.78...0.84).contains(radius) && abs(angle) > Double.pi * 0.30 ? 1 : 0
        }
        let lowContrastContour = outlineNativeControl(side: controlSide) { radius, _ in
            (0.78...0.84).contains(radius) ? 0.02 : 0
        }
        let controls: [(String, PixelImage, Bool)] = [
            ("thin-open-contour", thinOpenContour, true),
            ("filled-torus", filledTorus, false),
            ("ripple-filled-disc", rippleFilledDisc, false),
            ("vanished-contour", vanishedContour, false),
            ("broken-arc", brokenArc, false),
            ("low-contrast-contour", lowContrastContour, false),
        ]
        for (label, image, expectedPass) in controls {
            let metrics = outlineNativeIdentityMetrics(
                image,
                reference: emptyControl,
                centerX: controlCenter,
                centerY: controlCenter,
                pixelRadius: controlRadius
            )
            try #require(
                outlineNativeIdentityPasses(metrics) == expectedPass,
                Comment(rawValue: "synthetic \(label) expectedPass=\(expectedPass) \(metrics)")
            )
            // Candidate RGB never adjudicates physical eligibility. These
            // controls are all physically attainable, so every malformed or
            // low-contrast candidate must still face the unchanged predicate.
            #expect(outlineNativePresentationIsEligible(attainablePeakContrast: 0.20))
        }
        #expect(!outlineNativePresentationIsEligible(attainablePeakContrast: 0.069_999))
        #expect(outlineNativePresentationIsEligible(attainablePeakContrast: 0.070))

        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == 11
        }?.recipe)
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        let renderer = MaterialRenderer()
        var geometricObservationCount = 0
        var eligibleObservationCount = 0
        var physicalOcclusions = [(label: String, ceiling: Double)]()
        var worstPoleMutationWitnesses = [String]()
        var selectorObservations = [OutlineSelectorObservation]()

        for colorCount in 1...3 {
            let material = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .outline,
                requestedColorCount: colorCount
            )
            for background in backgrounds {
                let instrumentation = MaterialRenderInstrumentation()
                let rendered = try renderer.render(
                    recipe: recipe,
                    material: material,
                    background: background,
                    configuration: .init(
                        scale: 1,
                        supersampling: 2,
                        outlineVisibilityPlacement: .none,
                        instrumentation: instrumentation,
                        presentationEvidenceRequest: .perActor
                    )
                )
                let presentationEvidence = try #require(rendered.presentationEvidence)
                let full = try pixels(rendered.fullScreen.pngData)
                let tile = try pixels(rendered.calendarTile.pngData)
                try #require(
                    instrumentation.projectedActorLayers.count
                        == presentationEvidence.actors.count
                )
                try #require(
                    instrumentation.outlineVisibilityPalettePoleLayers.count
                        == presentationEvidence.actors.count
                )
                try #require(
                    instrumentation.outlineVisibilitySelectedPaletteIndices.count
                        == presentationEvidence.actors.count
                )
                let projectedLayers = try instrumentation.projectedActorLayers.map { image in
                    PixelImage(
                        width: image.width,
                        height: image.height,
                        rgba: try rgbaBytes(image)
                    )
                }
                let palettePoleLayers = try instrumentation
                    .outlineVisibilityPalettePoleLayers.map { actorLayers in
                        try actorLayers.map { image in
                            PixelImage(
                                width: image.width,
                                height: image.height,
                                rgba: try rgbaBytes(image)
                            )
                        }
                    }
                let base = try pixels(
                    presentationEvidence.actors[0].removed.fullScreen.pngData
                )
                var prefixes = [base]
                prefixes.reserveCapacity(projectedLayers.count + 1)
                for layer in projectedLayers {
                    prefixes.append(outlineSourceOver(source: layer, underlay: prefixes.last!))
                }
                var suffixes = [PixelImage](
                    repeating: PixelImage(
                        width: full.width,
                        height: full.height,
                        rgba: Data(repeating: 0, count: full.width * full.height * 4)
                    ),
                    count: projectedLayers.count + 1
                )
                for actorIndex in projectedLayers.indices.reversed() {
                    suffixes[actorIndex] = outlineSourceOver(
                        source: suffixes[actorIndex + 1],
                        underlay: projectedLayers[actorIndex]
                    )
                }
                #expect(prefixes.last?.rgba == full.rgba)

                for (actorIndex, actorEvidence) in presentationEvidence.actors.enumerated() {
                    let actor = try #require(recipe.actor(actorEvidence.eventID))
                    let actorMaterial = try #require(material.actor(actorEvidence.eventID))
                    let selectedPaletteIndex = instrumentation
                        .outlineVisibilitySelectedPaletteIndices[actorIndex]
                    try #require(palettePoleLayers[actorIndex].indices.contains(
                        selectedPaletteIndex
                    ))
                    #expect(
                        projectedLayers[actorIndex].rgba
                            == palettePoleLayers[actorIndex][selectedPaletteIndex].rgba
                    )
                    var selectorCandidateLayers = [
                        "gamut-ray": projectedLayers[actorIndex],
                    ]
                    for (poleIndex, color) in actorMaterial.colors.enumerated() {
                        selectorCandidateLayers["assigned-pole-\(poleIndex)"] =
                            outlineSelectorRawTargetLayer(
                                gamutPoleLayers: palettePoleLayers[actorIndex],
                                assignedColors: actorMaterial.colors,
                                prefix: prefixes[actorIndex],
                                target: color
                            )
                    }
                    let inverseColorCount = 1 / Double(actorMaterial.colors.count)
                    selectorCandidateLayers["centroid"] = outlineSelectorRawTargetLayer(
                        gamutPoleLayers: palettePoleLayers[actorIndex],
                        assignedColors: actorMaterial.colors,
                        prefix: prefixes[actorIndex],
                        target: MaterialColor(
                            red: actorMaterial.colors.reduce(0) { $0 + $1.red }
                                * inverseColorCount,
                            green: actorMaterial.colors.reduce(0) { $0 + $1.green }
                                * inverseColorCount,
                            blue: actorMaterial.colors.reduce(0) { $0 + $1.blue }
                                * inverseColorCount
                        )
                    )
                    let authorityFullAlpha = try alphaBytes(
                        actorEvidence.isolated.fullScreen.pngData
                    )
                    let authorityTileAlpha = try alphaBytes(
                        actorEvidence.isolated.calendarTile.pngData
                    )
                    #expect(authorityTileAlpha == fixture11CroppedBytes(
                        authorityFullAlpha,
                        sourceWidth: full.width,
                        crop: rendered.tileCrop,
                        bytesPerPixel: 1
                    ))
                    let withoutActor = outlineSourceOver(
                        source: suffixes[actorIndex + 1],
                        underlay: prefixes[actorIndex]
                    )
                    var effectiveContributionLabels = Data(
                        repeating: 255,
                        count: full.width * full.height
                    )
                    for pixelIndex in 0..<(full.width * full.height) {
                        var effectiveAlpha = Double(
                            projectedLayers[actorIndex].rgba[pixelIndex * 4 + 3]
                        ) / 255
                        if actorIndex + 1 < projectedLayers.count {
                            for laterIndex in (actorIndex + 1)..<projectedLayers.count {
                                effectiveAlpha *= 1 - Double(
                                    projectedLayers[laterIndex].rgba[pixelIndex * 4 + 3]
                                ) / 255
                            }
                        }
                        if effectiveAlpha > 0 {
                            effectiveContributionLabels[pixelIndex] = UInt8(actorIndex)
                        }
                    }
                    let tileContributionLabels = fixture11CroppedBytes(
                        effectiveContributionLabels,
                        sourceWidth: full.width,
                        crop: rendered.tileCrop,
                        bytesPerPixel: 1
                    )
                    let withoutActorTile = withoutActor.cropped(
                        x: rendered.tileCrop.x,
                        y: rendered.tileCrop.y,
                        width: rendered.tileCrop.width,
                        height: rendered.tileCrop.height
                    )
                    let centerX = actor.position.x * 393
                    let centerY = actor.position.y * 852
                    let pixelRadius = actor.diameter * 393 * 0.5
                    let views: [(String, PixelImage, PixelImage, Data, Double, PixelRect?)] = [
                        (
                            "full",
                            full,
                            withoutActor,
                            effectiveContributionLabels,
                            centerY,
                            nil
                        ),
                        (
                            "tile",
                            tile,
                            withoutActorTile,
                            tileContributionLabels,
                            centerY - Double(rendered.tileCrop.y),
                            rendered.tileCrop
                        ),
                    ]
                    for (view, image, reference, ownerLabels, viewCenterY, crop) in views {
                        guard outlineNativeActorIsEligible(
                            actor,
                            centerX: centerX,
                            centerY: viewCenterY,
                            width: image.width,
                            height: image.height
                        ) else { continue }
                        geometricObservationCount += 1
                        let candidateMetrics = Dictionary(uniqueKeysWithValues:
                            selectorCandidateLayers.map { candidateID, candidateLayer in
                                let candidatePrefix = outlineSourceOver(
                                    source: candidateLayer,
                                    underlay: prefixes[actorIndex]
                                )
                                let candidateFull = outlineSourceOver(
                                    source: suffixes[actorIndex + 1],
                                    underlay: candidatePrefix
                                )
                                let candidate = crop.map {
                                    candidateFull.cropped(
                                        x: $0.x,
                                        y: $0.y,
                                        width: $0.width,
                                        height: $0.height
                                    )
                                } ?? candidateFull
                                return (
                                    candidateID,
                                    outlineNativeIdentityMetrics(
                                        candidate,
                                        reference: reference,
                                        centerX: centerX,
                                        centerY: viewCenterY,
                                        pixelRadius: pixelRadius,
                                        ownerIndex: UInt8(actorIndex),
                                        ownerLabels: ownerLabels
                                    )
                                )
                            }
                        )
                        let attainablePeakContrast = candidateMetrics.values
                            .map(\.peakContrast)
                            .max() ?? 0
                        let label = "c\(colorCount)/\(background.rawValue)/"
                            + "\(actor.eventID.prefix(4))/\(view)"
                        guard outlineNativePresentationIsEligible(
                            attainablePeakContrast: attainablePeakContrast
                        ) else {
                            physicalOcclusions.append((label, attainablePeakContrast))
                            continue
                        }
                        eligibleObservationCount += 1
                        selectorObservations.append(OutlineSelectorObservation(
                            label: label,
                            key: "\(actor.eventID)|\(background.rawValue)",
                            candidateMetrics: candidateMetrics
                        ))
                        let assignedPoleMetrics = candidateMetrics.filter {
                            $0.key.hasPrefix("assigned-pole-")
                        }.map(\.value)
                        if let worst = assignedPoleMetrics.min(by: {
                            $0.peakContrast < $1.peakContrast
                        }), !outlineNativeIdentityPasses(worst) {
                            let baseline = candidateMetrics["gamut-ray"]!
                            worstPoleMutationWitnesses.append(
                                "\(label) gamut=\(baseline) worst=\(worst)"
                            )
                        }
                    }
                }
            }
        }

        let fixedCandidateOrder = [
            "gamut-ray",
            "assigned-pole-0",
            "assigned-pole-1",
            "assigned-pole-2",
            "centroid",
        ]
        let observationsByKey = Dictionary(grouping: selectorObservations, by: \.key)
        var selectorTable = [String: String]()
        var unselectableKeys = [String]()
        for (key, observations) in observationsByKey {
            if let selected = fixedCandidateOrder.first(where: { candidateID in
                observations.allSatisfy { observation in
                    observation.candidateMetrics[candidateID].map(
                        outlineNativeIdentityPasses
                    ) == true
                }
            }) {
                selectorTable[key] = selected
            } else {
                unselectableKeys.append(key)
            }
        }
        let selectedFailures = selectorObservations.compactMap { observation -> String? in
            guard let selected = selectorTable[observation.key],
                  let metrics = observation.candidateMetrics[selected],
                  !outlineNativeIdentityPasses(metrics)
            else { return nil }
            return "\(observation.label) target=\(selected) \(metrics)"
        }
        let selectorDigestInput = selectorTable.keys.sorted().map { key in
            "\(key)=\(selectorTable[key]!)"
        }.joined(separator: "\n")
        let selectorDigest = sha256Hex(Data(selectorDigestInput.utf8))
        let unselectableSummary = unselectableKeys.sorted().flatMap { key in
            ["key=\(key)"] + (observationsByKey[key] ?? []).sorted {
                $0.label < $1.label
            }.map { observation in
                let candidates = fixedCandidateOrder.compactMap { candidateID in
                    observation.candidateMetrics[candidateID].map {
                        "\(candidateID)={\($0)}"
                    }
                }.joined(separator: "; ")
                return "  \(observation.label): \(candidates)"
            }
        }.joined(separator: "\n")

        #expect(geometricObservationCount == 72, Comment(rawValue:
            "expected all native full/tile outline observations, got "
                + "\(geometricObservationCount)"
        ))
        #expect(eligibleObservationCount == 68,
            "expected 68 physically attainable observations, got \(eligibleObservationCount)")
        #expect(physicalOcclusions.count == 4)
        #expect(physicalOcclusions.map(\.label) == [
            "c1/light/1BE8/full",
            "c1/lowContrast/1BE8/full",
            "c2/lowContrast/1BE8/full",
            "c3/lowContrast/1BE8/full",
        ])
        #expect(unselectableKeys.isEmpty, Comment(rawValue:
            "selector oracle has no passing target:\n\(unselectableSummary)"
        ))
        #expect(selectorTable.count == observationsByKey.count)
        #expect(!selectorDigest.isEmpty)
        #expect(!worstPoleMutationWitnesses.isEmpty, Comment(rawValue:
            "expected at least one attainable residual to fail with its worst assigned pole"
        ))
        #expect(selectedFailures.isEmpty, Comment(rawValue:
            "native outline selector failures=\(selectedFailures.count) "
                + "eligible=\(eligibleObservationCount)/\(geometricObservationCount)\n"
                + selectedFailures.joined(separator: "\n")
                + "\nselector=\(selectorTable.sorted { $0.key < $1.key })"
        ))
    }

    @Test("ruling 19 positive-mean support and waived coverage close layout 11")
    func ruling19PositiveMeanSupportCoverageOracle() throws {
        let controlSide = 129
        let controlCenter = Double(controlSide) * 0.5
        let controlRadius = 54.0
        let empty = outlineNativeControl(side: controlSide) { _, _ in 0 }
        let controls: [(String, PixelImage, Bool)] = [
            (
                "thin-open-contour",
                outlineNativeControl(side: controlSide) { radius, _ in
                    (0.78...0.84).contains(radius) ? 1 : 0
                },
                true
            ),
            (
                "filled-torus",
                outlineNativeControl(side: controlSide) { radius, _ in
                    (0.30...1.02).contains(radius) ? 1 : 0
                },
                false
            ),
            (
                "ripple-filled-disc",
                outlineNativeControl(side: controlSide) { radius, _ in
                    [0.18, 0.34, 0.50, 0.66, 0.82, 0.98].contains {
                        abs(radius - $0) <= 0.035
                    } ? 1 : 0
                },
                false
            ),
            ("vanished-contour", empty, false),
            (
                "broken-arc",
                outlineNativeControl(side: controlSide) { radius, angle in
                    (0.78...0.84).contains(radius)
                        && abs(angle) > Double.pi * 0.30 ? 1 : 0
                },
                false
            ),
            (
                "filled-counterform",
                outlineNativeControl(side: controlSide) { radius, _ in
                    radius <= 0.34 ? 1 : 0
                },
                false
            ),
        ]
        for (label, image, expectedPass) in controls {
            let metrics = outlineNativeIdentityMetrics(
                image,
                reference: empty,
                centerX: controlCenter,
                centerY: controlCenter,
                pixelRadius: controlRadius
            )
            #expect(
                outlineNativeIdentityPasses(metrics, minimumAngularCoverage: 0.77)
                    == expectedPass,
                Comment(rawValue: "r19 synthetic \(label) \(metrics)")
            )
        }

        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == 11
        }?.recipe)
        let orderedActors = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }
        let candidateOrder = [
            "gamut-ray",
            "assigned-pole-0",
            "assigned-pole-1",
            "assigned-pole-2",
            "centroid",
        ]
        let backgrounds: [BackgroundCondition] = [.light, .dark, .lowContrast]
        let tileCrop = PixelRect(x: 0, y: 229, width: 393, height: 393)
        var observations = [OutlineSelectorObservation]()
        var geometricCount = 0
        var attainableCount = 0
        var occlusions = [String]()
        var peakGeometricCount = 0
        var peakAttainableCount = 0
        var peakOcclusions = [String]()
        var peakProductionWitness: OutlineNativeIdentityMetrics?
        var supportStability = [String: Set<String>]()
        var targetStability = [String: Set<String>]()
        var authorityDigests = [String: String]()
        var radialFailures = [String]()
        var radialFlatMutationFailures = [String]()
        var radialObservable = [String: OutlineR19RadialColorMetrics]()
        var radialUnobservable = [String: OutlineR19RadialColorMetrics]()
        var radialAuthoredFallbacks = [String: OutlineR19RadialColorMetrics]()

        for background in backgrounds {
            var scenes = [OutlineR19OracleScene]()
            for colorCount in 1...3 {
                let material = MaterialDNA.fixture(
                    daySeed: layout.seed,
                    eventIDs: layout.eventIDs,
                    family: .outline,
                    requestedColorCount: colorCount
                )
                let capture = MaterialRawSceneCapture()
                let instrumentation = MaterialRenderInstrumentation()
                let rendered = try MaterialRenderer().render(
                    recipe: recipe,
                    material: material,
                    background: background,
                    configuration: .init(
                        scale: 2,
                        outlineVisibilityPlacement: .none,
                        instrumentation: instrumentation,
                        rawSceneCapture: capture,
                        presentationEvidenceRequest: .none,
                        presentationScale: 1
                    )
                )
                #expect(rendered.drawSequence == orderedActors.map(\.eventID))
                try #require(capture.actorLayers.count == orderedActors.count)
                #expect(instrumentation.actorRemovedFullSceneRenders == 0)
                #expect(instrumentation.counterfactualCompositePasses == 0)
                #expect(instrumentation.isolatedPresentationComposites == 0)
                #expect(instrumentation.capturedActorLayerBuilds == orderedActors.count)
                let authorities = try capture.actorLayers.map { layer in
                    try outlineR19PlacedAndDownsampled(
                        layer.image,
                        drawRect: layer.drawRect,
                        sourceWidth: 786,
                        sourceHeight: 1_704,
                        outputWidth: 393,
                        outputHeight: 852
                    )
                }
                let supports = try capture.actorLayers.map { layer in
                    try outlineR19PlacedAndDownsampled(
                        layer.presentationSupport,
                        drawRect: layer.presentationSupportDrawRect,
                        sourceWidth: 786,
                        sourceHeight: 1_704,
                        outputWidth: 393,
                        outputHeight: 852
                    )
                }
                for actorIndex in orderedActors.indices {
                    let actorMaterial = try #require(
                        material.actor(orderedActors[actorIndex].eventID)
                    )
                    #expect(
                        capture.actorLayers[actorIndex].presentationColors
                            == actorMaterial.colors
                    )
                    authorityDigests[
                        "c\(colorCount)|\(orderedActors[actorIndex].eventID)|"
                            + background.rawValue
                    ] = sha256Hex(outlineR19AlphaBytes(authorities[actorIndex]))
                }
                scenes.append(OutlineR19OracleScene(
                    colorCount: colorCount,
                    material: material,
                    base: try outlineR19Resized(
                        capture.actorLayers[0].presentedUnderlay,
                        width: 393,
                        height: 852
                    ),
                    authorities: authorities,
                    supports: supports,
                    authoredSupports: try capture.actorLayers.map { layer in
                        try outlineR19Resized(
                            layer.presentationSupport,
                            width: layer.presentationSupport.width,
                            height: layer.presentationSupport.height
                        )
                    }
                ))
            }

            var positiveMeanPrefixes = scenes.map(\.base)
            var peakPrefixes = scenes.map(\.base)
            for actorIndex in orderedActors.indices {
                let actor = orderedActors[actorIndex]
                var candidatesByScene = [OutlineR19Candidates]()
                var peakCandidatesByScene = [OutlineR19Candidates]()
                var actorObservations = [OutlineSelectorObservation]()
                for sceneIndex in scenes.indices {
                    let scene = scenes[sceneIndex]
                    let actorMaterial = try #require(scene.material.actor(actor.eventID))
                    let positiveMean = outlineR19PositiveMeanCandidates(
                        authority: scene.authorities[actorIndex],
                        support: scene.supports[actorIndex],
                        prefix: positiveMeanPrefixes[sceneIndex],
                        laterAuthorities: scene.authorities.dropFirst(actorIndex + 1),
                        colors: actorMaterial.colors
                    )
                    let peak = outlineR19PositiveMeanCandidates(
                        authority: scene.authorities[actorIndex],
                        support: scene.supports[actorIndex],
                        prefix: peakPrefixes[sceneIndex],
                        laterAuthorities: scene.authorities.dropFirst(actorIndex + 1),
                        colors: actorMaterial.colors
                    )
                    candidatesByScene.append(positiveMean)
                    peakCandidatesByScene.append(peak)
                    let stabilityKey = "c\(scene.colorCount)|\(actor.eventID)|"
                        + background.rawValue
                    supportStability[stabilityKey, default: []].insert(
                        positiveMean.supportDigest
                    )
                    for (candidateID, targetID) in positiveMean.targetIDs {
                        for _ in ["full", "tile"] {
                            for _ in [1, 3] {
                                targetStability[
                                    "candidate|\(stabilityKey)|\(candidateID)", default: []
                                ].insert(targetID)
                            }
                        }
                    }

                    let transparent = PixelImage(
                        width: 393,
                        height: 852,
                        rgba: Data(repeating: 0, count: 393 * 852 * 4)
                    )
                    var suffix = transparent
                    for laterIndex in scene.authorities.indices.reversed()
                        where laterIndex > actorIndex {
                        suffix = outlineSourceOver(
                            source: suffix,
                            underlay: outlineR19AlphaOnly(scene.authorities[laterIndex])
                        )
                    }
                    let positiveMeanReference = outlineSourceOver(
                        source: suffix,
                        underlay: positiveMeanPrefixes[sceneIndex]
                    )
                    let peakReference = outlineSourceOver(
                        source: suffix,
                        underlay: peakPrefixes[sceneIndex]
                    )
                    var effectiveLabels = Data(repeating: 255, count: 393 * 852)
                    for pixelIndex in 0..<(393 * 852) {
                        let offset = pixelIndex * 4 + 3
                        var effectiveAlpha = Double(
                            scene.authorities[actorIndex].rgba[offset]
                        ) / 255
                        for laterIndex in scene.authorities.indices
                            where laterIndex > actorIndex {
                            effectiveAlpha *= 1 - Double(
                                scene.authorities[laterIndex].rgba[offset]
                            ) / 255
                        }
                        if effectiveAlpha > 0 {
                            effectiveLabels[pixelIndex] = UInt8(actorIndex)
                        }
                    }
                    let centerX = actor.position.x * 393
                    let fullCenterY = actor.position.y * 852
                    let pixelRadius = actor.diameter * 393 * 0.5
                    let views: [(String, Double, PixelRect?)] = [
                        ("full", fullCenterY, nil),
                        ("tile", fullCenterY - Double(tileCrop.y), tileCrop),
                    ]
                    for (viewName, centerY, crop) in views {
                        let width = crop?.width ?? 393
                        let height = crop?.height ?? 852
                        guard outlineNativeActorIsEligible(
                            actor,
                            centerX: centerX,
                            centerY: centerY,
                            width: width,
                            height: height
                        ) else { continue }
                        geometricCount += 1
                        peakGeometricCount += 1
                        let labels = crop.map {
                            fixture11CroppedBytes(
                                effectiveLabels,
                                sourceWidth: 393,
                                crop: $0,
                                bytesPerPixel: 1
                            )
                        } ?? effectiveLabels
                        let positiveMeanReferenceView = crop.map {
                            positiveMeanReference.cropped(
                                x: $0.x, y: $0.y, width: $0.width, height: $0.height
                            )
                        } ?? positiveMeanReference
                        let peakReferenceView = crop.map {
                            peakReference.cropped(
                                x: $0.x, y: $0.y, width: $0.width, height: $0.height
                            )
                        } ?? peakReference

                        func metrics(
                            layers: [String: PixelImage],
                            prefix: PixelImage,
                            reference: PixelImage
                        ) -> [String: OutlineNativeIdentityMetrics] {
                            Dictionary(uniqueKeysWithValues: layers.map {
                                candidateID, layer in
                                let candidatePrefix = outlineSourceOver(
                                    source: layer,
                                    underlay: prefix
                                )
                                let candidateFull = outlineSourceOver(
                                    source: suffix,
                                    underlay: candidatePrefix
                                )
                                let candidate = crop.map {
                                    candidateFull.cropped(
                                        x: $0.x,
                                        y: $0.y,
                                        width: $0.width,
                                        height: $0.height
                                    )
                                } ?? candidateFull
                                return (
                                    candidateID,
                                    outlineNativeIdentityMetrics(
                                        candidate,
                                        reference: reference,
                                        centerX: centerX,
                                        centerY: centerY,
                                        pixelRadius: pixelRadius,
                                        ownerIndex: UInt8(actorIndex),
                                        ownerLabels: labels
                                    )
                                )
                            })
                        }
                        let positiveMeanMetrics = metrics(
                            layers: positiveMean.layers,
                            prefix: positiveMeanPrefixes[sceneIndex],
                            reference: positiveMeanReferenceView
                        )
                        let peakMetrics = metrics(
                            layers: peak.peakLayers,
                            prefix: peakPrefixes[sceneIndex],
                            reference: peakReferenceView
                        )
                        let label = "c\(scene.colorCount)/\(background.rawValue)/"
                            + "\(actor.eventID.prefix(4))/\(viewName)"
                        let positiveMeanCeiling = positiveMeanMetrics.values
                            .map(\.peakContrast).max() ?? 0
                        if positiveMeanCeiling >= 0.070 {
                            attainableCount += 1
                            let observation = OutlineSelectorObservation(
                                label: label,
                                key: "\(actor.eventID)|\(background.rawValue)",
                                candidateMetrics: positiveMeanMetrics
                            )
                            observations.append(observation)
                            actorObservations.append(observation)
                        } else {
                            occlusions.append(label)
                        }
                        let peakCeiling = peakMetrics.values.map(\.peakContrast).max() ?? 0
                        if peakCeiling >= 0.070 {
                            peakAttainableCount += 1
                        } else {
                            peakOcclusions.append(label)
                        }
                        if label == "c2/light/1BE8/full" {
                            peakProductionWitness = peakMetrics["gamut-ray"]
                        }

                        let authorityAlpha = outlineR19AlphaBytes(
                            scene.authorities[actorIndex]
                        )
                        for layer in positiveMean.layers.values {
                            #expect(outlineR19AlphaBytes(layer) == authorityAlpha)
                            #expect((0..<(layer.width * layer.height)).allSatisfy {
                                pixelIndex in
                                let offset = pixelIndex * 4
                                return authorityAlpha[pixelIndex] > 0
                                    || (layer.rgba[offset] == 0
                                        && layer.rgba[offset + 1] == 0
                                        && layer.rgba[offset + 2] == 0
                                        && layer.rgba[offset + 3] == 0)
                            })
                        }
                        if let crop {
                            let cropped = fixture11CroppedBytes(
                                authorityAlpha,
                                sourceWidth: 393,
                                crop: crop,
                                bytesPerPixel: 1
                            )
                            #expect(cropped == outlineR19AlphaBytes(
                                scene.authorities[actorIndex].cropped(
                                    x: crop.x,
                                    y: crop.y,
                                    width: crop.width,
                                    height: crop.height
                                )
                            ))
                        }
                    }
                }

                let actorKey = "\(actor.eventID)|\(background.rawValue)"
                let selected = candidateOrder.first { candidateID in
                    actorObservations.allSatisfy {
                        $0.candidateMetrics[candidateID].map {
                            outlineNativeIdentityPasses(
                                $0,
                                minimumAngularCoverage: 0.77
                            )
                        } == true
                    }
                } ?? "gamut-ray"
                for sceneIndex in scenes.indices {
                    let actorMaterial = try #require(
                        scenes[sceneIndex].material.actor(actor.eventID)
                    )
                    positiveMeanPrefixes[sceneIndex] = outlineSourceOver(
                        source: candidatesByScene[sceneIndex].layers[selected]
                            ?? candidatesByScene[sceneIndex].layers["gamut-ray"]!,
                        underlay: positiveMeanPrefixes[sceneIndex]
                    )
                    peakPrefixes[sceneIndex] = outlineSourceOver(
                        source: peakCandidatesByScene[sceneIndex].peakLayers["gamut-ray"]!,
                        underlay: peakPrefixes[sceneIndex]
                    )
                    let stabilityKey = "c\(scenes[sceneIndex].colorCount)|\(actorKey)"
                    for _ in ["full", "tile"] {
                        for _ in [1, 3] {
                            targetStability[
                                "selected|\(stabilityKey)", default: []
                            ].insert(candidatesByScene[sceneIndex].targetIDs[selected]!)
                        }
                    }
                    if scenes[sceneIndex].colorCount >= 2 {
                        let radialLabel = "c\(scenes[sceneIndex].colorCount)/\(actorKey)"
                        let selectedLayer = candidatesByScene[sceneIndex].layers[selected]!
                        let radial = outlineR19RadialColorMetrics(
                            layer: selectedLayer,
                            authority: scenes[sceneIndex].authorities[actorIndex],
                            centerX: actor.position.x * 393,
                            centerY: actor.position.y * 852,
                            pixelRadius: actor.diameter * 393 * 0.5
                        )
                        if radial.isObservable {
                            radialObservable[radialLabel] = radial
                            if !radial.varies {
                                radialFailures.append("\(radialLabel) \(radial)")
                            }
                            let flat = outlineR20FlatTargetLayer(
                                authority: scenes[sceneIndex].authorities[actorIndex],
                                color: actorMaterial.colors[0]
                            )
                            let flatMetrics = outlineR19RadialColorMetrics(
                                layer: flat,
                                authority: scenes[sceneIndex].authorities[actorIndex],
                                centerX: actor.position.x * 393,
                                centerY: actor.position.y * 852,
                                pixelRadius: actor.diameter * 393 * 0.5
                            )
                            if !flatMetrics.isObservable || flatMetrics.varies {
                                radialFlatMutationFailures.append(
                                    "\(radialLabel) flat=\(flatMetrics)"
                                )
                            }
                        } else {
                            radialUnobservable[radialLabel] = radial
                            let authoredSupport = scenes[sceneIndex]
                                .authoredSupports[actorIndex]
                            let authored = outlineR19RadialColorMetrics(
                                layer: authoredSupport,
                                authority: authoredSupport,
                                centerX: Double(authoredSupport.width) * 0.5,
                                centerY: Double(authoredSupport.height) * 0.5,
                                pixelRadius: Double(min(
                                    authoredSupport.width,
                                    authoredSupport.height
                                )) * 0.5
                            )
                            radialAuthoredFallbacks[radialLabel] = authored
                            if !outlineR20AuthoredRadialFieldPasses(
                                actorMaterial,
                                metrics: authored
                            ) {
                                radialFailures.append(
                                    "\(radialLabel) radial-unobservable; authored=\(authored)"
                                )
                            }
                            let flatAuthored = outlineR20FlatTargetLayer(
                                authority: authoredSupport,
                                color: actorMaterial.colors[0]
                            )
                            let flatAuthoredMetrics = outlineR19RadialColorMetrics(
                                layer: flatAuthored,
                                authority: authoredSupport,
                                centerX: Double(authoredSupport.width) * 0.5,
                                centerY: Double(authoredSupport.height) * 0.5,
                                pixelRadius: Double(min(
                                    authoredSupport.width,
                                    authoredSupport.height
                                )) * 0.5
                            )
                            if !flatAuthoredMetrics.isObservable
                                || flatAuthoredMetrics.varies {
                                radialFlatMutationFailures.append(
                                    "\(radialLabel) authored-flat=\(flatAuthoredMetrics)"
                                )
                            }
                        }
                    }
                }
            }
        }

        let observationsByKey = Dictionary(grouping: observations, by: \.key)
        var selectorTable = [String: String]()
        var oldThresholdUnresolved = [String]()
        for (key, keyObservations) in observationsByKey {
            if let selected = candidateOrder.first(where: { candidateID in
                keyObservations.allSatisfy {
                    $0.candidateMetrics[candidateID].map {
                        outlineNativeIdentityPasses($0, minimumAngularCoverage: 0.77)
                    } == true
                }
            }) {
                selectorTable[key] = selected
            }
            if !candidateOrder.contains(where: { candidateID in
                keyObservations.allSatisfy {
                    $0.candidateMetrics[candidateID].map {
                        outlineNativeIdentityPasses($0, minimumAngularCoverage: 0.82)
                    } == true
                }
            }) {
                oldThresholdUnresolved.append(key)
            }
        }
        let selectedFailures = observations.filter { observation in
            guard let selected = selectorTable[observation.key],
                  let metrics = observation.candidateMetrics[selected]
            else { return true }
            return !outlineNativeIdentityPasses(
                metrics,
                minimumAngularCoverage: 0.77
            )
        }
        let selectorDigestInput = selectorTable.keys.sorted().map {
            "\($0)=\(selectorTable[$0]!)"
        }.joined(separator: "\n")
        let selectorDigest = sha256Hex(Data(selectorDigestInput.utf8))
        let peakWitness = try #require(peakProductionWitness)
        let supportStabilityFailures = supportStability.filter { $0.value.count != 1 }
        let targetStabilityFailures = targetStability.filter { $0.value.count != 1 }

        print("ruling19 ledger geometric=\(geometricCount) attainable="
            + "\(attainableCount) occluded=\(occlusions.count) keys="
            + "\(selectorTable.count)/\(observationsByKey.count) pass="
            + "\(observations.count - selectedFailures.count)/\(observations.count)")
        print("ruling19 selector=\(selectorTable.sorted { $0.key < $1.key })")
        print("ruling19 selectorDigest=\(selectorDigest)")
        print("ruling19 peakMutation geometric=\(peakGeometricCount) attainable="
            + "\(peakAttainableCount) occluded=\(peakOcclusions.count) "
            + "c2/light/1BE8/full={\(peakWitness)}")
        print("ruling19 radial observable=\(radialObservable.count) "
            + "unobservable=\(radialUnobservable.keys.sorted()) "
            + "authoredFallbacks=\(radialAuthoredFallbacks.count)")

        #expect(geometricCount == 72)
        #expect(attainableCount == 68)
        #expect(occlusions == [
            "c1/light/1BE8/full",
            "c1/lowContrast/1BE8/full",
            "c2/lowContrast/1BE8/full",
            "c3/lowContrast/1BE8/full",
        ])
        #expect(selectorTable.count == 14)
        #expect(selectorTable.values.allSatisfy { $0 == "gamut-ray" })
        #expect(selectedFailures.isEmpty, Comment(rawValue:
            "r19 selected failures=\(selectedFailures.map(\.label))"
        ))
        #expect(observations.count == 68)
        #expect(oldThresholdUnresolved == [
            "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02|light"
        ])
        #expect(peakGeometricCount == 72)
        #expect(peakAttainableCount == 67)
        #expect(peakOcclusions.count == 5)
        #expect(abs(peakWitness.angularCoverage - 0.6875) < 0.000_001)
        #expect(!outlineNativeIdentityPasses(
            peakWitness,
            minimumAngularCoverage: 0.77
        ))
        #expect(supportStabilityFailures.isEmpty)
        #expect(targetStabilityFailures.isEmpty)
        #expect(!authorityDigests.isEmpty)
        #expect(radialObservable.count + radialUnobservable.count
            == backgrounds.count * 2 * orderedActors.count)
        #expect(radialAuthoredFallbacks.count == radialUnobservable.count)
        #expect(radialUnobservable.keys.allSatisfy {
            radialAuthoredFallbacks[$0]?.passes == true
        })
        #expect(radialObservable.contains { label, metrics in
            label.contains("1BE8C246") && metrics.sampleCount == 23 && metrics.varies
        })
        #expect(radialFailures.isEmpty, Comment(rawValue:
            "r19 c2/c3 radial failures=\(radialFailures)"
        ))
        #expect(radialFlatMutationFailures.isEmpty, Comment(rawValue:
            "r19 flat-target mutation failures=\(radialFlatMutationFailures)"
        ))
        #expect(!selectorDigest.isEmpty)
    }

    @Test("ruling 20 radial harness separates 60D3 unobservable support from 1BE8 variability")
    func ruling20RadialHarnessSeparatesAvailabilityFromVariability() throws {
        let oneBE8 = outlineR20RadialFixture(availableRayCount: 23, flat: false)
        let oneBE8Metrics = outlineR19RadialColorMetrics(
            layer: oneBE8.layer,
            authority: oneBE8.authority,
            centerX: oneBE8.center,
            centerY: oneBE8.center,
            pixelRadius: oneBE8.radius
        )
        #expect(oneBE8Metrics.sampleCount == 23)
        #expect(oneBE8Metrics.isObservable)
        #expect(oneBE8Metrics.varies)

        let oneBE8Flat = outlineR20FlatTargetLayer(
            authority: oneBE8.authority,
            color: .init(red: 0.92, green: 0.08, blue: 0.16)
        )
        let oneBE8FlatMetrics = outlineR19RadialColorMetrics(
            layer: oneBE8Flat,
            authority: oneBE8.authority,
            centerX: oneBE8.center,
            centerY: oneBE8.center,
            pixelRadius: oneBE8.radius
        )
        #expect(oneBE8FlatMetrics.isObservable)
        #expect(!oneBE8FlatMetrics.varies)

        let sixtyD3 = outlineR20RadialFixture(availableRayCount: 0, flat: false)
        let sixtyD3Metrics = outlineR19RadialColorMetrics(
            layer: sixtyD3.layer,
            authority: sixtyD3.authority,
            centerX: sixtyD3.center,
            centerY: sixtyD3.center,
            pixelRadius: sixtyD3.radius
        )
        #expect(!sixtyD3Metrics.isObservable)
        #expect(!sixtyD3Metrics.varies)

        let authored = outlineR20RadialFixture(availableRayCount: 96, flat: false)
        let authoredMetrics = outlineR19RadialColorMetrics(
            layer: authored.layer,
            authority: authored.authority,
            centerX: authored.center,
            centerY: authored.center,
            pixelRadius: authored.radius
        )
        let compositionAuthority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: compositionAuthority.recipes
        )
        let layout = CorpusManifest.visibleV1().breadth[11]
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == 11
        }?.recipe)
        let orderedActors = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }
        let focusEventIDs = [
            "60D319B7-3E21-4E8A-879F-5C6B24FA0A07",
            "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02",
        ]
        for eventID in [
            "60D319B7-3E21-4E8A-879F-5C6B24FA0A07",
            "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02",
        ] {
            for colorCount in 2...3 {
                let material = try #require(MaterialDNA.fixture(
                    daySeed: layout.seed,
                    eventIDs: layout.eventIDs,
                    family: .outline,
                    requestedColorCount: colorCount
                ).actor(eventID))
                #expect(outlineR20AuthoredRadialFieldPasses(
                    material,
                    metrics: authoredMetrics
                ))
            }
        }
        for colorCount in 2...3 {
            let dailyMaterial = MaterialDNA.fixture(
                daySeed: layout.seed,
                eventIDs: layout.eventIDs,
                family: .outline,
                requestedColorCount: colorCount
            )
            let capture = MaterialRawSceneCapture()
            _ = try MaterialRenderer().render(
                recipe: recipe,
                material: dailyMaterial,
                background: .light,
                configuration: .init(
                    scale: 2,
                    outlineVisibilityPlacement: .none,
                    rawSceneCapture: capture,
                    presentationEvidenceRequest: .none,
                    presentationScale: 1
                )
            )
            #expect(capture.actorLayers.count == orderedActors.count)
            for eventID in focusEventIDs {
                let actorIndex = try #require(orderedActors.firstIndex {
                    $0.eventID == eventID
                })
                let material = try #require(dailyMaterial.actor(eventID))
                let supportImage = capture.actorLayers[actorIndex].presentationSupport
                let support = try outlineR19Resized(
                    supportImage,
                    width: supportImage.width,
                    height: supportImage.height
                )
                let metrics = outlineR19RadialColorMetrics(
                    layer: support,
                    authority: support,
                    centerX: Double(support.width) * 0.5,
                    centerY: Double(support.height) * 0.5,
                    pixelRadius: Double(min(support.width, support.height)) * 0.5
                )
                #expect(
                    outlineR20AuthoredRadialFieldPasses(material, metrics: metrics),
                    Comment(rawValue: "c\(colorCount)/\(eventID.prefix(4)) authored \(metrics)")
                )
                let flat = outlineR20FlatTargetLayer(
                    authority: support,
                    color: material.colors[0]
                )
                let flatMetrics = outlineR19RadialColorMetrics(
                    layer: flat,
                    authority: support,
                    centerX: Double(support.width) * 0.5,
                    centerY: Double(support.height) * 0.5,
                    pixelRadius: Double(min(support.width, support.height)) * 0.5
                )
                #expect(flatMetrics.isObservable)
                #expect(!flatMetrics.varies)
            }
        }
    }

    @Test("production outline projection matches the accepted R19 positive-mean construction")
    func productionOutlineProjectionMatchesAcceptedR19Construction() throws {
        let authority = try canonicalCompositionAuthority()
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: authority.recipes
        )
        let manifest = CorpusManifest.visibleV1()
        let layout = manifest.breadth[11]
        let recipe = try #require(archive.fixtures.first {
            $0.fixtureIndex == 11
        }?.recipe)
        let orderedActors = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }
        let material = MaterialDNA.fixture(
            daySeed: layout.seed,
            eventIDs: layout.eventIDs,
            family: .outline,
            requestedColorCount: 2
        )
        let sourceCapture = MaterialRawSceneCapture()
        let sourceInstrumentation = MaterialRenderInstrumentation()
        let source = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .light,
            configuration: .init(
                scale: 2,
                outlineVisibilityPlacement: .none,
                instrumentation: sourceInstrumentation,
                rawSceneCapture: sourceCapture,
                presentationScale: 1
            )
        )
        let productionInstrumentation = MaterialRenderInstrumentation()
        let production = try MaterialRenderer().render(
            recipe: recipe,
            material: material,
            background: .light,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                instrumentation: productionInstrumentation,
                presentationEvidenceRequest: .perActor
            )
        )
        let evidence = try #require(production.presentationEvidence)

        #expect(source.drawSequence == orderedActors.map(\.eventID))
        #expect(production.drawSequence == source.drawSequence)
        try #require(sourceCapture.actorLayers.count == orderedActors.count)
        try #require(productionInstrumentation.projectedActorLayers.count == orderedActors.count)
        try #require(
            productionInstrumentation.outlineVisibilityPalettePoleLayers.count
                == orderedActors.count
        )
        try #require(
            productionInstrumentation.outlineVisibilitySelectedPaletteIndices.count
                == orderedActors.count
        )
        try #require(
            productionInstrumentation.preProjectionAuthorityAlphaPlanes.count
                == orderedActors.count
        )
        #expect(productionInstrumentation.canonicalRawSceneRenders == 1)
        #expect(productionInstrumentation.capturedActorLayerBuilds == orderedActors.count)
        #expect(productionInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(productionInstrumentation.counterfactualCompositePasses == 0)
        #expect(productionInstrumentation.isolatedPresentationComposites == 0)

        let authorities = try sourceCapture.actorLayers.map { layer in
            try outlineR19PlacedAndDownsampled(
                layer.image,
                drawRect: layer.drawRect,
                sourceWidth: 786,
                sourceHeight: 1_704,
                outputWidth: 393,
                outputHeight: 852
            )
        }
        let supports = try sourceCapture.actorLayers.map { layer in
            try outlineR19PlacedAndDownsampled(
                layer.presentationSupport,
                drawRect: layer.presentationSupportDrawRect,
                sourceWidth: 786,
                sourceHeight: 1_704,
                outputWidth: 393,
                outputHeight: 852
            )
        }
        var expectedPrefix = try outlineR19Resized(
            sourceCapture.actorLayers[0].presentedUnderlay,
            width: 393,
            height: 852
        )

        for actorIndex in orderedActors.indices {
            let actor = orderedActors[actorIndex]
            let actorMaterial = try #require(material.actor(actor.eventID))
            let expected = outlineR19PositiveMeanCandidates(
                authority: authorities[actorIndex],
                support: supports[actorIndex],
                prefix: expectedPrefix,
                laterAuthorities: authorities.dropFirst(actorIndex + 1),
                colors: actorMaterial.colors
            )
            let productionPoles = try productionInstrumentation
                .outlineVisibilityPalettePoleLayers[actorIndex].map { image in
                    PixelImage(
                        width: image.width,
                        height: image.height,
                        rgba: try rgbaBytes(image)
                    )
                }
            let productionLayer = try PixelImage(
                width: productionInstrumentation.projectedActorLayers[actorIndex].width,
                height: productionInstrumentation.projectedActorLayers[actorIndex].height,
                rgba: rgbaBytes(productionInstrumentation.projectedActorLayers[actorIndex])
            )
            let expectedLayer = expected.positiveMeanGamutPoleLayers[
                expected.positiveMeanGamutIndex
            ]
            let actorEvidence = try #require(evidence.actors.first {
                $0.eventID == actor.eventID
            })

            #expect(productionPoles.map(\.rgba)
                == expected.positiveMeanGamutPoleLayers.map(\.rgba))
            #expect(
                productionInstrumentation.outlineVisibilitySelectedPaletteIndices[actorIndex]
                    == expected.positiveMeanGamutIndex
            )
            #expect(productionLayer.rgba == expectedLayer.rgba)
            #expect(
                productionInstrumentation.preProjectionAuthorityAlphaPlanes[actorIndex]
                    == outlineR19AlphaBytes(authorities[actorIndex])
            )
            #expect(try pixels(actorEvidence.projected.fullScreen.pngData) == productionLayer)
            #expect(actorEvidence.projected.drawSequence == [actor.eventID])
            #expect(actorEvidence.removed.drawSequence
                == Array(production.drawSequence.prefix(actorIndex)))
            #expect(actorEvidence.isolated.ownership.ownerEventIDs == production.drawSequence)
            #expect(try pixels(actorEvidence.projected.calendarTile.pngData)
                == productionLayer.cropped(
                    x: production.tileCrop.x,
                    y: production.tileCrop.y,
                    width: production.tileCrop.width,
                    height: production.tileCrop.height
                ))

            expectedPrefix = outlineSourceOver(source: expectedLayer, underlay: expectedPrefix)
        }

        let productionFull = try pixels(production.fullScreen.pngData)
        #expect(productionFull.rgba == expectedPrefix.rgba)
        #expect(try pixels(production.calendarTile.pngData)
            == productionFull.cropped(
                x: production.tileCrop.x,
                y: production.tileCrop.y,
                width: production.tileCrop.width,
                height: production.tileCrop.height
            ))
        #expect(sourceInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(sourceInstrumentation.counterfactualCompositePasses == 0)
        #expect(sourceInstrumentation.isolatedPresentationComposites == 0)
        #expect(sourceInstrumentation.capturedActorLayerBuilds == orderedActors.count)
    }

    @Test("halo split presentation preserves aura alpha and final-pixel compact softness")
    func haloSplitPresentationControlsAreObservable() {
        let background = MaterialRenderer.backgroundColor(for: .light)
        let alphaFixture = (0...255).map { value in
            let alpha = UInt8(value)
            return OutlineVisibilityPixel(
                red: UInt8((Double(alpha) * 0.154_907_887_5).rounded()),
                green: UInt8((Double(alpha) * 0.934_679_486_5).rounded()),
                blue: UInt8((Double(alpha) * 0.701_692_491_7).rounded()),
                alpha: alpha
            )
        }
        let masks = alphaFixture.indices.map { index in
            Double(index) / Double(max(alphaFixture.count - 1, 1))
        }
        let single = haloCompactProjectionWitness(
            alphaFixture,
            masks: masks,
            background: background
        )
        let double = haloCompactProjectionWitness(
            single,
            masks: masks,
            background: background
        )
        let originalAlpha = alphaFixture.map(\.alpha)
        let singleAlpha = single.map(\.alpha)

        #expect(originalAlpha == singleAlpha)
        #expect(fixture11AlphaHistogram(originalAlpha) == fixture11AlphaHistogram(singleAlpha))
        #expect(fixture11AlphaQuantiles(originalAlpha) == fixture11AlphaQuantiles(singleAlpha))
        #expect(zip(alphaFixture, single).contains { lhs, rhs in
            lhs.red != rhs.red || lhs.green != rhs.green || lhs.blue != rhs.blue
        })
        #expect(haloCompactProjectionMatchesOneApplication(
            original: alphaFixture,
            candidate: single,
            masks: masks,
            background: background
        ))
        #expect(!haloCompactProjectionMatchesOneApplication(
            original: alphaFixture,
            candidate: double,
            masks: masks,
            background: background
        ))

        let finalPixelSide = 12
        let directProfile = haloCompactMaskBytes(
            side: finalPixelSide,
            presentationPixelSide: finalPixelSide,
            innerRadius: 0.10
        )
        let scale1Supersampled2Profile = haloCompactMaskBytes(
            side: finalPixelSide,
            presentationPixelSide: finalPixelSide,
            innerRadius: 0.10
        )
        let sourceScaleMutation = haloCompactMaskBytes(
            side: finalPixelSide,
            presentationPixelSide: finalPixelSide * 2,
            innerRadius: 0.10
        )
        #expect(directProfile == scale1Supersampled2Profile)
        #expect(zip(directProfile, scale1Supersampled2Profile).allSatisfy {
            abs(Int($0) - Int($1)) <= 1
        })
        #expect(directProfile.filter { $0 > 0 }.count ==
            scale1Supersampled2Profile.filter { $0 > 0 }.count)
        #expect(sourceScaleMutation != directProfile)
    }
}

private struct OutlineNativeIdentityMetrics: CustomStringConvertible {
    let peakContrast: Double
    let centerToPeakRatio: Double
    let percentile90ContourThickness: Double
    let activeRadialDensity: Double
    let radialBandCount: Int
    let angularCoverage: Double
    let observableRayCount: Int

    var description: String {
        "peak=\(peakContrast), centerRatio=\(centerToPeakRatio), "
            + "p90Thickness=\(percentile90ContourThickness), density=\(activeRadialDensity), "
            + "bands=\(radialBandCount), angularCoverage=\(angularCoverage), "
            + "observableRays=\(observableRayCount)"
    }
}

private struct OutlineSelectorObservation {
    let label: String
    let key: String
    let candidateMetrics: [String: OutlineNativeIdentityMetrics]
}

#if false // Rejected R13/R15/R16 read-only oracle scaffolding; never ship or execute.
private struct OutlineOfflineOracleScene {
    let colorCount: Int
    let material: DailyMaterialDNA
    let base: PixelImage
    let authorities: [PixelImage]
    let supports: [PixelImage]
    let tileCrop: PixelRect
}

private struct OutlineOfflineCandidates {
    let layers: [String: PixelImage]
    let meanNormalizedLayers: [String: PixelImage]
    let ceilingLayers: [String: PixelImage]
    let ceilingTargetIDs: [String: String]
    let supportDigest: String
}

private struct OutlineRuling16Observation {
    let label: String
    let colorCount: Int
    let scale: Int
    let candidateMetrics: [String: OutlineNativeIdentityMetrics]
    let ruling15Metrics: [String: OutlineNativeIdentityMetrics]
    let targetIDs: [String: String]
    let colorMetrics: [String: OutlineRadialColorMetrics]
    let candidateAlphaDigests: [String: String]
    let authorityAlphaDigest: String
}

private struct OutlineRadialColorMetrics: CustomStringConvertible {
    let sampleCount: Int
    let maximumRGBDistance: Double
    let maximumHueDistance: Double
    let maximumChromaDifference: Double
    let maximumChroma: Double

    var passes: Bool {
        sampleCount >= 24
            && maximumRGBDistance > 0.08
            && (maximumHueDistance > 0.04 || maximumChromaDifference > 0.06)
            && maximumChroma > 0.25
    }

    var description: String {
        "samples=\(sampleCount), rgb=\(maximumRGBDistance), "
            + "hue=\(maximumHueDistance), chromaDelta=\(maximumChromaDifference), "
            + "maxChroma=\(maximumChroma), passes=\(passes)"
    }
}

private func outlineOfflineResized(
    _ image: CGImage,
    width: Int,
    height: Int
) throws -> PixelImage {
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
    guard rendered else { throw MaterialRendererError.cannotCreateBitmap(width, height) }
    return PixelImage(width: width, height: height, rgba: rgba)
}

private func outlineOfflinePlacedAndDownsampled(
    _ image: CGImage,
    drawRect: CGRect,
    sourceWidth: Int,
    sourceHeight: Int,
    outputWidth: Int,
    outputHeight: Int
) throws -> PixelImage {
    let sourceContext = try #require(CGContext(
        data: nil,
        width: sourceWidth,
        height: sourceHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ))
    sourceContext.clear(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
    sourceContext.draw(image, in: drawRect)
    return try outlineOfflineResized(
        #require(sourceContext.makeImage()),
        width: outputWidth,
        height: outputHeight
    )
}

private func outlineOfflineAlphaOnly(_ authority: PixelImage) -> PixelImage {
    var rgba = Data(repeating: 0, count: authority.rgba.count)
    for pixelIndex in 0..<(authority.width * authority.height) {
        rgba[pixelIndex * 4 + 3] = authority.rgba[pixelIndex * 4 + 3]
    }
    return PixelImage(width: authority.width, height: authority.height, rgba: rgba)
}

private func outlineAlphaBytes(_ image: PixelImage) -> Data {
    var alpha = Data(repeating: 0, count: image.width * image.height)
    for pixelIndex in 0..<(image.width * image.height) {
        alpha[pixelIndex] = image.rgba[pixelIndex * 4 + 3]
    }
    return alpha
}

private func outlineRadialColorMetrics(
    layer: PixelImage,
    authority: PixelImage,
    centerX: Double,
    centerY: Double,
    pixelRadius: Double
) -> OutlineRadialColorMetrics {
    precondition(layer.width == authority.width && layer.height == authority.height)
    var samples = [StraightRGB]()
    for rayIndex in 0..<96 {
        let angle = Double(rayIndex) / 96 * Double.pi * 2
        var bestAlpha: UInt8 = 0
        var bestColor: StraightRGB?
        for radialStep in 0..<80 {
            let normalizedRadius = 0.58 + Double(radialStep) / 79 * 0.58
            let x = Int((centerX + cos(angle) * pixelRadius * normalizedRadius).rounded())
            let y = Int((centerY + sin(angle) * pixelRadius * normalizedRadius).rounded())
            guard x >= 0, x < layer.width, y >= 0, y < layer.height else { continue }
            let authorityAlpha = authority.rgba[(y * authority.width + x) * 4 + 3]
            guard authorityAlpha >= 19, authorityAlpha >= bestAlpha else { continue }
            bestAlpha = authorityAlpha
            bestColor = layer.pixel(x: x, y: y).straight
        }
        if let bestColor { samples.append(bestColor) }
    }
    var maximumRGBDistance = 0.0
    var maximumHueDistance = 0.0
    var maximumChromaDifference = 0.0
    for lhs in samples.indices {
        for rhs in samples.indices where rhs > lhs {
            maximumRGBDistance = max(
                maximumRGBDistance,
                rgbDistance(samples[lhs], samples[rhs])
            )
            if min(samples[lhs].chroma, samples[rhs].chroma) > 0.12 {
                maximumHueDistance = max(
                    maximumHueDistance,
                    circularHueDistance(samples[lhs].hue, samples[rhs].hue)
                )
            }
            maximumChromaDifference = max(
                maximumChromaDifference,
                abs(samples[lhs].chroma - samples[rhs].chroma)
            )
        }
    }
    return OutlineRadialColorMetrics(
        sampleCount: samples.count,
        maximumRGBDistance: maximumRGBDistance,
        maximumHueDistance: maximumHueDistance,
        maximumChromaDifference: maximumChromaDifference,
        maximumChroma: samples.map(\.chroma).max() ?? 0
    )
}

private func outlineOfflinePositiveMeanCandidates(
    authority: PixelImage,
    support: PixelImage,
    prefix: PixelImage,
    laterAuthorities: ArraySlice<PixelImage>,
    colors: [MaterialColor]
) -> OutlineOfflineCandidates {
    precondition(authority.width == support.width && authority.height == support.height)
    precondition(authority.width == prefix.width && authority.height == prefix.height)
    precondition(!colors.isEmpty)
    let pixelCount = authority.width * authority.height
    var positiveAlphaSum = 0.0
    var positiveAlphaCount = 0
    var peakRGBContribution = 0.0
    for pixelIndex in 0..<pixelCount {
        let offset = pixelIndex * 4
        guard authority.rgba[offset + 3] > 0 else { continue }
        let supportAlpha = Double(support.rgba[offset + 3]) / 255
        guard supportAlpha > 0 else { continue }
        positiveAlphaSum += supportAlpha
        positiveAlphaCount += 1
        let x = pixelIndex % authority.width
        let y = pixelIndex / authority.width
        let background = prefix.pixel(x: x, y: y).straight
        let presented = StraightRGB(
            r: Double(support.rgba[offset]) / 255 + background.r * (1 - supportAlpha),
            g: Double(support.rgba[offset + 1]) / 255 + background.g * (1 - supportAlpha),
            b: Double(support.rgba[offset + 2]) / 255 + background.b * (1 - supportAlpha)
        )
        peakRGBContribution = max(peakRGBContribution, rgbDistance(presented, background))
    }
    let meanPositiveAlpha = positiveAlphaSum / Double(max(positiveAlphaCount, 1))
    var unstrengthenedWeights = [Double](repeating: 0, count: pixelCount)
    var transmissions = [Double](repeating: 1, count: pixelCount)
    for pixelIndex in 0..<pixelCount {
        let offset = pixelIndex * 4
        guard authority.rgba[offset + 3] > 0 else { continue }
        let supportAlpha = Double(support.rgba[offset + 3]) / 255
        let x = pixelIndex % authority.width
        let y = pixelIndex / authority.width
        let background = prefix.pixel(x: x, y: y).straight
        let presented = StraightRGB(
            r: Double(support.rgba[offset]) / 255 + background.r * (1 - supportAlpha),
            g: Double(support.rgba[offset + 1]) / 255 + background.g * (1 - supportAlpha),
            b: Double(support.rgba[offset + 2]) / 255 + background.b * (1 - supportAlpha)
        )
        let rgbWeight = min(1, max(0,
            rgbDistance(presented, background) / max(peakRGBContribution, .ulpOfOne)
        ))
        let alphaWeight = min(1, max(0,
            supportAlpha / max(meanPositiveAlpha, .ulpOfOne)
        ))
        unstrengthenedWeights[pixelIndex] = min(1, max(0,
            1 - (1 - rgbWeight) * (1 - alphaWeight)
        ))
        transmissions[pixelIndex] = laterAuthorities.reduce(1) { partial, later in
            partial * (1 - Double(later.rgba[offset + 3]) / 255)
        }
    }

    let positiveUnionWeights = unstrengthenedWeights.filter { $0 > 0 }
    let meanPositiveUnionWeight = positiveUnionWeights.reduce(0, +)
        / Double(max(positiveUnionWeights.count, 1))
    let strengthenedWeights = unstrengthenedWeights.map { weight in
        min(1, max(0, weight / max(meanPositiveUnionWeight, Double.ulpOfOne)))
    }
    let selfUnionWeights = strengthenedWeights.map { weight in
        1 - (1 - weight) * (1 - weight)
    }

    func projectedLayer(
        weights: [Double],
        target: (StraightRGB) -> StraightRGB
    ) -> (layer: PixelImage, score: Double) {
        var rgba = Data(repeating: 0, count: authority.rgba.count)
        var score = 0.0
        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * 4
            let alphaByte = authority.rgba[offset + 3]
            guard alphaByte > 0 else { continue }
            let x = pixelIndex % authority.width
            let y = pixelIndex / authority.width
            let background = prefix.pixel(x: x, y: y).straight
            let projectedTarget = target(background)
            let weight = weights[pixelIndex]
            let foreground = StraightRGB(
                r: background.r + (projectedTarget.r - background.r) * weight,
                g: background.g + (projectedTarget.g - background.g) * weight,
                b: background.b + (projectedTarget.b - background.b) * weight
            )
            rgba[offset] = UInt8((foreground.r * Double(alphaByte)).rounded())
            rgba[offset + 1] = UInt8((foreground.g * Double(alphaByte)).rounded())
            rgba[offset + 2] = UInt8((foreground.b * Double(alphaByte)).rounded())
            rgba[offset + 3] = alphaByte
            score += Double(alphaByte) / 255 * weight * transmissions[pixelIndex]
                * rgbDistance(projectedTarget, background)
        }
        return (PixelImage(width: authority.width, height: authority.height, rgba: rgba), score)
    }

    let inverseColorCount = 1 / Double(colors.count)
    let centroid = StraightRGB(
        r: colors.reduce(0) { $0 + $1.red } * inverseColorCount,
        g: colors.reduce(0) { $0 + $1.green } * inverseColorCount,
        b: colors.reduce(0) { $0 + $1.blue } * inverseColorCount
    )

    func candidateLayers(
        weights: [Double]
    ) -> (layers: [String: PixelImage], targetIDs: [String: String]) {
        let gamutCandidates = colors.map { color in
            projectedLayer(weights: weights) {
                outlineSelectorGamutTarget(color, background: $0)
            }
        }
        let gamutIndex = gamutCandidates.indices.dropFirst().reduce(0) { best, candidate in
            gamutCandidates[candidate].score > gamutCandidates[best].score ? candidate : best
        }
        var layers = ["gamut-ray": gamutCandidates[gamutIndex].layer]
        var targetIDs = [
            "gamut-ray": outlineTargetIdentity(
                kind: "gamut-ray-\(gamutIndex)",
                colors: [colors[gamutIndex]]
            ),
        ]
        for (index, color) in colors.enumerated() {
            layers["assigned-pole-\(index)"] = projectedLayer(weights: weights) { _ in
                StraightRGB(r: color.red, g: color.green, b: color.blue)
            }.layer
            targetIDs["assigned-pole-\(index)"] = outlineTargetIdentity(
                kind: "assigned-pole-\(index)",
                colors: [color]
            )
        }
        layers["centroid"] = projectedLayer(weights: weights) { _ in centroid }.layer
        targetIDs["centroid"] = outlineTargetIdentity(kind: "centroid", colors: colors)
        return (layers, targetIDs)
    }

    var strengthenedSupportBytes = Data(capacity: pixelCount * 2)
    for weight in selfUnionWeights {
        var quantized = UInt16((weight * Double(UInt16.max)).rounded()).bigEndian
        withUnsafeBytes(of: &quantized) { strengthenedSupportBytes.append(contentsOf: $0) }
    }
    let selfUnionCandidates = candidateLayers(weights: selfUnionWeights)
    let meanNormalizedCandidates = candidateLayers(weights: strengthenedWeights)
    let ceilingWeights = authority.rgba.enumerated().compactMap { index, byte -> Double? in
        guard index % 4 == 3 else { return nil }
        return byte > 0 ? 1 : 0
    }
    let ceilingCandidates = candidateLayers(weights: ceilingWeights)
    return OutlineOfflineCandidates(
        layers: selfUnionCandidates.layers,
        meanNormalizedLayers: meanNormalizedCandidates.layers,
        ceilingLayers: ceilingCandidates.layers,
        ceilingTargetIDs: ceilingCandidates.targetIDs,
        supportDigest: sha256Hex(strengthenedSupportBytes)
    )
}

private func outlineTargetIdentity(
    kind: String,
    colors: [MaterialColor]
) -> String {
    var data = Data(kind.utf8)
    for color in colors {
        for component in [color.red, color.green, color.blue] {
            var bits = component.bitPattern.bigEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }
    return "\(kind):\(sha256Hex(data))"
}
#endif

private struct OutlineR19OracleScene {
    let colorCount: Int
    let material: DailyMaterialDNA
    let base: PixelImage
    let authorities: [PixelImage]
    let supports: [PixelImage]
    let authoredSupports: [PixelImage]
}

private struct OutlineR19Candidates {
    let layers: [String: PixelImage]
    let peakLayers: [String: PixelImage]
    let targetIDs: [String: String]
    let supportDigest: String
    let positiveMeanGamutPoleLayers: [PixelImage]
    let positiveMeanGamutIndex: Int
}

private struct OutlineR19RadialColorMetrics: CustomStringConvertible {
    let sampleCount: Int
    let maximumRGBDistance: Double
    let maximumHueDistance: Double
    let maximumChromaDifference: Double
    let maximumChroma: Double

    var isObservable: Bool { sampleCount >= 2 }

    var varies: Bool {
        isObservable
            && maximumRGBDistance > 0.08
            && (maximumHueDistance > 0.04 || maximumChromaDifference > 0.06)
            && maximumChroma > 0.25
    }

    var passes: Bool { isObservable && varies }

    var description: String {
        "samples=\(sampleCount), observable=\(isObservable), "
            + "rgb=\(maximumRGBDistance), "
            + "hue=\(maximumHueDistance), chromaDelta=\(maximumChromaDifference), "
            + "maxChroma=\(maximumChroma), varies=\(varies)"
    }
}

private struct OutlineR20RadialFixture {
    let layer: PixelImage
    let authority: PixelImage
    let center: Double
    let radius: Double
}

private func outlineR20RadialFixture(
    availableRayCount: Int,
    flat: Bool
) -> OutlineR20RadialFixture {
    precondition((0...96).contains(availableRayCount))
    let side = 513
    let center = Double(side) * 0.5
    let radius = 180.0
    var authority = Data(repeating: 0, count: side * side * 4)
    var layer = Data(repeating: 0, count: side * side * 4)
    for rayIndex in 0..<availableRayCount {
        let angle = Double(rayIndex) / 96 * Double.pi * 2
        let phase = Double(rayIndex) / Double(max(availableRayCount - 1, 1))
        let color = flat
            ? StraightRGB(r: 0.92, g: 0.08, b: 0.16)
            : StraightRGB(r: 0.92 * (1 - phase), g: 0.12, b: 0.92 * phase)
        for radialStep in 0..<80 {
            let normalizedRadius = 0.58 + Double(radialStep) / 79 * 0.58
            let x = Int((center + cos(angle) * radius * normalizedRadius).rounded())
            let y = Int((center + sin(angle) * radius * normalizedRadius).rounded())
            guard x >= 0, x < side, y >= 0, y < side else { continue }
            let offset = (y * side + x) * 4
            authority[offset + 3] = 255
            layer[offset] = UInt8((color.r * 255).rounded())
            layer[offset + 1] = UInt8((color.g * 255).rounded())
            layer[offset + 2] = UInt8((color.b * 255).rounded())
            layer[offset + 3] = 255
        }
    }
    return OutlineR20RadialFixture(
        layer: PixelImage(width: side, height: side, rgba: layer),
        authority: PixelImage(width: side, height: side, rgba: authority),
        center: center,
        radius: radius
    )
}

private func outlineR20FlatTargetLayer(
    authority: PixelImage,
    color: MaterialColor
) -> PixelImage {
    var rgba = Data(repeating: 0, count: authority.rgba.count)
    for pixelIndex in 0..<(authority.width * authority.height) {
        let offset = pixelIndex * 4
        let alphaByte = authority.rgba[offset + 3]
        guard alphaByte > 0 else { continue }
        let alpha = Double(alphaByte) / 255
        rgba[offset] = UInt8((color.red * alpha * 255).rounded())
        rgba[offset + 1] = UInt8((color.green * alpha * 255).rounded())
        rgba[offset + 2] = UInt8((color.blue * alpha * 255).rounded())
        rgba[offset + 3] = alphaByte
    }
    return PixelImage(width: authority.width, height: authority.height, rgba: rgba)
}

private func outlineR20AuthoredRadialFieldPasses(
    _ material: ActorMaterialRecipe,
    metrics: OutlineR19RadialColorMetrics
) -> Bool {
    let expectedColorIndexes = Set(material.colors.indices)
    let authoredColorIndexes = Set(material.fields.map(\.colorIndex))
    return material.family == .outline
        && material.colors.count >= 2
        && material.fields.count == material.colors.count
        && authoredColorIndexes == expectedColorIndexes
        && material.fields.allSatisfy {
            $0.blend == .normal
                && $0.radius > 0
                && $0.softness > 0
                && $0.opacity > 0
        }
        && metrics.varies
}

private func outlineR19Resized(
    _ image: CGImage,
    width: Int,
    height: Int
) throws -> PixelImage {
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
    guard rendered else { throw MaterialRendererError.cannotCreateBitmap(width, height) }
    return PixelImage(width: width, height: height, rgba: rgba)
}

private func outlineR19PlacedAndDownsampled(
    _ image: CGImage,
    drawRect: CGRect,
    sourceWidth: Int,
    sourceHeight: Int,
    outputWidth: Int,
    outputHeight: Int
) throws -> PixelImage {
    let sourceContext = try #require(CGContext(
        data: nil,
        width: sourceWidth,
        height: sourceHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ))
    sourceContext.clear(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
    sourceContext.draw(image, in: drawRect)
    return try outlineR19Resized(
        #require(sourceContext.makeImage()),
        width: outputWidth,
        height: outputHeight
    )
}

private func outlineR19AlphaOnly(_ authority: PixelImage) -> PixelImage {
    var rgba = Data(repeating: 0, count: authority.rgba.count)
    for pixelIndex in 0..<(authority.width * authority.height) {
        rgba[pixelIndex * 4 + 3] = authority.rgba[pixelIndex * 4 + 3]
    }
    return PixelImage(width: authority.width, height: authority.height, rgba: rgba)
}

private func outlineR19AlphaBytes(_ image: PixelImage) -> Data {
    var alpha = Data(repeating: 0, count: image.width * image.height)
    for pixelIndex in 0..<(image.width * image.height) {
        alpha[pixelIndex] = image.rgba[pixelIndex * 4 + 3]
    }
    return alpha
}

private func outlineR19RadialColorMetrics(
    layer: PixelImage,
    authority: PixelImage,
    centerX: Double,
    centerY: Double,
    pixelRadius: Double
) -> OutlineR19RadialColorMetrics {
    precondition(layer.width == authority.width && layer.height == authority.height)
    var samples = [StraightRGB]()
    for rayIndex in 0..<96 {
        let angle = Double(rayIndex) / 96 * Double.pi * 2
        var bestAlpha: UInt8 = 0
        var bestColor: StraightRGB?
        for radialStep in 0..<80 {
            let normalizedRadius = 0.58 + Double(radialStep) / 79 * 0.58
            let x = Int((centerX + cos(angle) * pixelRadius * normalizedRadius).rounded())
            let y = Int((centerY + sin(angle) * pixelRadius * normalizedRadius).rounded())
            guard x >= 0, x < layer.width, y >= 0, y < layer.height else { continue }
            let alpha = authority.rgba[(y * authority.width + x) * 4 + 3]
            guard alpha >= 19, alpha >= bestAlpha else { continue }
            bestAlpha = alpha
            bestColor = layer.pixel(x: x, y: y).straight
        }
        if let bestColor { samples.append(bestColor) }
    }
    var maximumRGBDistance = 0.0
    var maximumHueDistance = 0.0
    var maximumChromaDifference = 0.0
    for lhs in samples.indices {
        for rhs in samples.indices where rhs > lhs {
            maximumRGBDistance = max(
                maximumRGBDistance,
                rgbDistance(samples[lhs], samples[rhs])
            )
            if min(samples[lhs].chroma, samples[rhs].chroma) > 0.12 {
                maximumHueDistance = max(
                    maximumHueDistance,
                    circularHueDistance(samples[lhs].hue, samples[rhs].hue)
                )
            }
            maximumChromaDifference = max(
                maximumChromaDifference,
                abs(samples[lhs].chroma - samples[rhs].chroma)
            )
        }
    }
    return OutlineR19RadialColorMetrics(
        sampleCount: samples.count,
        maximumRGBDistance: maximumRGBDistance,
        maximumHueDistance: maximumHueDistance,
        maximumChromaDifference: maximumChromaDifference,
        maximumChroma: samples.map(\.chroma).max() ?? 0
    )
}

private func outlineR19PositiveMeanCandidates(
    authority: PixelImage,
    support: PixelImage,
    prefix: PixelImage,
    laterAuthorities: ArraySlice<PixelImage>,
    colors: [MaterialColor]
) -> OutlineR19Candidates {
    precondition(authority.width == support.width && authority.height == support.height)
    precondition(authority.width == prefix.width && authority.height == prefix.height)
    precondition(!colors.isEmpty)
    let pixelCount = authority.width * authority.height
    var positiveAlphaSum = 0.0
    var positiveAlphaCount = 0
    var peakSupportAlpha = 0.0
    var peakRGBContribution = 0.0
    for pixelIndex in 0..<pixelCount {
        let offset = pixelIndex * 4
        guard authority.rgba[offset + 3] > 0 else { continue }
        let supportAlpha = Double(support.rgba[offset + 3]) / 255
        guard supportAlpha > 0 else { continue }
        positiveAlphaSum += supportAlpha
        positiveAlphaCount += 1
        peakSupportAlpha = max(peakSupportAlpha, supportAlpha)
        let x = pixelIndex % authority.width
        let y = pixelIndex / authority.width
        let background = prefix.pixel(x: x, y: y).straight
        let presented = StraightRGB(
            r: Double(support.rgba[offset]) / 255 + background.r * (1 - supportAlpha),
            g: Double(support.rgba[offset + 1]) / 255 + background.g * (1 - supportAlpha),
            b: Double(support.rgba[offset + 2]) / 255 + background.b * (1 - supportAlpha)
        )
        peakRGBContribution = max(peakRGBContribution, rgbDistance(presented, background))
    }
    let meanPositiveAlpha = positiveAlphaSum / Double(max(positiveAlphaCount, 1))
    var positiveMeanWeights = [Double](repeating: 0, count: pixelCount)
    var peakWeights = [Double](repeating: 0, count: pixelCount)
    var transmissions = [Double](repeating: 1, count: pixelCount)
    for pixelIndex in 0..<pixelCount {
        let offset = pixelIndex * 4
        guard authority.rgba[offset + 3] > 0 else { continue }
        let supportAlpha = Double(support.rgba[offset + 3]) / 255
        let x = pixelIndex % authority.width
        let y = pixelIndex / authority.width
        let background = prefix.pixel(x: x, y: y).straight
        let presented = StraightRGB(
            r: Double(support.rgba[offset]) / 255 + background.r * (1 - supportAlpha),
            g: Double(support.rgba[offset + 1]) / 255 + background.g * (1 - supportAlpha),
            b: Double(support.rgba[offset + 2]) / 255 + background.b * (1 - supportAlpha)
        )
        let rgbWeight = min(1, max(0,
            rgbDistance(presented, background) / max(peakRGBContribution, .ulpOfOne)
        ))
        let meanAlphaWeight = min(1, max(0,
            supportAlpha / max(meanPositiveAlpha, .ulpOfOne)
        ))
        let peakAlphaWeight = min(1, max(0,
            supportAlpha / max(peakSupportAlpha, .ulpOfOne)
        ))
        positiveMeanWeights[pixelIndex] = min(1, max(0,
            1 - (1 - rgbWeight) * (1 - meanAlphaWeight)
        ))
        peakWeights[pixelIndex] = min(1, max(0,
            1 - (1 - rgbWeight) * (1 - peakAlphaWeight)
        ))
        transmissions[pixelIndex] = laterAuthorities.reduce(1) { partial, later in
            partial * (1 - Double(later.rgba[offset + 3]) / 255)
        }
    }

    func projectedLayer(
        weights: [Double],
        target: (StraightRGB) -> StraightRGB
    ) -> (layer: PixelImage, score: Double) {
        var rgba = Data(repeating: 0, count: authority.rgba.count)
        var score = 0.0
        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * 4
            let alphaByte = authority.rgba[offset + 3]
            guard alphaByte > 0 else { continue }
            let x = pixelIndex % authority.width
            let y = pixelIndex / authority.width
            let background = prefix.pixel(x: x, y: y).straight
            let projectedTarget = target(background)
            let weight = weights[pixelIndex]
            let foreground = StraightRGB(
                r: background.r + (projectedTarget.r - background.r) * weight,
                g: background.g + (projectedTarget.g - background.g) * weight,
                b: background.b + (projectedTarget.b - background.b) * weight
            )
            rgba[offset] = UInt8((foreground.r * Double(alphaByte)).rounded())
            rgba[offset + 1] = UInt8((foreground.g * Double(alphaByte)).rounded())
            rgba[offset + 2] = UInt8((foreground.b * Double(alphaByte)).rounded())
            rgba[offset + 3] = alphaByte
            score += Double(alphaByte) / 255 * weight * transmissions[pixelIndex]
                * rgbDistance(projectedTarget, background)
        }
        return (PixelImage(width: authority.width, height: authority.height, rgba: rgba), score)
    }

    let inverseColorCount = 1 / Double(colors.count)
    let centroid = StraightRGB(
        r: colors.reduce(0) { $0 + $1.red } * inverseColorCount,
        g: colors.reduce(0) { $0 + $1.green } * inverseColorCount,
        b: colors.reduce(0) { $0 + $1.blue } * inverseColorCount
    )
    func candidateLayers(
        weights: [Double]
    ) -> (
        layers: [String: PixelImage],
        targetIDs: [String: String],
        gamutPoleLayers: [PixelImage],
        gamutIndex: Int
    ) {
        let gamutCandidates = colors.map { color in
            projectedLayer(weights: weights) {
                outlineSelectorGamutTarget(color, background: $0)
            }
        }
        let gamutIndex = gamutCandidates.indices.dropFirst().reduce(0) { best, candidate in
            gamutCandidates[candidate].score > gamutCandidates[best].score ? candidate : best
        }
        var layers = ["gamut-ray": gamutCandidates[gamutIndex].layer]
        var targetIDs = [
            "gamut-ray": outlineR19TargetIdentity(
                kind: "gamut-ray-\(gamutIndex)",
                colors: [colors[gamutIndex]]
            ),
        ]
        for (index, color) in colors.enumerated() {
            layers["assigned-pole-\(index)"] = projectedLayer(weights: weights) { _ in
                StraightRGB(r: color.red, g: color.green, b: color.blue)
            }.layer
            targetIDs["assigned-pole-\(index)"] = outlineR19TargetIdentity(
                kind: "assigned-pole-\(index)",
                colors: [color]
            )
        }
        layers["centroid"] = projectedLayer(weights: weights) { _ in centroid }.layer
        targetIDs["centroid"] = outlineR19TargetIdentity(
            kind: "centroid",
            colors: colors
        )
        return (
            layers,
            targetIDs,
            gamutCandidates.map(\.layer),
            gamutIndex
        )
    }

    var supportBytes = Data(capacity: pixelCount * 2)
    for weight in positiveMeanWeights {
        var quantized = UInt16((weight * Double(UInt16.max)).rounded()).bigEndian
        withUnsafeBytes(of: &quantized) { supportBytes.append(contentsOf: $0) }
    }
    let positiveMean = candidateLayers(weights: positiveMeanWeights)
    let peak = candidateLayers(weights: peakWeights)
    return OutlineR19Candidates(
        layers: positiveMean.layers,
        peakLayers: peak.layers,
        targetIDs: positiveMean.targetIDs,
        supportDigest: sha256Hex(supportBytes),
        positiveMeanGamutPoleLayers: positiveMean.gamutPoleLayers,
        positiveMeanGamutIndex: positiveMean.gamutIndex
    )
}

private func outlineR19TargetIdentity(
    kind: String,
    colors: [MaterialColor]
) -> String {
    var data = Data(kind.utf8)
    for color in colors {
        for component in [color.red, color.green, color.blue] {
            var bits = component.bitPattern.bigEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }
    return "\(kind):\(sha256Hex(data))"
}

private func outlineSelectorGamutTarget(
    _ color: MaterialColor,
    background: StraightRGB
) -> StraightRGB {
    let direction = (
        color.red - background.r,
        color.green - background.g,
        color.blue - background.b
    )
    func projectionLimit(origin: Double, delta: Double) -> Double {
        if delta > 0 { return (1 - origin) / delta }
        if delta < 0 { return (0 - origin) / delta }
        return .infinity
    }
    let limits = [
        projectionLimit(origin: background.r, delta: direction.0),
        projectionLimit(origin: background.g, delta: direction.1),
        projectionLimit(origin: background.b, delta: direction.2),
    ].filter(\.isFinite)
    guard let furthest = limits.min(), furthest >= 1 else {
        return StraightRGB(r: color.red, g: color.green, b: color.blue)
    }
    return StraightRGB(
        r: min(1, max(0, background.r + direction.0 * furthest)),
        g: min(1, max(0, background.g + direction.1 * furthest)),
        b: min(1, max(0, background.b + direction.2 * furthest))
    )
}

private func outlineSelectorRawTargetLayer(
    gamutPoleLayers: [PixelImage],
    assignedColors: [MaterialColor],
    prefix: PixelImage,
    target: MaterialColor
) -> PixelImage {
    precondition(!gamutPoleLayers.isEmpty)
    precondition(gamutPoleLayers.count == assignedColors.count)
    precondition(gamutPoleLayers.allSatisfy {
        $0.width == prefix.width && $0.height == prefix.height
    })
    var rgba = Data(repeating: 0, count: prefix.width * prefix.height * 4)
    for pixelIndex in 0..<(prefix.width * prefix.height) {
        let offset = pixelIndex * 4
        let alphaByte = gamutPoleLayers[0].rgba[offset + 3]
        guard alphaByte > 0 else { continue }
        let x = pixelIndex % prefix.width
        let y = pixelIndex / prefix.width
        let background = prefix.pixel(x: x, y: y).straight
        var strongestDenominator = 0.0
        var recoveredWeight = 0.0
        for (poleIndex, color) in assignedColors.enumerated() {
            let gamutTarget = outlineSelectorGamutTarget(color, background: background)
            let direction = (
                gamutTarget.r - background.r,
                gamutTarget.g - background.g,
                gamutTarget.b - background.b
            )
            let denominator = direction.0 * direction.0
                + direction.1 * direction.1
                + direction.2 * direction.2
            guard denominator > strongestDenominator else { continue }
            let presented = gamutPoleLayers[poleIndex].pixel(x: x, y: y).straight
            let numerator = (presented.r - background.r) * direction.0
                + (presented.g - background.g) * direction.1
                + (presented.b - background.b) * direction.2
            strongestDenominator = denominator
            recoveredWeight = min(1, max(0, numerator / denominator))
        }
        let foreground = StraightRGB(
            r: background.r + (target.red - background.r) * recoveredWeight,
            g: background.g + (target.green - background.g) * recoveredWeight,
            b: background.b + (target.blue - background.b) * recoveredWeight
        )
        rgba[offset] = UInt8((foreground.r * Double(alphaByte)).rounded())
        rgba[offset + 1] = UInt8((foreground.g * Double(alphaByte)).rounded())
        rgba[offset + 2] = UInt8((foreground.b * Double(alphaByte)).rounded())
        rgba[offset + 3] = alphaByte
    }
    return PixelImage(width: prefix.width, height: prefix.height, rgba: rgba)
}

private struct OutlineAlphaRunMetrics: CustomStringConvertible {
    let percentile90Thickness: Double
    let activeRadialDensity: Double
    let radialBandCount: Int
    let angularCoverage: Double

    var description: String {
        "p90Thickness=\(percentile90Thickness), density=\(activeRadialDensity), "
            + "bands=\(radialBandCount), angularCoverage=\(angularCoverage)"
    }
}

private func outlineAlphaRunMetrics(
    _ image: PixelImage,
    centerX: Double,
    centerY: Double,
    pixelRadius: Double
) -> OutlineAlphaRunMetrics {
    let angleCount = 96
    let maximumNormalizedRadius = 1.12
    let radialSteps = max(32, Int(ceil(pixelRadius * maximumNormalizedRadius)))
    let normalizedStep = maximumNormalizedRadius / Double(radialSteps)
    var thicknesses = [Double]()
    var bandCounts = [Double]()
    var activeCount = 0
    var supportedRays = 0
    for angleIndex in 0..<angleCount {
        let angle = Double(angleIndex) / Double(angleCount) * Double.pi * 2
        let active = (0...radialSteps).map { radialIndex in
            let radius = Double(radialIndex) * normalizedStep
            let x = Int(floor(centerX + cos(angle) * radius * pixelRadius))
            let y = Int(floor(centerY + sin(angle) * radius * pixelRadius))
            guard (0..<image.width).contains(x), (0..<image.height).contains(y) else {
                return false
            }
            let support = image.pixel(x: x, y: y).alphaByte >= 20
            if support { activeCount += 1 }
            return support
        }
        let longestRun = fixture11LongestRun(active)
        thicknesses.append(Double(longestRun) * normalizedStep)
        var bands = 0
        var prior = false
        for support in active {
            if support && !prior { bands += 1 }
            prior = support
        }
        bandCounts.append(Double(bands))
        if active.enumerated().contains(where: { index, support in
            support && (0.50...1.10).contains(Double(index) * normalizedStep)
        }) { supportedRays += 1 }
    }
    return OutlineAlphaRunMetrics(
        percentile90Thickness: percentile(thicknesses.sorted(), fraction: 0.90),
        activeRadialDensity: Double(activeCount)
            / Double(angleCount * (radialSteps + 1)),
        radialBandCount: Int(percentile(bandCounts.sorted(), fraction: 0.50).rounded()),
        angularCoverage: Double(supportedRays) / Double(angleCount)
    )
}

private func outlineSourceOver(source: PixelImage, underlay: PixelImage) -> PixelImage {
    precondition(source.width == underlay.width && source.height == underlay.height)
    var rgba = Data(repeating: 0, count: source.width * source.height * 4)
    for index in 0..<(source.width * source.height) {
        let offset = index * 4
        let alpha = Double(source.rgba[offset + 3]) / 255
        for channel in 0..<3 {
            let premultiplied = Double(source.rgba[offset + channel]) / 255
            let background = Double(underlay.rgba[offset + channel]) / 255
            rgba[offset + channel] = UInt8((min(1,
                premultiplied + background * (1 - alpha)
            ) * 255).rounded())
        }
        let underlayAlpha = Double(underlay.rgba[offset + 3]) / 255
        rgba[offset + 3] = UInt8((min(
            1,
            alpha + underlayAlpha * (1 - alpha)
        ) * 255).rounded())
    }
    return PixelImage(width: source.width, height: source.height, rgba: rgba)
}

private func outlineNativeIdentityPasses(_ metrics: OutlineNativeIdentityMetrics) -> Bool {
    outlineNativeIdentityPasses(metrics, minimumAngularCoverage: 0.77)
}

private func outlineNativeIdentityPasses(
    _ metrics: OutlineNativeIdentityMetrics,
    minimumAngularCoverage: Double
) -> Bool {
    metrics.peakContrast >= 0.070
        && metrics.centerToPeakRatio <= 0.24
        && metrics.percentile90ContourThickness <= 0.24
        && metrics.activeRadialDensity <= 0.32
        && (1...3).contains(metrics.radialBandCount)
        && metrics.angularCoverage >= minimumAngularCoverage
}

private func outlineNativePresentationIsEligible(
    attainablePeakContrast: Double
) -> Bool {
    attainablePeakContrast >= 0.070
}

private func outlineNativeActorIsEligible(
    _ actor: ActorCompositionRecipe,
    centerX: Double,
    centerY: Double,
    width: Int,
    height: Int
) -> Bool {
    let sampledExtent = actor.diameter * 393 * 0.5 * 1.12
    return centerX - sampledExtent >= 0
        && centerX + sampledExtent < Double(width)
        && centerY - sampledExtent >= 0
        && centerY + sampledExtent < Double(height)
}

private func outlineNativeIdentityMetrics(
    _ image: PixelImage,
    reference: PixelImage,
    centerX: Double,
    centerY: Double,
    pixelRadius: Double,
    ownerIndex: UInt8? = nil,
    ownerLabels: Data? = nil
) -> OutlineNativeIdentityMetrics {
    precondition(image.width == reference.width && image.height == reference.height)
    precondition(pixelRadius > 0)
    let angleCount = 96
    let maximumNormalizedRadius = 1.12
    let radialSteps = max(32, Int(ceil(pixelRadius * maximumNormalizedRadius)))
    var sampledContrasts = [[Double]]()
    var observableRays = [Bool]()
    sampledContrasts.reserveCapacity(angleCount)
    observableRays.reserveCapacity(angleCount)
    var peakContrast = 0.0

    for angleIndex in 0..<angleCount {
        let angle = Double(angleIndex) / Double(angleCount) * Double.pi * 2
        var ray = [Double]()
        var observable = ownerLabels == nil
        ray.reserveCapacity(radialSteps + 1)
        for radialIndex in 0...radialSteps {
            let normalizedRadius = Double(radialIndex) / Double(radialSteps)
                * maximumNormalizedRadius
            let x = Int(floor(centerX + cos(angle) * normalizedRadius * pixelRadius))
            let y = Int(floor(centerY + sin(angle) * normalizedRadius * pixelRadius))
            let contrast: Double
            if (0..<image.width).contains(x), (0..<image.height).contains(y) {
                let exactOwner = ownerIndex.flatMap { index in
                    ownerLabels.map { $0[y * image.width + x] == index }
                }
                if exactOwner == true, (0.50...1.10).contains(normalizedRadius) {
                    observable = true
                }
                contrast = exactOwner == false ? 0 : rgbDistance(
                    image.pixel(x: x, y: y).straight,
                    reference.pixel(x: x, y: y).straight
                )
            } else {
                contrast = 0
            }
            peakContrast = max(peakContrast, contrast)
            ray.append(contrast)
        }
        sampledContrasts.append(ray)
        observableRays.append(observable)
    }

    let activeThreshold = max(0.035, peakContrast * 0.20)
    let normalizedStep = maximumNormalizedRadius / Double(radialSteps)
    var centerContrasts = [Double]()
    var thicknesses = [Double]()
    var rayBandCounts = [Double]()
    var activeSampleCount = 0
    var angularSupport = 0

    for (rayIndex, ray) in sampledContrasts.enumerated() where observableRays[rayIndex] {
        let active = ray.enumerated().map { radialIndex, contrast in
            let normalizedRadius = Double(radialIndex) * normalizedStep
            if normalizedRadius <= 0.20 { centerContrasts.append(contrast) }
            let owned = contrast >= activeThreshold
            if owned { activeSampleCount += 1 }
            return owned
        }
        thicknesses.append(Double(fixture11LongestRun(active)) * normalizedStep)
        var rayBandCount = 0
        var wasActive = false
        for isActive in active {
            if isActive && !wasActive { rayBandCount += 1 }
            wasActive = isActive
        }
        rayBandCounts.append(Double(rayBandCount))
        if active.enumerated().contains(where: { radialIndex, owned in
            let normalizedRadius = Double(radialIndex) * normalizedStep
            return owned && (0.50...1.10).contains(normalizedRadius)
        }) {
            angularSupport += 1
        }
    }

    centerContrasts.sort()
    thicknesses.sort()
    let radialBandCount = Int(percentile(rayBandCounts.sorted(), fraction: 0.50).rounded())
    return OutlineNativeIdentityMetrics(
        peakContrast: peakContrast,
        centerToPeakRatio: percentile(centerContrasts, fraction: 0.90)
            / max(peakContrast, 0.000_001),
        percentile90ContourThickness: percentile(thicknesses, fraction: 0.90),
        activeRadialDensity: Double(activeSampleCount)
            / Double(max(observableRays.filter { $0 }.count, 1) * (radialSteps + 1)),
        radialBandCount: radialBandCount,
        angularCoverage: Double(angularSupport)
            / Double(max(observableRays.filter { $0 }.count, 1)),
        observableRayCount: observableRays.filter { $0 }.count
    )
}

private func outlineNativeControl(
    side: Int,
    intensity: (_ normalizedRadius: Double, _ angle: Double) -> Double
) -> PixelImage {
    let center = Double(side) * 0.5
    let pixelRadius = Double(side) * 0.42
    var rgba = Data(repeating: 0, count: side * side * 4)
    for y in 0..<side {
        for x in 0..<side {
            let dx = Double(x) + 0.5 - center
            let dy = Double(y) + 0.5 - center
            let level = min(1, max(0, intensity(hypot(dx, dy) / pixelRadius, atan2(dy, dx))))
            let byte = UInt8((level * 255).rounded())
            let offset = (y * side + x) * 4
            rgba[offset] = byte
            rgba[offset + 1] = byte
            rgba[offset + 2] = byte
            rgba[offset + 3] = 255
        }
    }
    return PixelImage(width: side, height: side, rgba: rgba)
}

private func outlineBelowCutoffMissingArcMutation(
    _ scene: MaterialPresentationEvidenceScene,
    actor: ActorCompositionRecipe
) throws -> MaterialPresentationEvidenceScene {
    let fullScreen = try outlineBelowCutoffMissingArcMutation(scene.fullScreen, actor: actor)
    return MaterialPresentationEvidenceScene(
        fullScreen: fullScreen,
        calendarTile: try outlineCroppedRenderedImage(fullScreen, crop: scene.tileCrop),
        tileCrop: scene.tileCrop,
        drawSequence: scene.drawSequence,
        ownership: scene.ownership
    )
}

private func outlineBelowCutoffMissingArcMutation(
    _ image: NeutralRenderedImage,
    actor: ActorCompositionRecipe
) throws -> NeutralRenderedImage {
    let pixels = try pixels(image.pngData)
    var rgba = pixels.rgba
    let centerX = actor.position.x * 393
    let centerY = actor.position.y * 852
    let pixelRadius = actor.diameter * 393 * 0.5
    for y in 0..<pixels.height {
        for x in 0..<pixels.width {
            let dx = Double(x) + 0.5 - centerX
            let dy = Double(y) + 0.5 - centerY
            let normalizedRadius = hypot(dx, dy) / max(pixelRadius, 1)
            let angle = atan2(dy, dx)
            guard (0.45...1.12).contains(normalizedRadius),
                  abs(angle) < Double.pi * 0.34
            else { continue }
            let offset = (y * pixels.width + x) * 4
            let oldAlpha = rgba[offset + 3]
            guard oldAlpha > 0 else { continue }
            let newAlpha = min(oldAlpha, 19)
            for channel in 0..<3 {
                rgba[offset + channel] = UInt8((Double(rgba[offset + channel])
                    * Double(newAlpha) / Double(oldAlpha)).rounded())
            }
            rgba[offset + 3] = newAlpha
        }
    }
    return try outlineRenderedImage(PixelImage(
        width: pixels.width,
        height: pixels.height,
        rgba: rgba
    ))
}

private func outlineCroppedRenderedImage(
    _ image: NeutralRenderedImage,
    crop: PixelRect
) throws -> NeutralRenderedImage {
    let pixels = try pixels(image.pngData).cropped(
        x: crop.x,
        y: crop.y,
        width: crop.width,
        height: crop.height
    )
    return try outlineRenderedImage(pixels)
}

private func outlineRenderedImage(_ image: PixelImage) throws -> NeutralRenderedImage {
    var rgba = image.rgba
    let cgImage = try rgba.withUnsafeMutableBytes { bytes in
        let context = try #require(CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        return try #require(context.makeImage())
    }
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, cgImage, nil)
    try #require(CGImageDestinationFinalize(destination))
    return NeutralRenderedImage(
        pngData: data as Data,
        pixelWidth: image.width,
        pixelHeight: image.height
    )
}

private enum Fixture11PresentationView: String, Hashable {
    case full
    case tile
    case actor
    case exact
}

private struct Fixture11OwnedLayer {
    let actor: ActorCompositionRecipe
    let alpha: PixelImage
    let removed: PixelImage
}

private struct Fixture11PresentationSample {
    let view: Fixture11PresentationView
    let current: PixelImage
    let preOnly: PixelImage
    let postWitness: PixelImage
    let alpha: PixelImage
    let centerX: Double
    let centerY: Double
    let pixelRadius: Double
    let originX: Int
    let originY: Int
}

private struct Fixture11IsolatedIdentityMetrics {
    let eligibleRays: Int
    let supportedRays: Int
    let percentile90Contrast: Double

    var coverage: Double { Double(supportedRays) / Double(max(eligibleRays, 1)) }
    var passes: Bool { eligibleRays > 0 && coverage >= 0.82 && percentile90Contrast >= 0.16 }
}

private func fixture11OwnedVisibilityWitness(
    canonical: PixelImage,
    owners: [Fixture11OwnedLayer]
) -> PixelImage {
    precondition(owners.allSatisfy {
        $0.removed.width == canonical.width && $0.removed.height == canonical.height
    })
    var rgba = canonical.rgba
    for y in 0..<canonical.height {
        for x in 0..<canonical.width {
            for owner in owners.reversed() {
                let centerX = owner.actor.position.x * Double(canonical.width)
                let centerY = owner.actor.position.y * Double(canonical.height)
                let alphaX = Int(floor(Double(x) + 0.5 - centerX + Double(owner.alpha.width) * 0.5))
                let alphaY = Int(floor(Double(y) + 0.5 - centerY + Double(owner.alpha.height) * 0.5))
                guard (0..<owner.alpha.width).contains(alphaX),
                      (0..<owner.alpha.height).contains(alphaY),
                      owner.alpha.pixel(x: alphaX, y: alphaY).alphaByte > 0
                else { continue }

                let offset = (y * canonical.width + x) * 4
                let removed = owner.removed.pixel(x: x, y: y)
                if rgba[offset] != removed.redByte
                    || rgba[offset + 1] != removed.greenByte
                    || rgba[offset + 2] != removed.blueByte {
                    let adjusted = MaterialRenderer.outlineVisibilityPixel(
                        OutlineVisibilityPixel(
                            red: rgba[offset],
                            green: rgba[offset + 1],
                            blue: rgba[offset + 2],
                            alpha: rgba[offset + 3]
                        ),
                        background: MaterialColor(
                            red: removed.straight.r,
                            green: removed.straight.g,
                            blue: removed.straight.b
                        )
                    )
                    rgba[offset] = adjusted.red
                    rgba[offset + 1] = adjusted.green
                    rgba[offset + 2] = adjusted.blue
                }
                // The first topmost isolated-alpha owner is authoritative even
                // when its exact counterfactual RGB delta rounds to zero.
                break
            }
        }
    }
    return PixelImage(width: canonical.width, height: canonical.height, rgba: rgba)
}

private func fixture11PresentationViews(
    current: PixelImage,
    preOnly: PixelImage,
    postWitness: PixelImage,
    alpha: PixelImage,
    actor: ActorCompositionRecipe
) -> [Fixture11PresentationSample] {
    let centerX = actor.position.x * 393
    let centerY = actor.position.y * 852
    let diameter = actorPixelDiameter(actor)
    let actorRect = fixture11CenteredCrop(
        centerX: centerX,
        centerY: centerY,
        side: diameter,
        width: 393,
        height: 852
    )
    let exactRect = fixture11CenteredCrop(
        centerX: centerX,
        centerY: centerY,
        side: max(diameter, alpha.width),
        width: 393,
        height: 852
    )
    let definitions: [(Fixture11PresentationView, Int, Int, Int, Int)] = [
        (.full, 0, 0, 393, 852),
        (.tile, 0, 229, 393, 393),
        (.actor, actorRect.x, actorRect.y, actorRect.width, actorRect.height),
        (.exact, exactRect.x, exactRect.y, exactRect.width, exactRect.height),
    ]
    return definitions.map { view, x, y, width, height in
        Fixture11PresentationSample(
            view: view,
            current: current.cropped(x: x, y: y, width: width, height: height),
            preOnly: preOnly.cropped(x: x, y: y, width: width, height: height),
            postWitness: postWitness.cropped(x: x, y: y, width: width, height: height),
            alpha: alpha,
            centerX: centerX - Double(x),
            centerY: centerY - Double(y),
            pixelRadius: actor.diameter * 393 * 0.48,
            originX: x,
            originY: y
        )
    }
}

private func fixture11CenteredCrop(
    centerX: Double,
    centerY: Double,
    side: Int,
    width: Int,
    height: Int
) -> (x: Int, y: Int, width: Int, height: Int) {
    let cropWidth = min(side, width)
    let cropHeight = min(side, height)
    return (
        x: min(width - cropWidth, max(0, Int(floor(centerX - Double(cropWidth) * 0.5)))),
        y: min(height - cropHeight, max(0, Int(floor(centerY - Double(cropHeight) * 0.5)))),
        width: cropWidth,
        height: cropHeight
    )
}

private func fixture11IsolatedIdentityMetrics(
    alpha: PixelImage,
    image: PixelImage,
    centerX: Double,
    centerY: Double,
    pixelRadius: Double,
    background: BackgroundCondition
) -> Fixture11IsolatedIdentityMetrics {
    let backgroundColor = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: backgroundColor.red,
        g: backgroundColor.green,
        b: backgroundColor.blue
    )
    let alphaCenterX = Double(alpha.width) * 0.5
    let alphaCenterY = Double(alpha.height) * 0.5
    let radialSteps = max(1, Int(ceil((1.08 - 0.52) * pixelRadius)))
    var eligibleRays = 0
    var supportedRays = 0
    var contrasts = [Double]()
    for angleIndex in 0..<96 {
        let angle = Double(angleIndex) / 96 * Double.pi * 2
        var samples = [(owned: Bool, contrast: Double)]()
        var inFrame = true
        for step in 0...radialSteps {
            let radius = 0.52 + Double(step) / pixelRadius
            let x = Int(floor(centerX + cos(angle) * radius * pixelRadius))
            let y = Int(floor(centerY + sin(angle) * radius * pixelRadius))
            guard (0..<image.width).contains(x), (0..<image.height).contains(y) else {
                inFrame = false
                continue
            }
            let alphaX = Int(floor(alphaCenterX + cos(angle) * radius * pixelRadius))
            let alphaY = Int(floor(alphaCenterY + sin(angle) * radius * pixelRadius))
            let owned = (0..<alpha.width).contains(alphaX)
                && (0..<alpha.height).contains(alphaY)
                && alpha.pixel(x: alphaX, y: alphaY).alphaByte > 0
            samples.append((
                owned: owned,
                contrast: rgbDistance(image.pixel(x: x, y: y).straight, backgroundRGB)
            ))
        }
        guard inFrame else { continue }
        eligibleRays += 1
        let support = samples.map { $0.owned && $0.contrast >= 0.075 }
        if fixture11LongestRun(support) >= 2 {
            supportedRays += 1
            contrasts.append(contentsOf: samples.compactMap {
                $0.owned && $0.contrast >= 0.075 ? $0.contrast : nil
            })
        }
    }
    return Fixture11IsolatedIdentityMetrics(
        eligibleRays: eligibleRays,
        supportedRays: supportedRays,
        percentile90Contrast: percentile(contrasts.sorted(), fraction: 0.90)
    )
}

private func fixture11Resized(
    _ image: PixelImage,
    width: Int,
    height: Int
) throws -> PixelImage {
    let provider = try #require(CGDataProvider(data: image.rgba as CFData))
    let source = try #require(CGImage(
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    ))
    var rgba = Data(count: width * height * 4)
    let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    #expect(rendered)
    return PixelImage(width: width, height: height, rgba: rgba)
}

private func fixture11AlphaBytes(_ image: PixelImage) -> [UInt8] {
    stride(from: 3, to: image.rgba.count, by: 4).map { image.rgba[$0] }
}

private func fixture11DifferenceBounds(_ image: PixelImage, _ removed: PixelImage) -> [Int] {
    precondition(image.width == removed.width && image.height == removed.height)
    var minimumX = image.width
    var minimumY = image.height
    var maximumX = -1
    var maximumY = -1
    for y in 0..<image.height {
        for x in 0..<image.width {
            let pixel = image.pixel(x: x, y: y)
            let counterfactual = removed.pixel(x: x, y: y)
            guard pixel.redByte != counterfactual.redByte
                || pixel.greenByte != counterfactual.greenByte
                || pixel.blueByte != counterfactual.blueByte
            else { continue }
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }
    }
    return [minimumX, minimumY, maximumX, maximumY]
}

private func fixture11SolidPixel(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    alpha: UInt8
) -> PixelImage {
    PixelImage(width: 1, height: 1, rgba: Data([red, green, blue, alpha]))
}

private struct Fixture11OutlinePresentationMetrics: CustomStringConvertible {
    let eligibleRays: Int
    let identitySupportedRays: Int
    let percentile90Contrast: Double
    let composedOwnedCoverage: Double
    let rawComposedCoverage: Double

    var identityCoverage: Double {
        Double(identitySupportedRays) / Double(max(eligibleRays, 1))
    }

    var description: String {
        "eligible=\(eligibleRays), identity=\(identityCoverage), p90=\(percentile90Contrast), "
            + "composedOwned=\(composedOwnedCoverage), rawComposed=\(rawComposedCoverage)"
    }
}

private func fixture11OutlinePresentationMetrics(
    alpha: PixelImage,
    isolated: PixelImage,
    composed: PixelImage,
    actor: ActorCompositionRecipe,
    background: BackgroundCondition
) -> Fixture11OutlinePresentationMetrics {
    let backgroundColor = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: backgroundColor.red,
        g: backgroundColor.green,
        b: backgroundColor.blue
    )
    let centerX = actor.position.x * 393
    let centerY = actor.position.y * 852
    let pixelRadius = actor.diameter * 393 * 0.48
    let alphaCenterX = Double(alpha.width) * 0.5
    let alphaCenterY = Double(alpha.height) * 0.5
    let radialSteps = max(1, Int(ceil((1.08 - 0.52) * pixelRadius)))
    var eligibleRays = 0
    var identitySupported = 0
    var composedOwnedSupported = 0
    var rawComposedSupported = 0
    var isolatedContrasts = [Double]()

    for angleIndex in 0..<96 {
        let angle = Double(angleIndex) / 96 * Double.pi * 2
        var samples = [(alpha: Double, isolated: Double, composed: Double)]()
        var inFrame = true
        for step in 0...radialSteps {
            let radius = 0.52 + Double(step) / pixelRadius
            let sceneX = Int((centerX + cos(angle) * radius * pixelRadius).rounded(.down))
            let sceneY = Int((centerY + sin(angle) * radius * pixelRadius).rounded(.down))
            guard (0..<isolated.width).contains(sceneX),
                  (0..<isolated.height).contains(sceneY)
            else {
                inFrame = false
                continue
            }
            let alphaX = Int((alphaCenterX + cos(angle) * radius * pixelRadius).rounded(.down))
            let alphaY = Int((alphaCenterY + sin(angle) * radius * pixelRadius).rounded(.down))
            let alphaValue = (0..<alpha.width).contains(alphaX) && (0..<alpha.height).contains(alphaY)
                ? alpha.pixel(x: alphaX, y: alphaY).alpha
                : 0
            samples.append((
                alpha: alphaValue,
                isolated: rgbDistance(isolated.pixel(x: sceneX, y: sceneY).straight, backgroundRGB),
                composed: rgbDistance(composed.pixel(x: sceneX, y: sceneY).straight, backgroundRGB)
            ))
        }
        guard inFrame else { continue }
        eligibleRays += 1
        // Isolated same-scale pixels are the material-identity authority.
        // Structural alpha proves actor ownership; composed RGB is metadata
        // only and cannot create or erase isolated continuity.
        let identityRun = fixture11LongestRun(samples.map {
            $0.alpha >= 1.0 / 255.0 && $0.isolated >= 0.075
        })
        let composedOwnedRun = fixture11LongestRun(samples.map {
            $0.alpha >= 1.0 / 255.0 && $0.composed >= 0.075
        })
        let rawComposedRun = fixture11LongestRun(samples.map { $0.composed >= 0.075 })
        if identityRun >= 2 {
            identitySupported += 1
            isolatedContrasts.append(contentsOf: samples.compactMap {
                $0.alpha >= 1.0 / 255.0 && $0.isolated >= 0.075 ? $0.isolated : nil
            })
        }
        if composedOwnedRun >= 2 { composedOwnedSupported += 1 }
        if rawComposedRun >= 2 { rawComposedSupported += 1 }
    }

    return Fixture11OutlinePresentationMetrics(
        eligibleRays: eligibleRays,
        identitySupportedRays: identitySupported,
        percentile90Contrast: percentile(isolatedContrasts.sorted(), fraction: 0.90),
        composedOwnedCoverage: Double(composedOwnedSupported) / Double(max(eligibleRays, 1)),
        rawComposedCoverage: Double(rawComposedSupported) / Double(max(eligibleRays, 1))
    )
}

private func fixture11LongestRun(_ values: [Bool]) -> Int {
    var longest = 0
    var current = 0
    for value in values {
        current = value ? current + 1 : 0
        longest = max(longest, current)
    }
    return longest
}

private func fixture11AlphaHistogram(_ values: [UInt8]) -> [Int] {
    var histogram = [Int](repeating: 0, count: 256)
    for value in values { histogram[Int(value)] += 1 }
    return histogram
}

private func fixture11AlphaQuantiles(_ values: [UInt8]) -> [UInt8] {
    let sorted = values.sorted()
    return [0.0, 0.10, 0.50, 0.90, 1.0].map { fraction in
        sorted[Int(Double(sorted.count - 1) * fraction)]
    }
}

private func fixture11CompositedDistance(
    _ color: MaterialColor,
    alpha: Double,
    background: MaterialColor
) -> Double {
    let red = background.red + (color.red - background.red) * alpha
    let green = background.green + (color.green - background.green) * alpha
    let blue = background.blue + (color.blue - background.blue) * alpha
    return hypot(
        red - background.red,
        hypot(green - background.green, blue - background.blue)
    )
}

private func fixture11ProjectionCrossMagnitude(
    color: MaterialColor,
    target: MaterialColor,
    background: MaterialColor
) -> Double {
    let ax = color.red - background.red
    let ay = color.green - background.green
    let az = color.blue - background.blue
    let bx = target.red - background.red
    let by = target.green - background.green
    let bz = target.blue - background.blue
    return hypot(
        ay * bz - az * by,
        hypot(az * bx - ax * bz, ax * by - ay * bx)
    )
}

private func fixture11BrokenArcMutation(_ image: PixelImage) -> PixelImage {
    var rgba = image.rgba
    let centerX = Double(image.width) * 0.5
    let centerY = Double(image.height) * 0.5
    for y in 0..<image.height {
        for x in 0..<image.width {
            let angle = atan2(Double(y) + 0.5 - centerY, Double(x) + 0.5 - centerX)
            guard abs(angle) < Double.pi * 0.34 else { continue }
            let offset = (y * image.width + x) * 4
            rgba[offset] = 0
            rgba[offset + 1] = 0
            rgba[offset + 2] = 0
            rgba[offset + 3] = 0
        }
    }
    return PixelImage(width: image.width, height: image.height, rgba: rgba)
}

private func fixture11ArcColorMutation(
    _ image: PixelImage,
    actor: ActorCompositionRecipe,
    color: MaterialColor
) -> PixelImage {
    var rgba = image.rgba
    let centerX = actor.position.x * 393
    let centerY = actor.position.y * 852
    let pixelRadius = actor.diameter * 393 * 0.48
    for y in 0..<image.height {
        for x in 0..<image.width {
            let dx = Double(x) + 0.5 - centerX
            let dy = Double(y) + 0.5 - centerY
            let radius = hypot(dx, dy) / max(pixelRadius, 1)
            let angle = atan2(dy, dx)
            guard (0.52...1.08).contains(radius), abs(angle) < Double.pi * 0.34 else { continue }
            let offset = (y * image.width + x) * 4
            rgba[offset] = UInt8((color.red * 255).rounded())
            rgba[offset + 1] = UInt8((color.green * 255).rounded())
            rgba[offset + 2] = UInt8((color.blue * 255).rounded())
            rgba[offset + 3] = 255
        }
    }
    return PixelImage(width: image.width, height: image.height, rgba: rgba)
}

private enum SealedMaterialView: String, CaseIterable, Hashable {
    case full
    case tile
    case actor
    case exact
}

private struct SealedMaterialKey: Hashable {
    let colorCount: Int
    let background: BackgroundCondition
    let family: MaterialFamily
    let view: SealedMaterialView
}

private struct MistTextureMetrics: CustomStringConvertible {
    let fineEnergy: Double
    let maximumAxisAutocorrelation: Double
    let coarseAxisSpectrumFraction: Double
    let maximumAxisSpectrumBinFraction: Double

    var description: String {
        "energy=\(fineEnergy) autocorrelation=\(maximumAxisAutocorrelation) "
            + "coarseSpectrum=\(coarseAxisSpectrumFraction) "
            + "axisPeak=\(maximumAxisSpectrumBinFraction)"
    }
}

private func mistCanonicalSeedDigest(_ material: ActorMaterialRecipe) -> String {
    sha256Hex(mistCanonicalSeedBytes(material))
}

private func mistCanonicalSeedBytes(_ material: ActorMaterialRecipe) -> Data {
    var bytes = Data("editorial-mist-grain-seed-v1\0".utf8)

    func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
    func appendString(_ value: String) {
        let encoded = Data(value.utf8)
        appendUInt32(UInt32(encoded.count))
        bytes.append(encoded)
    }
    func appendDouble(_ value: Double) {
        let canonical = value == 0 ? 0.0 : value
        var bigEndian = canonical.bitPattern.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }

    appendString(material.family.rawValue)
    appendUInt32(UInt32(material.colors.count))
    for color in material.colors {
        appendDouble(color.red)
        appendDouble(color.green)
        appendDouble(color.blue)
    }
    appendUInt32(UInt32(material.fields.count))
    for field in material.fields {
        appendDouble(field.focus.x)
        appendDouble(field.focus.y)
        appendDouble(field.radius)
        appendDouble(field.softness)
        appendDouble(field.opacity)
        appendUInt32(UInt32(field.colorIndex))
        appendString(field.blend.rawValue)
    }
    appendDouble(material.baseOpacity)
    appendDouble(material.edgeSoftness)
    return bytes
}

private func mistFineGrainPasses(_ metrics: MistTextureMetrics) -> Bool {
    metrics.fineEnergy >= 0.0025
        && metrics.maximumAxisAutocorrelation <= 0.45
        && metrics.coarseAxisSpectrumFraction <= 0.62
        && metrics.maximumAxisSpectrumBinFraction <= 0.14
}

private struct MistRadialColorFixture {
    let pixels: [OutlineVisibilityPixel]
    let radialColors: [MaterialColor]
}

private func mistRadialColorFixture(
    side: Int,
    background: MaterialColor
) -> MistRadialColorFixture {
    let inner = MaterialColor(red: 0.92, green: 0.24, blue: 0.38)
    let outer = MaterialColor(red: 0.14, green: 0.58, blue: 0.94)
    var pixels = [OutlineVisibilityPixel]()
    var radialColors = [MaterialColor]()
    pixels.reserveCapacity(side * side)
    radialColors.reserveCapacity(side * side)
    for y in 0..<side {
        for x in 0..<side {
            let dx = (Double(x) + 0.5) / Double(side) - 0.5
            let dy = (Double(y) + 0.5) / Double(side) - 0.5
            let radius = hypot(dx, dy) / 0.5
            let radialWeight = min(1, max(0, (radius - 0.12) / 0.76))
            let color = MaterialColor(
                red: inner.red + (outer.red - inner.red) * radialWeight,
                green: inner.green + (outer.green - inner.green) * radialWeight,
                blue: inner.blue + (outer.blue - inner.blue) * radialWeight
            )
            let alpha = radius < 0.94
                ? UInt8((255 * min(1, max(0, (0.94 - radius) / 0.16))).rounded())
                : 0
            let a = Double(alpha) / 255
            radialColors.append(color)
            pixels.append(OutlineVisibilityPixel(
                red: UInt8((color.red * a * 255).rounded()),
                green: UInt8((color.green * a * 255).rounded()),
                blue: UInt8((color.blue * a * 255).rounded()),
                alpha: alpha
            ))
        }
    }
    _ = background
    return MistRadialColorFixture(pixels: pixels, radialColors: radialColors)
}

private func mistIsotropicFineField(
    side: Int,
    presentationScale: Int,
    actorID: String,
    alpha: [UInt8],
    siblingEventIDs: [String] = []
) -> [Double] {
    precondition(side > 0 && presentationScale > 0 && alpha.count == side * side)
    // Actor identity is the only seed authority. Sibling presence/order is
    // deliberately accepted but excluded from the field seed.
    _ = siblingEventIDs
    let seed = actorID.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) {
        ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3
    }
    let finalSide = side / presentationScale
    var final = [Double]()
    final.reserveCapacity(finalSide * finalSide)
    for y in 0..<finalSide {
        for x in 0..<finalSide {
            var value = seed
            value ^= UInt64(x) &* 0x9E37_79B9_7F4A_7C15
            value ^= UInt64(y) &* 0xD1B5_4A32_D192_ED03
            value ^= value >> 30
            value &*= 0xBF58_476D_1CE4_E5B9
            value ^= value >> 27
            value &*= 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            final.append(Double(value & 0xFFFF) / 32_767.5 - 1)
        }
    }
    var expanded = [Double](repeating: 0, count: side * side)
    for y in 0..<side {
        for x in 0..<side {
            expanded[y * side + x] = final[(y / presentationScale) * finalSide + x / presentationScale]
        }
    }
    let weighted = zip(expanded, alpha).reduce(into: (sum: 0.0, weight: 0.0)) { result, sample in
        let weight = Double(sample.1) / 255
        result.sum += sample.0 * weight
        result.weight += weight
    }
    let mean = weighted.sum / max(weighted.weight, Double.ulpOfOne)
    return expanded.map { $0 - mean }
}

private func mistRayGrainWitness(
    _ pixels: [OutlineVisibilityPixel],
    radialColors: [MaterialColor],
    field: [Double],
    background: MaterialColor
) -> [OutlineVisibilityPixel] {
    precondition(pixels.count == radialColors.count && pixels.count == field.count)
    return zip(zip(pixels, radialColors), field).map { pair, grain in
        let pixel = pair.0
        let color = pair.1
        guard pixel.alpha > 0 else { return pixel }
        let direction = (
            color.red - background.red,
            color.green - background.green,
            color.blue - background.blue
        )
        var maximum = Double.greatestFiniteMagnitude
        for component in [direction.0, direction.1, direction.2] where abs(component) > 0.000_001 {
            let origin = component == direction.0 ? background.red
                : component == direction.1 ? background.green : background.blue
            maximum = min(maximum, component > 0 ? (1 - origin) / component : -origin / component)
        }
        let amount = min(maximum, max(0, 1 + grain * 0.12))
        let projected = MaterialColor(
            red: background.red + direction.0 * amount,
            green: background.green + direction.1 * amount,
            blue: background.blue + direction.2 * amount
        )
        let alpha = Double(pixel.alpha) / 255
        return OutlineVisibilityPixel(
            red: UInt8((projected.red * alpha * 255).rounded()),
            green: UInt8((projected.green * alpha * 255).rounded()),
            blue: UInt8((projected.blue * alpha * 255).rounded()),
            alpha: pixel.alpha
        )
    }
}

private func mistAlphaWeightedDC(_ field: [Double], alpha: [UInt8]) -> Double {
    let weighted = zip(field, alpha).reduce(into: (sum: 0.0, weight: 0.0)) { result, sample in
        let weight = Double(sample.1) / 255
        result.sum += sample.0 * weight
        result.weight += weight
    }
    return weighted.sum / max(weighted.weight, Double.ulpOfOne)
}

private func mistAllSamplesRemainOnRadialRay(
    original: [OutlineVisibilityPixel],
    candidate: [OutlineVisibilityPixel],
    radialColors: [MaterialColor],
    background: MaterialColor
) -> Bool {
    zip(zip(original, candidate), radialColors).allSatisfy { pair, radial in
        let before = pair.0
        let after = pair.1
        guard before.alpha >= 16 else { return after.alpha == before.alpha }
        let alpha = Double(after.alpha) / 255
        let observed = MaterialColor(
            red: Double(after.red) / 255 / alpha,
            green: Double(after.green) / 255 / alpha,
            blue: Double(after.blue) / 255 / alpha
        )
        let direction = (
            radial.red - background.red,
            radial.green - background.green,
            radial.blue - background.blue
        )
        let offset = (
            observed.red - background.red,
            observed.green - background.green,
            observed.blue - background.blue
        )
        let cross = hypot(
            offset.1 * direction.2 - offset.2 * direction.1,
            hypot(
                offset.2 * direction.0 - offset.0 * direction.2,
                offset.0 * direction.1 - offset.1 * direction.0
            )
        )
        let quantization = sqrt(3) * 0.5 / Double(after.alpha)
        return after.alpha == before.alpha && cross <= quantization * 1.75
    }
}

private func mistDirectionalEnergySpread(_ field: [Double], side: Int) -> Double {
    precondition(field.count == side * side)
    let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
    let energies = directions.map { dx, dy in
        var energy = 0.0
        var count = 0
        for y in 0..<side {
            for x in 0..<side {
                let sx = x + dx
                let sy = y + dy
                guard (0..<side).contains(sx), (0..<side).contains(sy) else { continue }
                let delta = field[sy * side + sx] - field[y * side + x]
                // A one-pixel lattice step in any sampled direction is the
                // presentation observable; diagonal energy is not divided by
                // Euclidean distance because that would make isotropic white
                // detail appear artificially axis-heavy by construction.
                energy += delta * delta
                count += 1
            }
        }
        return energy / Double(max(count, 1))
    }
    let mean = energies.reduce(0, +) / Double(energies.count)
    return ((energies.max() ?? 0) - (energies.min() ?? 0)) / max(mean, Double.ulpOfOne)
}

private func mistRotatedQuarterTurn(_ field: [Double], side: Int) -> [Double] {
    var rotated = [Double](repeating: 0, count: field.count)
    for y in 0..<side {
        for x in 0..<side {
            rotated[x * side + (side - 1 - y)] = field[y * side + x]
        }
    }
    return rotated
}

private func mistUpsampledAlpha(_ alpha: [UInt8], side: Int, scale: Int) -> [UInt8] {
    precondition(alpha.count == side * side)
    let resultSide = side * scale
    return (0..<(resultSide * resultSide)).map { index in
        let x = index % resultSide
        let y = index / resultSide
        return alpha[(y / scale) * side + x / scale]
    }
}

private func mistDownsampledField(_ field: [Double], side: Int, scale: Int) -> [Double] {
    precondition(field.count == side * side && side.isMultiple(of: scale))
    let resultSide = side / scale
    return (0..<(resultSide * resultSide)).map { index in
        let x = index % resultSide
        let y = index / resultSide
        var sum = 0.0
        for oy in 0..<scale {
            for ox in 0..<scale {
                sum += field[(y * scale + oy) * side + x * scale + ox]
            }
        }
        return sum / Double(scale * scale)
    }
}

private func mistTextureMetrics(
    image: PixelImage,
    centerX: Double,
    centerY: Double,
    diameter: Double,
    background: BackgroundCondition
) -> MistTextureMetrics {
    let side = min(64, max(16, Int(floor(diameter * 0.42))))
    let originX = min(
        image.width - side,
        max(0, Int(floor(centerX - Double(side) * 0.5)))
    )
    let originY = min(
        image.height - side,
        max(0, Int(floor(centerY - Double(side) * 0.5)))
    )
    var colors = [StraightRGB]()
    colors.reserveCapacity(side * side)
    for y in originY..<(originY + side) {
        for x in originX..<(originX + side) {
            colors.append(image.pixel(x: x, y: y).straight)
        }
    }
    let materialBackground = MaterialRenderer.backgroundColor(for: background)
    let backgroundColor = StraightRGB(
        r: materialBackground.red,
        g: materialBackground.green,
        b: materialBackground.blue
    )
    let smoothingRadius = max(2, min(4, side / 12))
    var residual = [Double](repeating: 0, count: colors.count)
    for y in 0..<side {
        for x in 0..<side {
            var localRed = 0.0
            var localGreen = 0.0
            var localBlue = 0.0
            var count = 0
            for sampleY in max(0, y - smoothingRadius)...min(side - 1, y + smoothingRadius) {
                for sampleX in max(0, x - smoothingRadius)...min(side - 1, x + smoothingRadius) {
                    let sample = colors[sampleY * side + sampleX]
                    localRed += sample.r
                    localGreen += sample.g
                    localBlue += sample.b
                    count += 1
                }
            }
            let inverseCount = 1 / Double(max(count, 1))
            let local = StraightRGB(
                r: localRed * inverseCount,
                g: localGreen * inverseCount,
                b: localBlue * inverseCount
            )
            let direction = (
                local.r - backgroundColor.r,
                local.g - backgroundColor.g,
                local.b - backgroundColor.b
            )
            let length = hypot(direction.0, hypot(direction.1, direction.2))
            guard length > 1.0 / 255 else { continue }
            let current = colors[y * side + x]
            residual[y * side + x] = (
                (current.r - local.r) * direction.0
                    + (current.g - local.g) * direction.1
                    + (current.b - local.b) * direction.2
            ) / length
        }
    }
    return mistTextureMetrics(residual: residual, side: side)
}

private func mistTextureMetrics(
    luminance: [Double],
    side: Int
) -> MistTextureMetrics {
    precondition(luminance.count == side * side)
    let smoothingRadius = max(2, min(4, side / 12))
    var residual = Array(repeating: 0.0, count: luminance.count)
    for y in 0..<side {
        for x in 0..<side {
            var local = 0.0
            var count = 0
            for sampleY in max(0, y - smoothingRadius)...min(side - 1, y + smoothingRadius) {
                for sampleX in max(0, x - smoothingRadius)...min(side - 1, x + smoothingRadius) {
                    local += luminance[sampleY * side + sampleX]
                    count += 1
                }
            }
            residual[y * side + x] = luminance[y * side + x] - local / Double(count)
        }
    }
    return mistTextureMetrics(residual: residual, side: side)
}

private func mistTextureMetrics(
    residual inputResidual: [Double],
    side: Int
) -> MistTextureMetrics {
    precondition(inputResidual.count == side * side)
    let mean = inputResidual.reduce(0, +) / Double(max(inputResidual.count, 1))
    let residual = inputResidual.map { $0 - mean }
    let fineEnergy = residual.map(abs).reduce(0, +) / Double(max(residual.count, 1))

    func correlation(dx: Int, dy: Int) -> (value: Double, pairCount: Int) {
        var covariance = 0.0
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        var count = 0
        for y in 0..<(side - dy) {
            for x in 0..<(side - dx) {
                let lhs = residual[y * side + x]
                let rhs = residual[(y + dy) * side + x + dx]
                covariance += lhs * rhs
                lhsEnergy += lhs * lhs
                rhsEnergy += rhs * rhs
                count += 1
            }
        }
        guard count > 0, lhsEnergy > 0, rhsEnergy > 0 else { return (1, count) }
        return (covariance / sqrt(lhsEnergy * rhsEnergy), count)
    }
    let maximumLag = max(1, min(4, side / 8))
    let maximumAxisAutocorrelation = (1...maximumLag).flatMap { lag in
        [correlation(dx: lag, dy: 0), correlation(dx: 0, dy: lag)]
    }.map { sample in
        mistFamilyWiseAutocorrelationLowerBound(
            sample.value,
            pairCount: sample.pairCount,
            comparisonCount: maximumLag * 2
        )
    }.max() ?? 1

    let half = side / 2
    var axisPower = Array(repeating: 0.0, count: half + 1)
    var diagonalPower = Array(repeating: 0.0, count: half + 1)
    guard half >= 2 else {
        return MistTextureMetrics(
            fineEnergy: fineEnergy,
            maximumAxisAutocorrelation: maximumAxisAutocorrelation,
            coarseAxisSpectrumFraction: 1,
            maximumAxisSpectrumBinFraction: 1
        )
    }
    for fixed in 0..<side {
        for frequency in 1...half {
            var rowReal = 0.0
            var rowImaginary = 0.0
            var columnReal = 0.0
            var columnImaginary = 0.0
            var risingReal = 0.0
            var risingImaginary = 0.0
            var fallingReal = 0.0
            var fallingImaginary = 0.0
            for offset in 0..<side {
                let angle = Double.pi * 2 * Double(frequency * offset) / Double(side)
                let cosine = cos(angle)
                let sine = sin(angle)
                let rowValue = residual[fixed * side + offset]
                let columnValue = residual[offset * side + fixed]
                rowReal += rowValue * cosine
                rowImaginary -= rowValue * sine
                columnReal += columnValue * cosine
                columnImaginary -= columnValue * sine
                let risingValue = residual[((fixed + offset) % side) * side + offset]
                let fallingValue = residual[((fixed - offset + side) % side) * side + offset]
                risingReal += risingValue * cosine
                risingImaginary -= risingValue * sine
                fallingReal += fallingValue * cosine
                fallingImaginary -= fallingValue * sine
            }
            axisPower[frequency] += rowReal * rowReal + rowImaginary * rowImaginary
                + columnReal * columnReal + columnImaginary * columnImaginary
            diagonalPower[frequency] += risingReal * risingReal + risingImaginary * risingImaginary
                + fallingReal * fallingReal + fallingImaginary * fallingImaginary
        }
    }
    let totalPower = max(
        axisPower[1...half].reduce(0, +) + diagonalPower[1...half].reduce(0, +),
        0.000_000_001
    )
    let coarseFrequencies = (1...half).filter { frequency in
        let period = Double(side) / Double(frequency)
        return (4...16).contains(period)
    }
    let coarseAxis = coarseFrequencies.map { axisPower[$0] }.reduce(0, +)
    let coarseDiagonal = coarseFrequencies.map { diagonalPower[$0] }.reduce(0, +)
    let coarseAxisExcess = max(0, coarseAxis - coarseDiagonal)
        / max(coarseAxis + coarseDiagonal, 0.000_000_001)
    let maximumAxisBinExcess = (1...half).map { frequency in
        max(0, axisPower[frequency] - diagonalPower[frequency]) / totalPower
    }.max() ?? 0
    return MistTextureMetrics(
        fineEnergy: fineEnergy,
        maximumAxisAutocorrelation: maximumAxisAutocorrelation,
        coarseAxisSpectrumFraction: coarseAxisExcess,
        maximumAxisSpectrumBinFraction: maximumAxisBinExcess
    )
}

private func mistFamilyWiseAutocorrelationLowerBound(
    _ correlation: Double,
    pairCount: Int,
    comparisonCount: Int
) -> Double {
    guard pairCount > 3, comparisonCount > 0 else { return 1 }
    let targetProbability = 1 - 0.05 / Double(comparisonCount)
    var lowerZ = 0.0
    var upperZ = 8.0
    for _ in 0..<64 {
        let candidate = (lowerZ + upperZ) * 0.5
        let probability = 0.5 * (1 + erf(candidate / sqrt(2)))
        if probability < targetProbability {
            lowerZ = candidate
        } else {
            upperZ = candidate
        }
    }
    let criticalZ = (lowerZ + upperZ) * 0.5
    let bounded = min(1 - Double.ulpOfOne, max(-1 + Double.ulpOfOne, correlation))
    return tanh(atanh(bounded) - criticalZ / sqrt(Double(pairCount - 3)))
}

private func mistFineStableControl(side: Int) -> [Double] {
    (0..<(side * side)).map { index in
        let x = index % side
        let y = index / side
        var value = UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        let noise = Double(value & 0xFFFF) / 65_535 - 0.5
        let radial = hypot(
            (Double(x) + 0.5) / Double(side) - 0.5,
            (Double(y) + 0.5) / Double(side) - 0.5
        )
        return 0.54 - radial * 0.035 + noise * 0.070
    }
}

private func mistBrokenGrainMutation(_ luminance: [Double]) -> [Double] {
    Array(repeating: luminance.reduce(0, +) / Double(max(luminance.count, 1)), count: luminance.count)
}

private func mistCoarseCellMutation(
    _ luminance: [Double],
    side: Int,
    cellSide: Int
) -> [Double] {
    precondition(luminance.count == side * side)
    var result = luminance
    for cellY in stride(from: 0, to: side, by: cellSide) {
        for cellX in stride(from: 0, to: side, by: cellSide) {
            let maxY = min(side, cellY + cellSide)
            let maxX = min(side, cellX + cellSide)
            var sum = 0.0
            var count = 0
            for y in cellY..<maxY {
                for x in cellX..<maxX {
                    sum += luminance[y * side + x]
                    count += 1
                }
            }
            let value = sum / Double(max(count, 1))
            for y in cellY..<maxY {
                for x in cellX..<maxX {
                    result[y * side + x] = value
                }
            }
        }
    }
    return result
}

private func mistCheckerMutation(
    _ luminance: [Double],
    side: Int,
    cellSide: Int
) -> [Double] {
    precondition(luminance.count == side * side)
    let mean = luminance.reduce(0, +) / Double(max(luminance.count, 1))
    return (0..<(side * side)).map { index in
        let x = index % side
        let y = index / side
        let parity = (x / cellSide + y / cellSide).isMultiple(of: 2)
        return mean + (parity ? 0.045 : -0.045)
    }
}

private struct MistBackgroundCleanliness {
    let eligible: Int
    let contaminated: Int
}

private func mistBackgroundCleanliness(
    _ image: PixelImage,
    centerX: Double,
    centerY: Double,
    diameter: Double,
    localBlur: Double,
    background: BackgroundCondition
) -> MistBackgroundCleanliness {
    let color = MaterialRenderer.backgroundColor(for: background)
    let expected = StraightRGB(r: color.red, g: color.green, b: color.blue)
    let supportRadius = diameter * 0.5 + max(3, localBlur * 393 * 3)
    var eligible = 0
    var contaminated = 0
    for gridY in 0...8 {
        for gridX in 0...8 {
            let x = Int((Double(gridX) / 8 * Double(image.width - 1)).rounded())
            let y = Int((Double(gridY) / 8 * Double(image.height - 1)).rounded())
            guard hypot(Double(x) - centerX, Double(y) - centerY) > supportRadius else {
                continue
            }
            eligible += 1
            if rgbDistance(image.pixel(x: x, y: y).straight, expected) > 1.5 / 255 {
                contaminated += 1
            }
        }
    }
    return MistBackgroundCleanliness(eligible: eligible, contaminated: contaminated)
}

private func mistRadialEdgeSharpness(
    _ image: PixelImage,
    centerX: Double,
    centerY: Double,
    diameter: Double,
    background: BackgroundCondition
) -> Double {
    let color = MaterialRenderer.backgroundColor(for: background)
    let expected = StraightRGB(r: color.red, g: color.green, b: color.blue)
    var rayPeaks = [Double]()
    for ray in 0..<72 {
        let angle = Double(ray) / 72 * Double.pi * 2
        var previous: Double?
        var peak = 0.0
        for step in 0...32 {
            let radius = diameter * (0.30 + Double(step) / 32 * 0.36)
            let x = min(image.width - 1, max(0, Int((centerX + cos(angle) * radius).rounded())))
            let y = min(image.height - 1, max(0, Int((centerY + sin(angle) * radius).rounded())))
            let contrast = rgbDistance(image.pixel(x: x, y: y).straight, expected)
            if let previous { peak = max(peak, abs(contrast - previous)) }
            previous = contrast
        }
        rayPeaks.append(peak)
    }
    return percentile(rayPeaks, fraction: 0.50)
}

private struct HaloMatrixKey: Hashable {
    let fixture: Int
    let eventID: String
    let background: BackgroundCondition
    let family: MaterialFamily
    let view: SealedMaterialView
}

private struct HaloBodyAuraMetrics {
    let bodyP50: Double
    let auraP50: Double
    let auraP75: Double
    let auraAngularCoverage: Double
    let bodyChromaP50: Double
}

private struct HaloNucleusContinuityMetrics: CustomStringConvertible {
    let nucleusContrastP50: Double
    let nucleusChromaP50: Double
    let nucleusAuraDeltaP50: Double
    let boundaryStepRatioP75: Double
    let innerRadiusVariationConcentrationP75: Double
    let ridgeAngularCoverage: Double

    var description: String {
        "nucleusContrast=\(nucleusContrastP50) nucleusChroma=\(nucleusChromaP50) "
            + "nucleusAuraDelta=\(nucleusAuraDeltaP50) "
            + "boundaryStepRatio=\(boundaryStepRatioP75) "
            + "innerRadiusConcentration=\(innerRadiusVariationConcentrationP75) "
            + "ridgeCoverage=\(ridgeAngularCoverage)"
    }
}

private func haloNucleusContinuityPasses(_ metrics: HaloNucleusContinuityMetrics) -> Bool {
    metrics.nucleusContrastP50 >= 0.14
        && metrics.nucleusChromaP50 >= 0.10
        && metrics.nucleusAuraDeltaP50 >= 0.055
        && metrics.boundaryStepRatioP75 <= 0.52
        && metrics.innerRadiusVariationConcentrationP75 <= 0.44
        && metrics.ridgeAngularCoverage <= 0.42
}

private func haloNucleusContinuityMetrics(
    _ image: PixelImage,
    nucleusCenterX: Double,
    nucleusCenterY: Double,
    innerRadius: Double,
    background: BackgroundCondition
) -> HaloNucleusContinuityMetrics {
    let materialBackground = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: materialBackground.red,
        g: materialBackground.green,
        b: materialBackground.blue
    )
    var nucleusContrasts = [Double]()
    var nucleusChromas = [Double]()
    var nucleusAuraDeltas = [Double]()
    var boundaryStepRatios = [Double]()
    var innerRadiusVariationConcentrations = [Double]()
    var ridgeCount = 0
    let rayCount = 96

    for ray in 0..<rayCount {
        let angle = Double(ray) / Double(rayCount) * Double.pi * 2
        let nucleus = haloBilinearSample(
            image,
            x: nucleusCenterX + cos(angle) * innerRadius * 0.34,
            y: nucleusCenterY + sin(angle) * innerRadius * 0.34
        )
        let insideBoundary = haloBilinearSample(
            image,
            x: nucleusCenterX + cos(angle) * innerRadius * 0.82,
            y: nucleusCenterY + sin(angle) * innerRadius * 0.82
        )
        let outsideBoundary = haloBilinearSample(
            image,
            x: nucleusCenterX + cos(angle) * innerRadius * 1.18,
            y: nucleusCenterY + sin(angle) * innerRadius * 1.18
        )
        let aura = haloBilinearSample(
            image,
            x: nucleusCenterX + cos(angle) * innerRadius * 1.55,
            y: nucleusCenterY + sin(angle) * innerRadius * 1.55
        )
        let fullDelta = rgbDistance(nucleus, aura)
        let boundaryStep = rgbDistance(insideBoundary, outsideBoundary)
        let ratio = boundaryStep / max(fullDelta, 0.000_001)
        let radialProfile = (0...28).map { step in
            let radius = innerRadius * (0.30 + Double(step) * 0.05)
            return haloBilinearSample(
                image,
                x: nucleusCenterX + cos(angle) * radius,
                y: nucleusCenterY + sin(angle) * radius
            )
        }
        let radialVariation = zip(radialProfile, radialProfile.dropFirst()).enumerated().map {
            index, pair in
            (
                midpoint: 0.325 + Double(index) * 0.05,
                delta: rgbDistance(pair.0, pair.1)
            )
        }
        let totalVariation = radialVariation.map(\.delta).reduce(0, +)
        let innerRadiusVariation = radialVariation.filter {
            (0.725...1.075).contains($0.midpoint)
        }.map(\.delta).reduce(0, +)
        nucleusContrasts.append(rgbDistance(nucleus, backgroundRGB))
        nucleusChromas.append(nucleus.chroma)
        nucleusAuraDeltas.append(fullDelta)
        boundaryStepRatios.append(ratio)
        innerRadiusVariationConcentrations.append(
            innerRadiusVariation / max(totalVariation, 0.000_001)
        )
        if fullDelta >= 0.055, ratio > 0.52 { ridgeCount += 1 }
    }

    nucleusContrasts.sort()
    nucleusChromas.sort()
    nucleusAuraDeltas.sort()
    boundaryStepRatios.sort()
    innerRadiusVariationConcentrations.sort()
    return HaloNucleusContinuityMetrics(
        nucleusContrastP50: percentile(nucleusContrasts, fraction: 0.50),
        nucleusChromaP50: percentile(nucleusChromas, fraction: 0.50),
        nucleusAuraDeltaP50: percentile(nucleusAuraDeltas, fraction: 0.50),
        boundaryStepRatioP75: percentile(boundaryStepRatios, fraction: 0.75),
        innerRadiusVariationConcentrationP75: percentile(
            innerRadiusVariationConcentrations,
            fraction: 0.75
        ),
        ridgeAngularCoverage: Double(ridgeCount) / Double(rayCount)
    )
}

private func haloBilinearSample(_ image: PixelImage, x: Double, y: Double) -> StraightRGB {
    let clampedX = min(Double(image.width - 1), max(0, x - 0.5))
    let clampedY = min(Double(image.height - 1), max(0, y - 0.5))
    let x0 = Int(floor(clampedX))
    let y0 = Int(floor(clampedY))
    let x1 = min(image.width - 1, x0 + 1)
    let y1 = min(image.height - 1, y0 + 1)
    let tx = clampedX - Double(x0)
    let ty = clampedY - Double(y0)
    let top = haloMix(
        image.pixel(x: x0, y: y0).straight,
        image.pixel(x: x1, y: y0).straight,
        tx
    )
    let bottom = haloMix(
        image.pixel(x: x0, y: y1).straight,
        image.pixel(x: x1, y: y1).straight,
        tx
    )
    return haloMix(top, bottom, ty)
}

private func haloMix(_ lhs: StraightRGB, _ rhs: StraightRGB, _ amount: Double) -> StraightRGB {
    StraightRGB(
        r: lhs.r + (rhs.r - lhs.r) * amount,
        g: lhs.g + (rhs.g - lhs.g) * amount,
        b: lhs.b + (rhs.b - lhs.b) * amount
    )
}

private enum HaloNucleusContinuityControl {
    case broadTransition
    case sharpPastedDisc
    case missingNucleus
    case collapsedSingleBlur
}

private func haloNucleusContinuityControl(
    _ control: HaloNucleusContinuityControl
) -> HaloNucleusContinuityMetrics {
    let side = 161
    let center = Double(side) * 0.5
    let innerRadius = 28.0
    let background = MaterialRenderer.backgroundColor(for: .dark)
    let backgroundRGB = StraightRGB(r: background.red, g: background.green, b: background.blue)
    let auraRGB = StraightRGB(r: 0.16, g: 0.36, b: 0.42)
    let nucleusRGB = StraightRGB(r: 0.08, g: 0.82, b: 0.72)
    var rgba = Data(count: side * side * 4)
    for y in 0..<side {
        for x in 0..<side {
            let radius = hypot(Double(x) + 0.5 - center, Double(y) + 0.5 - center)
            let auraAmount = 0.34 + 0.40 * (1 - haloControlSmoothstep(
                lower: innerRadius * 1.8,
                upper: innerRadius * 2.8,
                value: radius
            ))
            let nucleusAmount: Double
            switch control {
            case .broadTransition:
                nucleusAmount = 1 - haloControlSmoothstep(
                    lower: innerRadius * 0.20,
                    upper: innerRadius * 1.80,
                    value: radius
                )
            case .sharpPastedDisc:
                nucleusAmount = radius < innerRadius ? 1 : 0
            case .missingNucleus:
                nucleusAmount = 0
            case .collapsedSingleBlur:
                nucleusAmount = 0.10 * (1 - haloControlSmoothstep(
                    lower: 0,
                    upper: innerRadius * 2.4,
                    value: radius
                ))
            }
            let auraColor = haloMix(backgroundRGB, auraRGB, auraAmount)
            let color = haloMix(auraColor, nucleusRGB, nucleusAmount * 0.76)
            let offset = (y * side + x) * 4
            rgba[offset] = UInt8((min(1, max(0, color.r)) * 255).rounded())
            rgba[offset + 1] = UInt8((min(1, max(0, color.g)) * 255).rounded())
            rgba[offset + 2] = UInt8((min(1, max(0, color.b)) * 255).rounded())
            rgba[offset + 3] = 255
        }
    }
    return haloNucleusContinuityMetrics(
        PixelImage(width: side, height: side, rgba: rgba),
        nucleusCenterX: center,
        nucleusCenterY: center,
        innerRadius: innerRadius,
        background: .dark
    )
}

private func haloBodyAuraPasses(_ metrics: HaloBodyAuraMetrics) -> Bool {
    metrics.bodyP50 >= 0.16
        && metrics.auraP75 >= 0.075
        && metrics.bodyP50 - metrics.auraP50 >= 0.06
        && metrics.auraAngularCoverage >= 0.75
        && metrics.bodyChromaP50 >= 0.10
}

private func haloBodyAuraMetrics(
    _ image: PixelImage,
    centerX: Double,
    centerY: Double,
    diameter: Double,
    material: ActorMaterialRecipe,
    background: BackgroundCondition
) -> HaloBodyAuraMetrics {
    guard let topology = material.organicTopology else {
        return HaloBodyAuraMetrics(
            bodyP50: 0,
            auraP50: 0,
            auraP75: 0,
            auraAngularCoverage: 0,
            bodyChromaP50: 0
        )
    }
    let backgroundColor = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: backgroundColor.red,
        g: backgroundColor.green,
        b: backgroundColor.blue
    )
    let bodyCenterX = centerX + (topology.innerCenter.x - 0.5) * diameter
    let bodyCenterY = centerY + (topology.innerCenter.y - 0.5) * diameter
    let auraCenterX = centerX + (topology.outerCenter.x - 0.5) * diameter
    let auraCenterY = centerY + (topology.outerCenter.y - 0.5) * diameter
    let bodyRadius = topology.innerRadius * diameter
    let auraRadius = topology.outerRadius * diameter
    var bodyContrasts = [Double]()
    var bodyChromas = [Double]()
    var auraContrasts = [Double]()
    let minX = max(0, Int(floor(auraCenterX - auraRadius)))
    let maxX = min(image.width - 1, Int(ceil(auraCenterX + auraRadius)))
    let minY = max(0, Int(floor(auraCenterY - auraRadius)))
    let maxY = min(image.height - 1, Int(ceil(auraCenterY + auraRadius)))
    for y in minY...maxY {
        for x in minX...maxX {
            let color = image.pixel(x: x, y: y).straight
            let contrast = rgbDistance(color, backgroundRGB)
            let bodyDistance = hypot(Double(x) - bodyCenterX, Double(y) - bodyCenterY)
            let auraDistance = hypot(Double(x) - auraCenterX, Double(y) - auraCenterY)
            if bodyDistance <= bodyRadius * 0.72 {
                bodyContrasts.append(contrast)
                bodyChromas.append(color.chroma)
            }
            if auraDistance >= auraRadius * 0.58,
               auraDistance <= auraRadius * 0.92,
               bodyDistance >= bodyRadius * 1.20 {
                auraContrasts.append(contrast)
            }
        }
    }
    bodyContrasts.sort()
    bodyChromas.sort()
    auraContrasts.sort()

    let rayCount = 72
    var supportedRays = 0
    for ray in 0..<rayCount {
        let angle = Double(ray) / Double(rayCount) * Double.pi * 2
        var longestRun = 0
        var currentRun = 0
        for step in 0..<8 {
            let radius = auraRadius * (0.58 + Double(step) * 0.05)
            let x = Int((auraCenterX + cos(angle) * radius).rounded())
            let y = Int((auraCenterY + sin(angle) * radius).rounded())
            guard (0..<image.width).contains(x), (0..<image.height).contains(y) else {
                currentRun = 0
                continue
            }
            let contrast = rgbDistance(image.pixel(x: x, y: y).straight, backgroundRGB)
            if contrast >= 0.05 {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        if longestRun >= 2 { supportedRays += 1 }
    }
    return HaloBodyAuraMetrics(
        bodyP50: percentile(bodyContrasts, fraction: 0.50),
        auraP50: percentile(auraContrasts, fraction: 0.50),
        auraP75: percentile(auraContrasts, fraction: 0.75),
        auraAngularCoverage: Double(supportedRays) / Double(rayCount),
        bodyChromaP50: percentile(bodyChromas, fraction: 0.50)
    )
}

private struct SealedOpticalSample {
    let gridX: Int
    let gridY: Int
    let normalizedX: Double
    let normalizedY: Double
    let color: StraightRGB
    let background: StraightRGB

    var radius: Double { hypot(normalizedX, normalizedY) }
    var contrast: Double { rgbDistance(color, background) }
}

private struct SealedOpticalSignature {
    let gridSide: Int
    let samples: [SealedOpticalSample]
    let pixelRadius: Double
    let contourRays: [[SealedOpticalSample]]
}

private struct SealedOpticalMetrics {
    let centerToRimRatio: Double
    let activeAreaFraction: Double
    let peakContrast: Double
    let meanChroma: Double
    let coreRange: Double
    let grainEnergy: Double
}

private struct SealedOutlineContinuity {
    let supportedAngularCoverage: Double
    let minimumNormalizedSupport: Double
}

private func actorPixelDiameter(_ actor: ActorCompositionRecipe) -> Int {
    max(1, Int(ceil(actor.diameter * 393)))
}

private func sealedSignature(
    _ image: PixelImage,
    centerX: Double,
    centerY: Double,
    radius: Double,
    background: BackgroundCondition,
    gridSide: Int = 33
) -> SealedOpticalSignature {
    let backgroundColor = MaterialRenderer.backgroundColor(for: background)
    let backgroundRGB = StraightRGB(
        r: backgroundColor.red,
        g: backgroundColor.green,
        b: backgroundColor.blue
    )
    var samples = [SealedOpticalSample]()
    samples.reserveCapacity(gridSide * gridSide)
    for gridY in 0..<gridSide {
        for gridX in 0..<gridSide {
            let normalizedX = (Double(gridX) / Double(gridSide - 1) * 2 - 1) * 1.04
            let normalizedY = (Double(gridY) / Double(gridSide - 1) * 2 - 1) * 1.04
            guard hypot(normalizedX, normalizedY) <= 1.04 else { continue }
            let x = min(image.width - 1, max(0, Int((centerX + normalizedX * radius).rounded())))
            let y = min(image.height - 1, max(0, Int((centerY + normalizedY * radius).rounded())))
            samples.append(SealedOpticalSample(
                gridX: gridX,
                gridY: gridY,
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                color: image.pixel(x: x, y: y).straight,
                background: backgroundRGB
            ))
        }
    }
    let rayCount = 96
    let radialStepCount = max(1, Int(ceil(radius * 0.52)))
    let contourRays = (0..<rayCount).map { angleIndex in
        let angle = Double(angleIndex) / Double(rayCount) * Double.pi * 2
        return (0...radialStepCount).map { radialIndex in
            let normalizedRadius = 0.52 + Double(radialIndex) / max(radius, 1)
            let normalizedX = cos(angle) * normalizedRadius
            let normalizedY = sin(angle) * normalizedRadius
            let x = min(image.width - 1, max(0, Int((centerX + normalizedX * radius).rounded())))
            let y = min(image.height - 1, max(0, Int((centerY + normalizedY * radius).rounded())))
            return SealedOpticalSample(
                gridX: radialIndex,
                gridY: angleIndex,
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                color: image.pixel(x: x, y: y).straight,
                background: backgroundRGB
            )
        }
    }
    return SealedOpticalSignature(
        gridSide: gridSide,
        samples: samples,
        pixelRadius: radius,
        contourRays: contourRays
    )
}

private func sealedMetrics(_ signature: SealedOpticalSignature) -> SealedOpticalMetrics {
    let center = signature.samples.filter { $0.radius <= 0.20 }.map(\.contrast)
    let rim = signature.samples.filter { (0.76...0.98).contains($0.radius) }.map(\.contrast)
    let body = signature.samples.filter { $0.radius <= 0.92 }
    let active = body.filter { $0.contrast >= 0.075 }
    let centerContrast = sealedMean(center)
    let rimContrast = sealedMean(rim)
    let chroma = active.map { $0.color.chroma }
    let core = body.filter { $0.radius <= 0.46 }.map { $0.color }
    let redRange = (core.map(\.r).max() ?? 0) - (core.map(\.r).min() ?? 0)
    let greenRange = (core.map(\.g).max() ?? 0) - (core.map(\.g).min() ?? 0)
    let blueRange = (core.map(\.b).max() ?? 0) - (core.map(\.b).min() ?? 0)
    let byCoordinate = Dictionary(uniqueKeysWithValues: signature.samples.map {
        ("\($0.gridX),\($0.gridY)", $0)
    })
    var residuals = [Double]()
    for sample in body where sample.radius <= 0.72 {
        let neighbours = [
            "\(sample.gridX - 1),\(sample.gridY)",
            "\(sample.gridX + 1),\(sample.gridY)",
            "\(sample.gridX),\(sample.gridY - 1)",
            "\(sample.gridX),\(sample.gridY + 1)",
        ].compactMap { byCoordinate[$0] }
        guard neighbours.count == 4 else { continue }
        let localMean = sealedMean(neighbours.map { $0.color.luminance })
        residuals.append(abs(sample.color.luminance - localMean))
    }
    return SealedOpticalMetrics(
        centerToRimRatio: centerContrast / max(rimContrast, 0.000_001),
        activeAreaFraction: Double(active.count) / Double(max(body.count, 1)),
        peakContrast: body.map(\.contrast).max() ?? 0,
        meanChroma: sealedMean(chroma),
        coreRange: max(redRange, greenRange, blueRange),
        grainEnergy: sealedMean(residuals)
    )
}

private func sealedDistance(
    _ lhs: SealedOpticalSignature,
    _ rhs: SealedOpticalSignature
) -> Double {
    precondition(lhs.samples.count == rhs.samples.count)
    let distances = zip(lhs.samples, rhs.samples).map { left, right in
        let leftDelta = StraightRGB(
            r: left.color.r - left.background.r,
            g: left.color.g - left.background.g,
            b: left.color.b - left.background.b
        )
        let rightDelta = StraightRGB(
            r: right.color.r - right.background.r,
            g: right.color.g - right.background.g,
            b: right.color.b - right.background.b
        )
        return rgbDistance(leftDelta, rightDelta)
    }
    return sealedMean(distances)
}

private func haloCompactProjectionWitness(
    _ pixels: [OutlineVisibilityPixel],
    masks: [Double],
    background: MaterialColor
) -> [OutlineVisibilityPixel] {
    precondition(pixels.count == masks.count)
    return zip(pixels, masks).map { pixel, mask in
        guard pixel.alpha > 0 else { return pixel }
        let alphaByte = Double(pixel.alpha)
        let color = MaterialColor(
            red: Double(pixel.red) / alphaByte,
            green: Double(pixel.green) / alphaByte,
            blue: Double(pixel.blue) / alphaByte
        )
        let target = MaterialRenderer.outlineVisibilityTarget(
            color: color,
            background: background
        )
        let amount = min(1, max(0, mask)) * alphaByte / 255
        let red = color.red + (target.red - color.red) * amount
        let green = color.green + (target.green - color.green) * amount
        let blue = color.blue + (target.blue - color.blue) * amount
        return OutlineVisibilityPixel(
            red: UInt8((red * alphaByte).rounded()),
            green: UInt8((green * alphaByte).rounded()),
            blue: UInt8((blue * alphaByte).rounded()),
            alpha: pixel.alpha
        )
    }
}

private func haloCompactProjectionMatchesOneApplication(
    original: [OutlineVisibilityPixel],
    candidate: [OutlineVisibilityPixel],
    masks: [Double],
    background: MaterialColor
) -> Bool {
    candidate == haloCompactProjectionWitness(
        original,
        masks: masks,
        background: background
    )
}

private func haloCompactMaskBytes(
    side: Int,
    presentationPixelSide: Int,
    innerRadius: Double
) -> [UInt8] {
    precondition(side > 0 && presentationPixelSide > 0)
    let innerCenter = CompositionPoint(x: 0.392_863_117_96, y: 0.409_179_806_84)
    let edgeWidth = 0.072
    let presentationPixel = 1 / Double(presentationPixelSide)
    let maximumRamp = max(presentationPixel, innerRadius - 2 * presentationPixel)
    let ramp = min(edgeWidth, innerRadius, maximumRamp)
    return (0..<(side * side)).map { index in
        let x = index % side
        let y = index / side
        let u = (Double(x) + 0.5) / Double(side)
        let v = (Double(y) + 0.5) / Double(side)
        let distance = hypot(u - innerCenter.x, v - innerCenter.y)
        let value = 1 - haloControlSmoothstep(
            lower: innerRadius - ramp,
            upper: innerRadius,
            value: distance
        )
        return UInt8((min(1, max(0, value)) * 255).rounded())
    }
}

private func haloControlSmoothstep(lower: Double, upper: Double, value: Double) -> Double {
    guard upper > lower else { return value < lower ? 0 : 1 }
    let t = min(1, max(0, (value - lower) / (upper - lower)))
    return t * t * (3 - 2 * t)
}

private func sealedTransparentBodyIsReadable(
    _ metrics: SealedOpticalMetrics,
    family: MaterialFamily
) -> Bool {
    metrics.peakContrast >= 0.16
        && (family == .outline || metrics.activeAreaFraction >= 0.18)
        && metrics.meanChroma >= 0.10
}

private func sealedOutlineContinuity(
    _ signature: SealedOpticalSignature
) -> SealedOutlineContinuity {
    let minimumNormalizedSupport = 2 / max(signature.pixelRadius, 1)
    let normalizedPixelStep = 1 / max(signature.pixelRadius, 1)
    let supportedRayCount = signature.contourRays.filter { ray in
        var longestRun = 0
        var currentRun = 0
        for sample in ray {
            if sample.contrast >= 0.075 {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return Double(longestRun) * normalizedPixelStep >= minimumNormalizedSupport
    }.count
    return SealedOutlineContinuity(
        supportedAngularCoverage: Double(supportedRayCount)
            / Double(max(signature.contourRays.count, 1)),
        minimumNormalizedSupport: minimumNormalizedSupport
    )
}

private func sealedRadialRampMutation(
    _ signature: SealedOpticalSignature
) -> SealedOpticalSignature {
    sealedMap(signature) { sample in
        let amount = min(0.24, sample.radius * 0.24)
        return sealedMix(sample.color, sample.background, amount)
    }
}

private func sealedDesaturatedSilhouetteMutation(
    _ signature: SealedOpticalSignature
) -> SealedOpticalSignature {
    sealedMap(signature) { sample in
        let gray = StraightRGB(
            r: sample.color.luminance,
            g: sample.color.luminance,
            b: sample.color.luminance
        )
        return sealedMix(sample.background, gray, 0.08)
    }
}

private func sealedDirectionalMutation(
    _ signature: SealedOpticalSignature
) -> SealedOpticalSignature {
    sealedMap(signature) { sample in
        sealedMix(sample.color, sample.background, max(0, sample.normalizedX) * 0.34)
    }
}

private func sealedBrokenContourMutation(
    _ signature: SealedOpticalSignature
) -> SealedOpticalSignature {
    sealedMap(signature) { sample in
        let angle = atan2(sample.normalizedY, sample.normalizedX)
        let breaksContinuity = abs(angle) < Double.pi * 0.34
        let leavesOnlySubpixelDashes = !sample.gridX.isMultiple(of: 3)
        return breaksContinuity || leavesOnlySubpixelDashes
            ? sample.background
            : sample.color
    }
}

private func sealedAngularResidual(_ signature: SealedOpticalSignature) -> Double {
    let rings = Dictionary(grouping: signature.samples.filter { $0.radius <= 0.82 }) {
        let center = (signature.gridSide - 1) / 2
        let x = $0.gridX - center
        let y = $0.gridY - center
        return x * x + y * y
    }
    return rings.values.map { ring in
        let luminances = ring.map { $0.color.luminance }
        return (luminances.max() ?? 0) - (luminances.min() ?? 0)
    }.max() ?? 0
}

private func sealedMap(
    _ signature: SealedOpticalSignature,
    transform: (SealedOpticalSample) -> StraightRGB
) -> SealedOpticalSignature {
    SealedOpticalSignature(
        gridSide: signature.gridSide,
        samples: signature.samples.map { sample in
            SealedOpticalSample(
                gridX: sample.gridX,
                gridY: sample.gridY,
                normalizedX: sample.normalizedX,
                normalizedY: sample.normalizedY,
                color: transform(sample),
                background: sample.background
            )
        },
        pixelRadius: signature.pixelRadius,
        contourRays: signature.contourRays.map { ray in
            ray.map { sample in
                SealedOpticalSample(
                    gridX: sample.gridX,
                    gridY: sample.gridY,
                    normalizedX: sample.normalizedX,
                    normalizedY: sample.normalizedY,
                    color: transform(sample),
                    background: sample.background
                )
            }
        }
    )
}

private func sealedMix(_ lhs: StraightRGB, _ rhs: StraightRGB, _ amount: Double) -> StraightRGB {
    let t = min(1, max(0, amount))
    return StraightRGB(
        r: lhs.r + (rhs.r - lhs.r) * t,
        g: lhs.g + (rhs.g - lhs.g) * t,
        b: lhs.b + (rhs.b - lhs.b) * t
    )
}

private func sealedMean(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(max(values.count, 1))
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

private func combinedAlphaImage(_ images: [PixelImage]) -> PixelImage? {
    guard let first = images.first,
          images.allSatisfy({ $0.width == first.width && $0.height == first.height })
    else {
        return nil
    }
    var rgba = Data(count: first.width * first.height * 4)
    for index in 0..<(first.width * first.height) {
        let alpha = images.map { $0.rgba[index * 4 + 3] }.max() ?? 0
        rgba[index * 4] = alpha
        rgba[index * 4 + 1] = alpha
        rgba[index * 4 + 2] = alpha
        rgba[index * 4 + 3] = alpha
    }
    return PixelImage(width: first.width, height: first.height, rgba: rgba)
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

private struct OrganicRimMetrics: CustomStringConvertible {
    let alphaCentroidOffset: Double
    let thicknessRange: Double
    let thicknessVariation: Double
    let angularCoverage: Double
    let minimumThickness: Double

    var description: String {
        "centroidOffset=\(alphaCentroidOffset), thicknessRange=\(thicknessRange), "
            + "thicknessVariation=\(thicknessVariation), coverage=\(angularCoverage), "
            + "minimumThickness=\(minimumThickness)"
    }
}

private struct OutlineContourAccentMetrics: CustomStringConvertible {
    let ridgeSeparation: Double
    let angularPresence: Double

    var description: String {
        "ridgeSeparation=\(ridgeSeparation), angularPresence=\(angularPresence)"
    }
}

private func outlineContourAccentMetrics(
    _ image: PixelImage,
    actor: ActorCompositionRecipe,
    material: ActorMaterialRecipe,
    centerYAdjustment: Double
) -> OutlineContourAccentMetrics {
    guard let topology = material.organicTopology, !topology.contours.isEmpty else {
        return OutlineContourAccentMetrics(ridgeSeparation: 0, angularPresence: 0)
    }
    let actorCenterX = actor.position.x * 393
    let actorCenterY = actor.position.y * 852 + centerYAdjustment
    let diameter = actor.diameter * 393
    var separations = [Double]()
    for contour in topology.contours.prefix(1) {
        let delta = max(0.030, (contour.outerRadius - contour.innerRadius) * 0.40)
        let boundaryRadius = contour.outerRadius
        for angleIndex in 0..<96 {
            let angle = Double(angleIndex) / 96 * Double.pi * 2
            let ridge = sample(
                image,
                actorCenterX: actorCenterX,
                actorCenterY: actorCenterY,
                center: contour.outerCenter,
                radius: boundaryRadius,
                diameter: diameter,
                angle: angle
            )
            let inside = sample(
                image,
                actorCenterX: actorCenterX,
                actorCenterY: actorCenterY,
                center: contour.outerCenter,
                radius: max(0, boundaryRadius - delta),
                diameter: diameter,
                angle: angle
            )
            let outside = sample(
                image,
                actorCenterX: actorCenterX,
                actorCenterY: actorCenterY,
                center: contour.outerCenter,
                radius: boundaryRadius + delta,
                diameter: diameter,
                angle: angle
            )
            guard let ridge, let inside, let outside else { continue }
            let baseline = StraightRGB(
                r: (inside.r + outside.r) * 0.5,
                g: (inside.g + outside.g) * 0.5,
                b: (inside.b + outside.b) * 0.5
            )
            separations.append(rgbDistance(ridge, baseline))
        }
    }
    let present = separations.filter { $0 >= 0.040 }.count
    return OutlineContourAccentMetrics(
        ridgeSeparation: percentile(separations, fraction: 0.82),
        angularPresence: Double(present) / Double(max(separations.count, 1))
    )
}

private func sample(
    _ image: PixelImage,
    actorCenterX: Double,
    actorCenterY: Double,
    center: CompositionPoint,
    radius: Double,
    diameter: Double,
    angle: Double
) -> StraightRGB? {
    let x = Int((
        actorCenterX
            + (center.x - 0.5) * diameter
            + cos(angle) * radius * diameter
    ).rounded(.down))
    let y = Int((
        actorCenterY
            + (center.y - 0.5) * diameter
            + sin(angle) * radius * diameter
    ).rounded(.down))
    guard (0..<image.width).contains(x), (0..<image.height).contains(y) else { return nil }
    return image.pixel(x: x, y: y).straight
}

private func organicRimMetrics(_ image: PixelImage) -> OrganicRimMetrics {
    var alphaWeight = 0.0
    var weightedX = 0.0
    var weightedY = 0.0
    var maximumAlpha = 0.0
    for y in 0..<image.height {
        for x in 0..<image.width {
            let alpha = image.pixel(x: x, y: y).alpha
            maximumAlpha = max(maximumAlpha, alpha)
            alphaWeight += alpha
            weightedX += ((Double(x) + 0.5) / Double(image.width)) * alpha
            weightedY += ((Double(y) + 0.5) / Double(image.height)) * alpha
        }
    }
    let centroidX = weightedX / max(alphaWeight, 0.000_001)
    let centroidY = weightedY / max(alphaWeight, 0.000_001)
    var thicknesses = [Double]()
    let threshold = maximumAlpha * 0.28
    for angleIndex in 0..<96 {
        let angle = Double(angleIndex) / 96 * Double.pi * 2
        var occupied = [Double]()
        for step in 0...220 {
            let radius = Double(step) / 220 * 0.54
            let x = Int(((0.5 + cos(angle) * radius) * Double(image.width)).rounded(.down))
            let y = Int(((0.5 + sin(angle) * radius) * Double(image.height)).rounded(.down))
            guard (0..<image.width).contains(x), (0..<image.height).contains(y) else { continue }
            if image.pixel(x: x, y: y).alpha >= threshold { occupied.append(radius) }
        }
        if let first = occupied.first, let last = occupied.last {
            thicknesses.append(last - first)
        }
    }
    let mean = thicknesses.reduce(0, +) / Double(max(thicknesses.count, 1))
    let variance = thicknesses.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        / Double(max(thicknesses.count, 1))
    return OrganicRimMetrics(
        alphaCentroidOffset: hypot(centroidX - 0.5, centroidY - 0.5),
        thicknessRange: (thicknesses.max() ?? 0) - (thicknesses.min() ?? 0),
        thicknessVariation: sqrt(variance) / max(mean, 0.000_001),
        angularCoverage: Double(thicknesses.count) / 96,
        minimumThickness: thicknesses.min() ?? 0
    )
}

private func maximumContourSpacingImbalance(_ image: PixelImage) -> Double {
    var maximumImbalance = 0.0
    for angleIndex in 0..<72 {
        let angle = Double(angleIndex) / 72 * Double.pi * 2
        var bands = [(start: Double, end: Double)]()
        var activeStart: Double?
        for step in 0...320 {
            let radius = Double(step) / 320 * 0.52
            let x = Int(((0.5 + cos(angle) * radius) * Double(image.width)).rounded(.down))
            let y = Int(((0.5 + sin(angle) * radius) * Double(image.height)).rounded(.down))
            let occupied = (0..<image.width).contains(x)
                && (0..<image.height).contains(y)
                && image.pixel(x: x, y: y).alpha >= 0.24
            if occupied, activeStart == nil {
                activeStart = radius
            } else if !occupied, let start = activeStart {
                bands.append((start, radius))
                activeStart = nil
            }
        }
        if let start = activeStart { bands.append((start, 0.52)) }
        let centers = bands.map { ($0.start + $0.end) * 0.5 }
        guard centers.count >= 3 else { continue }
        let gaps = zip(centers, centers.dropFirst()).map { $1 - $0 }
        maximumImbalance = max(maximumImbalance, (gaps.max() ?? 0) - (gaps.min() ?? 0))
    }
    return maximumImbalance
}

private func mechanicalRingControl(size: Int) -> PixelImage {
    var rgba = Data(count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let u = (Double(x) + 0.5) / Double(size)
            let v = (Double(y) + 0.5) / Double(size)
            let radius = hypot(u - 0.5, v - 0.5)
            let alpha: UInt8 = (0.24...0.44).contains(radius) ? 255 : 0
            let offset = (y * size + x) * 4
            rgba[offset] = alpha
            rgba[offset + 1] = alpha
            rgba[offset + 2] = alpha
            rgba[offset + 3] = alpha
        }
    }
    return PixelImage(width: size, height: size, rgba: rgba)
}

private func concentricTorusWithShiftedChroma(
    width: Int,
    height: Int,
    center: CGPoint,
    diameter: Double
) throws -> CGImage {
    let bytesPerRow = width * 4
    var rgba = Data(count: bytesPerRow * height)
    let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
        guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
        for y in 0..<height {
            for x in 0..<width {
                let normalizedX = (Double(x) + 0.5 - center.x) / diameter
                let normalizedY = (Double(y) + 0.5 - center.y) / diameter
                let radius = hypot(normalizedX, normalizedY)
                guard (0.25...0.47).contains(radius) else { continue }
                let ownershipDistance = hypot(normalizedX - 0.22, normalizedY + 0.09)
                let ownership = exp(-pow(ownershipDistance / 0.22, 2))
                let alpha = 0.82
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = UInt8((alpha * (0.04 + ownership * 0.96) * 255).rounded())
                bytes[offset + 1] = UInt8((alpha * (0.05 + ownership * 0.28) * 255).rounded())
                bytes[offset + 2] = UInt8((alpha * (0.09 + ownership * 0.82) * 255).rounded())
                bytes[offset + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return true
    }
    #expect(rendered)
    let provider = try #require(CGDataProvider(data: rgba as CFData))
    return try #require(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
}

private func radialTopologyMetrics(
    _ image: PixelImage,
    actor: ActorCompositionRecipe,
    material: ActorMaterialRecipe? = nil,
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
    let actorCenterX = actor.position.x * 393
    let actorCenterY = actor.position.y * 852 + centerYAdjustment
    let topology = material?.organicTopology
    let openingAuthority = if material?.family == .outline {
        topology?.contours.last?.innerCenter
    } else {
        topology?.innerCenter
    }
    let outerAuthority = if material?.family == .outline {
        topology?.contours.first?.outerCenter
    } else {
        topology?.outerCenter
    }
    let radius = actor.diameter * 393 * 0.5
    let diameter = radius * 2
    let centerX = actorCenterX + ((openingAuthority?.x ?? 0.5) - 0.5) * diameter
    let centerY = actorCenterY + ((openingAuthority?.y ?? 0.5) - 0.5) * diameter
    let rimCenterX = actorCenterX + ((outerAuthority?.x ?? 0.5) - 0.5) * diameter
    let rimCenterY = actorCenterY + ((outerAuthority?.y ?? 0.5) - 0.5) * diameter
    var centerSamples = [Double]()
    var interiorSamples = [Double]()
    var rimSamples = [Double]()
    let minX = max(0, Int(floor(actorCenterX - radius * 1.25)))
    let maxX = min(image.width - 1, Int(ceil(actorCenterX + radius * 1.25)))
    let minY = max(0, Int(floor(actorCenterY - radius * 1.25)))
    let maxY = min(image.height - 1, Int(ceil(actorCenterY + radius * 1.25)))
    for y in minY...maxY {
        for x in minX...maxX {
            let normalizedRadius = hypot(
                (Double(x) + 0.5 - centerX) / max(radius, 1),
                (Double(y) + 0.5 - centerY) / max(radius, 1)
            )
            let normalizedRimRadius = hypot(
                (Double(x) + 0.5 - rimCenterX) / max(radius, 1),
                (Double(y) + 0.5 - rimCenterY) / max(radius, 1)
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
            if normalizedRadius <= 0.32 {
                interiorSamples.append(contrast)
            }
            if (0.60...0.98).contains(normalizedRimRadius) {
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
        counterformSoftness: actor.counterformSoftness,
        organicTopology: actor.organicTopology
    )
}

private func replacingOrganicTopology(
    _ actor: ActorMaterialRecipe,
    with topology: OrganicRadialTopology?
) -> ActorMaterialRecipe {
    ActorMaterialRecipe(
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
        organicTopology: topology
    )
}

private func replacingSurface(
    _ actor: ActorMaterialRecipe,
    colors: [MaterialColor],
    fields: [RadialField]
) -> ActorMaterialRecipe {
    ActorMaterialRecipe(
        eventID: actor.eventID,
        family: actor.family,
        mutation: actor.mutation,
        colors: colors,
        fields: fields,
        baseOpacity: actor.baseOpacity,
        edgeSoftness: actor.edgeSoftness,
        contourWidth: actor.contourWidth,
        contourCount: actor.contourCount,
        counterformRadius: actor.counterformRadius,
        counterformSoftness: actor.counterformSoftness,
        organicTopology: actor.organicTopology
    )
}

private func replacingContourCenters(
    _ contour: OrganicRadialContour,
    outerCenter: CompositionPoint,
    innerCenter: CompositionPoint
) -> OrganicRadialContour {
    OrganicRadialContour(
        outerCenter: outerCenter,
        outerRadius: contour.outerRadius,
        innerCenter: innerCenter,
        innerRadius: contour.innerRadius,
        opacity: contour.opacity
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
        counterformSoftness: actor.counterformSoftness,
        organicTopology: actor.organicTopology
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

private func radialSectorMeans(
    _ image: PixelImage,
    radialBand: ClosedRange<Double>,
    sectorCount: Int
) -> [StraightRGB] {
    var red = Array(repeating: 0.0, count: sectorCount)
    var green = Array(repeating: 0.0, count: sectorCount)
    var blue = Array(repeating: 0.0, count: sectorCount)
    var counts = Array(repeating: 0, count: sectorCount)
    for y in 0..<image.height {
        for x in 0..<image.width {
            let u = (Double(x) + 0.5) / Double(image.width) - 0.5
            let v = (Double(y) + 0.5) / Double(image.height) - 0.5
            guard radialBand.contains(hypot(u, v)) else { continue }
            let normalizedAngle = (atan2(v, u) + Double.pi * 2)
                .truncatingRemainder(dividingBy: Double.pi * 2)
            let index = min(
                sectorCount - 1,
                Int(normalizedAngle / (Double.pi * 2) * Double(sectorCount))
            )
            let color = image.pixel(x: x, y: y).straight
            red[index] += color.r
            green[index] += color.g
            blue[index] += color.b
            counts[index] += 1
        }
    }
    return (0..<sectorCount).map { index in
        let divisor = Double(max(counts[index], 1))
        return StraightRGB(
            r: red[index] / divisor,
            g: green[index] / divisor,
            b: blue[index] / divisor
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

private func alphaBytes(_ data: Data) throws -> Data {
    let image = try pixels(data)
    var alpha = Data()
    alpha.reserveCapacity(image.width * image.height)
    for y in 0..<image.height {
        for x in 0..<image.width {
            alpha.append(image.pixel(x: x, y: y).alphaByte)
        }
    }
    return alpha
}

private func fixture11PresentationEvidenceDigest(
    eventID: String,
    isolated: MaterialRenderedScene,
    isolatedTrace: MaterialOutlineOwnershipTrace,
    removed: MaterialRenderedScene,
    removedTrace: MaterialOutlineOwnershipTrace
) throws -> String {
    sha256Hex(Data([
        eventID,
        try fixture11PresentationSceneDigest(scene: isolated, trace: isolatedTrace),
        try fixture11PresentationSceneDigest(scene: removed, trace: removedTrace),
    ].joined(separator: "|").utf8))
}

private func fixture11PresentationEvidenceDigest(
    eventID: String,
    isolated: MaterialPresentationEvidenceScene,
    removed: MaterialPresentationEvidenceScene,
    projected: MaterialPresentationEvidenceScene,
    palettePoles: [MaterialPresentationEvidenceScene]
) throws -> String {
    sha256Hex(Data([
        eventID,
        try fixture11PresentationSceneDigest(scene: isolated),
        try fixture11PresentationSceneDigest(scene: removed),
        try fixture11PresentationSceneDigest(scene: projected),
        try palettePoles.map(fixture11PresentationSceneDigest).joined(separator: ":"),
    ].joined(separator: "|").utf8))
}

private func fixture11PresentationSceneDigest(
    scene: MaterialRenderedScene,
    trace: MaterialOutlineOwnershipTrace
) throws -> String {
    try fixture11PresentationSceneDigest(
        fullScreen: scene.fullScreen,
        calendarTile: scene.calendarTile,
        tileCrop: scene.tileCrop,
        drawSequence: scene.drawSequence,
        ownerEventIDs: trace.ownerEventIDs,
        ownerLabels: trace.ownerLabels,
        counterfactualBackgroundRGBA: trace.counterfactualBackgroundRGBA
    )
}

private func fixture11PresentationSceneDigest(
    scene: MaterialPresentationEvidenceScene
) throws -> String {
    try fixture11PresentationSceneDigest(
        fullScreen: scene.fullScreen,
        calendarTile: scene.calendarTile,
        tileCrop: scene.tileCrop,
        drawSequence: scene.drawSequence,
        ownerEventIDs: scene.ownership.ownerEventIDs,
        ownerLabels: scene.ownership.ownerLabels,
        counterfactualBackgroundRGBA: scene.ownership.counterfactualBackgroundRGBA
    )
}

private func fixture11PresentationSceneDigest(
    fullScreen: NeutralRenderedImage,
    calendarTile: NeutralRenderedImage,
    tileCrop: PixelRect,
    drawSequence: [String],
    ownerEventIDs: [String],
    ownerLabels: Data,
    counterfactualBackgroundRGBA: Data
) throws -> String {
    let fullAlpha = try alphaBytes(fullScreen.pngData)
    let tileAlpha = try alphaBytes(calendarTile.pngData)
    let tileOwnerLabels = fixture11CroppedBytes(
        ownerLabels,
        sourceWidth: fullScreen.pixelWidth,
        crop: tileCrop,
        bytesPerPixel: 1
    )
    let tileBackground = fixture11CroppedBytes(
        counterfactualBackgroundRGBA,
        sourceWidth: fullScreen.pixelWidth,
        crop: tileCrop,
        bytesPerPixel: 4
    )
    return [
        sha256Hex(fullScreen.pngData),
        sha256Hex(calendarTile.pngData),
        sha256Hex(fullAlpha),
        sha256Hex(tileAlpha),
        "\(tileCrop.x),\(tileCrop.y),\(tileCrop.width),\(tileCrop.height)",
        drawSequence.joined(separator: ","),
        ownerEventIDs.joined(separator: ","),
        sha256Hex(ownerLabels),
        sha256Hex(tileOwnerLabels),
        sha256Hex(counterfactualBackgroundRGBA),
        sha256Hex(tileBackground),
    ].joined(separator: "|")
}

private func fixture11CroppedBytes(
    _ source: Data,
    sourceWidth: Int,
    crop: PixelRect,
    bytesPerPixel: Int
) -> Data {
    var result = Data()
    result.reserveCapacity(crop.width * crop.height * bytesPerPixel)
    for y in crop.y..<(crop.y + crop.height) {
        let lower = (y * sourceWidth + crop.x) * bytesPerPixel
        result.append(source[lower..<(lower + crop.width * bytesPerPixel)])
    }
    return result
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
