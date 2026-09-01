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
                configuration: .init(scale: 2)
            )
            let full = try downsampledPixels(rendered.fullScreen.pngData, width: 393, height: 852)
            let tile = full.cropped(x: 0, y: 229, width: 393, height: 393)
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
                #expect(fullMetrics.centerToRimRatio <= 0.22, Comment(rawValue: context))
                #expect(tileMetrics.centerToRimRatio <= 0.22, Comment(rawValue: context))
            }

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
                    material: actorMaterial,
                    background: fixture.background,
                    centerYAdjustment: 0,
                    reference: removedPixels
                )
                let contributionContext = context + " contribution=\(contribution)"
                #expect(contribution.rimContrast >= 0.040, Comment(rawValue: contributionContext))
                #expect(contribution.centerToRimRatio <= 0.22, Comment(rawValue: contributionContext))
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
                configuration: .init(scale: 2)
            )
            let full = try downsampledPixels(rendered.fullScreen.pngData, width: 393, height: 852)
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

            #expect(fullMetrics.ridgeSeparation >= 0.055, Comment(rawValue: context))
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
                    configuration: .init(scale: 2)
                )
                let comparisonFull = try downsampledPixels(
                    comparisonRendered.fullScreen.pngData,
                    width: 393,
                    height: 852
                )
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
        #expect(sha256Hex(defaultOutput.fullScreen.pngData) ==
            "0fb4432f23e8f850cbbdecfc07b15bc65509fb7ba0ef9679c7bb8444e8668555")
        #expect(sha256Hex(defaultOutput.calendarTile.pngData) ==
            "7a91334a807fe3c0773ba156a494540edea5cb339af51ba6e9b987a05e6c2029")
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

    @Test("fixture 11 outline captured actor replay eliminates recursive counterfactual renders")
    func fixture11OutlineCapturedPrefixesEliminateRecursiveCounterfactualRenders() throws {
        // Production regression caught: rebuilding the complete scene once per
        // outline actor makes package generation scale with actor count. The
        // retained reference freezes ownership/background/output semantics;
        // captured actor replay must reproduce them without material rebuilds.
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

        // The future implementation may change only how actor-removed
        // counterfactuals are obtained, never their observable semantics.
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

        #expect(sha256Hex(reference.fullScreen.pngData) ==
            "12dfaabad17090eee177fd7d0beb84a26a3f0f7d7147bc591745c2d47d430c42")
        #expect(sha256Hex(reference.calendarTile.pngData) ==
            "d31177d42675f2e7f55c910c7469443c078f3348e9fc51cacfdf0ece2de7fc05")
        #expect(sha256Hex(referenceAlpha) ==
            "180035a2d810c6118f95235d7fd255ea2e1fb5c7f910c0648e6aad4eca344879")
        #expect(sha256Hex(referenceTrace.ownerLabels) ==
            "235eb188a5f27778d984b7ff1580dc3dae32faf10c0f450250a9384a969ff922")
        #expect(sha256Hex(referenceTrace.counterfactualBackgroundRGBA) ==
            "5eb5a73164a25057d646d757425817564bd657440091a5ca8a7b56dad3c25856")
        #expect(ownedPixelCount == 145_735)

        #expect(referenceInstrumentation.canonicalRawSceneRenders == 1)
        #expect(referenceInstrumentation.actorRemovedFullSceneRenders == 10)
        #expect(referenceInstrumentation.capturedActorLayerBuilds == 10)
        #expect(referenceInstrumentation.counterfactualCompositePasses == 0)

        // Required optimized contract: one material pass captures each actor;
        // N composite-only replays replace N recursive material renders.
        #expect(capturedInstrumentation.canonicalRawSceneRenders == 1)
        #expect(capturedInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(capturedInstrumentation.capturedActorLayerBuilds == 10)
        #expect(capturedInstrumentation.counterfactualCompositePasses == 10)
    }

    @Test("fixture 11 presentation evidence is captured once by the renderer")
    func fixture11PresentationEvidencePayloadMatchesLegacyActorRenders() throws {
        // Production regression caught: evidence rebuilding isolated and
        // actor-removed scenes per actor repeats material construction and can
        // drift from the renderer-owned presentation pixels. The optional
        // payload must reuse one canonical actor build while preserving every
        // legacy pixel and ownership byte.
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

        var legacyDigests = [String: String]()
        var legacyCanonicalRenders = 0
        var legacyActorRemovedRenders = 0
        var legacyActorBuilds = 0
        var legacyCounterfactualComposites = 0
        for eventID in expectedOrder {
            let actor = try #require(recipe.actors.first { $0.eventID == eventID })
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
                actors: recipe.actors.filter { $0.eventID != eventID }
            )
            let isolatedInstrumentation = MaterialRenderInstrumentation()
            let isolated = try renderer.render(
                recipe: isolatedRecipe,
                material: material,
                background: .lowContrast,
                configuration: .init(
                    scale: 1,
                    supersampling: 2,
                    outlineVisibilityPlacement: .none,
                    outlineCounterfactualMode: .capturedActorReplay,
                    instrumentation: isolatedInstrumentation
                )
            )
            let removedInstrumentation = MaterialRenderInstrumentation()
            let removed = try renderer.render(
                recipe: removedRecipe,
                material: material,
                background: .lowContrast,
                configuration: .init(
                    scale: 1,
                    supersampling: 2,
                    outlineVisibilityPlacement: .none,
                    outlineCounterfactualMode: .capturedActorReplay,
                    instrumentation: removedInstrumentation
                )
            )
            let isolatedTrace = try #require(isolatedInstrumentation.ownershipTrace)
            let removedTrace = try #require(removedInstrumentation.ownershipTrace)
            legacyDigests[eventID] = try fixture11PresentationEvidenceDigest(
                eventID: eventID,
                isolated: isolated,
                isolatedTrace: isolatedTrace,
                removed: removed,
                removedTrace: removedTrace
            )
            for instrumentation in [isolatedInstrumentation, removedInstrumentation] {
                legacyCanonicalRenders += instrumentation.canonicalRawSceneRenders
                legacyActorRemovedRenders += instrumentation.actorRemovedFullSceneRenders
                legacyActorBuilds += instrumentation.capturedActorLayerBuilds
                legacyCounterfactualComposites += instrumentation.counterfactualCompositePasses
            }
        }
        let expectedLegacyDigests = [
            "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801":
                "8fdb02cc8beea34884c93d64daa9fd1746b251aefa587d259516e62308d7e0d1",
            "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02":
                "41f39540779f29e61da1bd915b03bd9f559852ef39ce9ab481662455d55554d4",
            "2C9F4B58-ABF5-4F7E-8CA9-6D415C7B3D03":
                "06aaa0917cfcb97d6338620cecb4e58885e5d1124b01af9b4b88d7bee43b989d",
            "3D247E01-C609-43C1-A5B2-3E0D9CF8B504":
                "8261165d96a1a48c99a4f8a7820abff7b19fab355738f007a3dc6a21b6409e6e",
            "4E6B83FD-19A8-4AA2-91FC-D297E6C15405":
                "30ba9c9a9aa05b88339fc5b321f70e1134463cb697b921266428e2a651acd0aa",
            "5FA2D140-7C0E-45B9-BE3D-8124A937EF06":
                "9f3914555835418919b04445452d73c49ee4c682c2d3624810d2dab8f6c55dd3",
            "60D319B7-3E21-4E8A-879F-5C6B24FA0A07":
                "a576685122f2730ea0284d6691c9e5fd92516e7a98cb476b5f5c7cafdfb718d4",
            "71E4AC82-5F36-4B19-9D48-A7C2E60B1D08":
                "c3d60e91e3d4bba23041df652bac9b7c99f311dfe19bc120096fec79b0e257c3",
            "82F5B06C-6A47-4C2E-8E51-B93D17CA2F09":
                "7778531892d5020108b5646c4934ee82c8cbdee63a969e0b569bf6c32a563810",
            "9346C9D1-7B58-4D3F-A062-CE4B28D03A10":
                "426c8819bb1e69b5f0e9c824287cb81d64ff16e07ffd0ae8298ddb7ef22b19ff",
        ]
        #expect(
            legacyDigests == expectedLegacyDigests,
            Comment(rawValue: "legacy presentation digests=\(legacyDigests.sorted { $0.key < $1.key })")
        )
        #expect(legacyDigests.count == 10)
        #expect(legacyCanonicalRenders == 20)
        #expect(legacyActorRemovedRenders == 0)
        #expect(legacyActorBuilds == 100)
        #expect(legacyCounterfactualComposites == 100)

        if let payload = requestOn.presentationEvidence {
            #expect(payload.actors.map(\.eventID) == expectedOrder)
            #expect(payload.actors.count == 10)
            for actorPayload in payload.actors {
                let payloadDigest = try fixture11PresentationEvidenceDigest(
                    eventID: actorPayload.eventID,
                    isolated: actorPayload.isolated,
                    removed: actorPayload.removed
                )
                #expect(payloadDigest == legacyDigests[actorPayload.eventID])
            }
        }
        #expect(requestOn.presentationEvidence != nil)

        // Desired payload cost: all single/double-removal backgrounds and all
        // isolated actor composites derive from one canonical actor capture.
        #expect(requestedInstrumentation.canonicalRawSceneRenders == 1)
        #expect(requestedInstrumentation.actorRemovedFullSceneRenders == 0)
        #expect(requestedInstrumentation.capturedActorLayerBuilds == 10)
        #expect(requestedInstrumentation.counterfactualCompositePasses == 55)
        #expect(requestedInstrumentation.isolatedPresentationComposites == 10)

        // A source-scale prefix approximation was proven wrong at this pixel:
        // one rounded counterfactual byte changes the final visibility result.
        let finalPixel = try pixels(requestOn.fullScreen.pngData).pixel(x: 201, y: 246)
        #expect(finalPixel == SampledRGBA(redByte: 125, greenByte: 127, blueByte: 120, alphaByte: 255))
        let prefixMutation = MaterialRenderer.outlineVisibilityPixel(
            OutlineVisibilityPixel(red: 125, green: 127, blue: 120, alpha: 255),
            background: MaterialColor(
                red: 125.0 / 255.0,
                green: 128.0 / 255.0,
                blue: 120.0 / 255.0
            )
        )
        #expect(prefixMutation == OutlineVisibilityPixel(red: 125, green: 48, blue: 120, alpha: 255))
        #expect(prefixMutation != OutlineVisibilityPixel(red: 125, green: 127, blue: 120, alpha: 255))
    }

    @Test("fixture 11 payload readability matches legacy metrics without renderer work")
    func fixture11PayloadReadabilityMatchesLegacyMetricsWithoutRerenders() throws {
        // Production regression caught: scene-scale evidence recomputes every
        // isolated and removed outline scene after the renderer has already
        // returned byte-exact presentation evidence for those same actors.
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
        #expect(instrumentation.counterfactualCompositePasses == 55)
        #expect(instrumentation.isolatedPresentationComposites == 10)

        let legacy = try MaterialEvidencePackage.legacySceneScaleReadabilityForTesting(
            source: source,
            recipe: recipe,
            material: material,
            background: .lowContrast,
            renderer: renderer
        )
        #expect(legacy.count == 10)
        #expect(legacy.map(\.eventID) == recipe.actors.map(\.eventID))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let legacyDigests = try Dictionary(uniqueKeysWithValues: legacy.map { metric in
            (metric.eventID, sha256Hex(try encoder.encode(metric)))
        })
        let expectedLegacyDigests = [
            "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801":
                "8603d1cd703c6331d2a6629e7d5cd14dee4a9ea7b4a5daf6dd1bc7e3314dfceb",
            "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02":
                "01f8426d2838292db073c4528d72c06b26bb6508fd62c67d18d292e74ec6a676",
            "2C9F4B58-ABF5-4F7E-8CA9-6D415C7B3D03":
                "f98fd912dcdc8a49250911adf2e07dd8c55486f80376ec51fa2f0ebbad4ec81c",
            "3D247E01-C609-43C1-A5B2-3E0D9CF8B504":
                "84cbf73501fcf6293cb71f4cda15c674ee2d0ee3a071f362c602c9f395c4830d",
            "4E6B83FD-19A8-4AA2-91FC-D297E6C15405":
                "ded1a0a436c23f59a8106b4c9400a000a4ef17aebc1ef1cbdf7fa0104be37b62",
            "5FA2D140-7C0E-45B9-BE3D-8124A937EF06":
                "acb645d424178e0f6b8d8e55903293aaf574d3a8b213aa7e8adbccc8b62ca0c0",
            "60D319B7-3E21-4E8A-879F-5C6B24FA0A07":
                "e275fa402007be9447ba7c54220439c3b266f9eb133bf8ecbfddfad30e7968e0",
            "71E4AC82-5F36-4B19-9D48-A7C2E60B1D08":
                "a747a9c7dc3b333e3a57adc737acfc41f7a25ca4cf0e3a1bb8d8aaf69aae25c2",
            "82F5B06C-6A47-4C2E-8E51-B93D17CA2F09":
                "8d825797adba804a69761916a3fe64fb46a2433510aef59a757986b56033f9c6",
            "9346C9D1-7B58-4D3F-A062-CE4B28D03A10":
                "9b380826ba32d39d1b680279b866c3346f8722119385e7224fc5bf82dafa65b9",
        ]
        #expect(
            legacyDigests == expectedLegacyDigests,
            Comment(rawValue: "legacy readability digests=\(legacyDigests.sorted { $0.key < $1.key })")
        )

        let countersBeforePayload = [
            instrumentation.canonicalRawSceneRenders,
            instrumentation.actorRemovedFullSceneRenders,
            instrumentation.capturedActorLayerBuilds,
            instrumentation.counterfactualCompositePasses,
            instrumentation.isolatedPresentationComposites,
        ]
        let payload = try MaterialEvidencePackage.presentationSceneScaleReadabilityForTesting(
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
        if let payload {
            #expect(try encoder.encode(payload) == encoder.encode(legacy))
            #expect(payload == legacy)
        }
        #expect(payload != nil)
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
        let expectedRawFailures = Set(cases.dropLast().map {
            "c\($0.colorCount)/lowContrast/\($0.eventPrefix)"
        })
        var currentFailures = Set<String>()
        var preOnlyFailures = Set<String>()
        var postWitnessFailures = Set<String>()
        var failuresByView = [Fixture11PresentationView: Int]()

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
                configuration: .init(scale: 1, supersampling: 2)
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
            #expect(fixture11DifferenceBounds(current1x, removed1x) ==
                fixture11DifferenceBounds(presented1x, removed1x))

            let key = "c\(item.colorCount)/lowContrast/\(item.eventPrefix)"
            let views = fixture11PresentationViews(
                current: current1x,
                preOnly: preOnly1x,
                postWitness: presented1x,
                alpha: alpha1x,
                actor: actor
            )
            for view in views {
                let current = fixture11IsolatedIdentityMetrics(
                    alpha: view.alpha,
                    image: view.current,
                    centerX: view.centerX,
                    centerY: view.centerY,
                    pixelRadius: view.pixelRadius,
                    background: .lowContrast
                )
                let preOnly = fixture11IsolatedIdentityMetrics(
                    alpha: view.alpha,
                    image: view.preOnly,
                    centerX: view.centerX,
                    centerY: view.centerY,
                    pixelRadius: view.pixelRadius,
                    background: .lowContrast
                )
                let postWitness = fixture11IsolatedIdentityMetrics(
                    alpha: view.alpha,
                    image: view.postWitness,
                    centerX: view.centerX,
                    centerY: view.centerY,
                    pixelRadius: view.pixelRadius,
                    background: .lowContrast
                )
                if !current.passes {
                    currentFailures.insert(key)
                    failuresByView[view.view, default: 0] += 1
                }
                if !preOnly.passes { preOnlyFailures.insert(key) }
                if !postWitness.passes { postWitnessFailures.insert(key) }
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

        #expect(postWitnessFailures.isEmpty, Comment(rawValue:
            "test-local post-downsample witness failures=\(postWitnessFailures.sorted())"
        ))
        #expect(preOnlyFailures == expectedPreFailures, Comment(rawValue:
            "pre-downsample-only mutation failures=\(preOnlyFailures.sorted())"
        ))
        #expect(currentFailures == expectedRawFailures, Comment(rawValue:
            "renderer-owned final presentation missing cells=\(currentFailures.sorted()) "
                + "views=\(failuresByView)"
        ))
        #expect(!currentFailures.contains("c3/lowContrast/9346"))
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
                        if family == .mist, metrics.grainEnergy < 0.006 {
                            failures.append("mist-grain \(label) energy=\(metrics.grainEnergy)")
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

        let mistKey = SealedMaterialKey(
            colorCount: 3,
            background: .lowContrast,
            family: .mist,
            view: .actor
        )
        let mistControl = try #require(observations[mistKey])
        #expect(sealedMetrics(sealedGrainMutation(mistControl)).grainEnergy >= 0.006)

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

private func sealedGrainMutation(
    _ signature: SealedOpticalSignature
) -> SealedOpticalSignature {
    sealedMap(signature) { sample in
        let sign = (sample.gridX &+ sample.gridY).isMultiple(of: 2) ? 1.0 : -1.0
        return StraightRGB(
            r: min(1, max(0, sample.color.r + sign * 0.035)),
            g: min(1, max(0, sample.color.g + sign * 0.035)),
            b: min(1, max(0, sample.color.b + sign * 0.035))
        )
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
    removed: MaterialPresentationEvidenceScene
) throws -> String {
    sha256Hex(Data([
        eventID,
        try fixture11PresentationSceneDigest(scene: isolated),
        try fixture11PresentationSceneDigest(scene: removed),
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
