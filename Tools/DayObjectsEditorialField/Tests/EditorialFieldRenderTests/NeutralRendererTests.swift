import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import EditorialFieldCore
import EditorialFieldEvidence
import EditorialFieldRender

private let canonicalTestCommit = String(repeating: "a", count: 40)
private let otherTestCommit = String(repeating: "b", count: 40)

@Suite("Neutral editorial field evidence")
struct NeutralRendererTests {
    @Test("phone PNG is exact 3x and tile bytes are cropped from that scene")
    func fullScreenAndTileShareOneCanvas() throws {
        let result = try NeutralRenderer().render(
            recipe: testRecipe,
            background: .light,
            configuration: .init(scale: 3)
        )

        #expect(result.fullScreen.pixelWidth == 1_179)
        #expect(result.fullScreen.pixelHeight == 2_556)
        #expect(result.calendarTile.pixelWidth == 1_179)
        #expect(result.calendarTile.pixelHeight == 1_179)

        let full = try decodePNG(result.fullScreen.pngData)
        let tile = try decodePNG(result.calendarTile.pngData)
        let crop = CGRect(
            x: result.tileCrop.x,
            y: result.tileCrop.y,
            width: result.tileCrop.width,
            height: result.tileCrop.height
        )
        let expectedTile = try #require(full.cropping(to: crop))
        #expect(try rgbaBytes(tile) == rgbaBytes(expectedTile))
    }

    @Test("actors carry distinct labels, depth luminance, local blur, and foreground order")
    func actorEvidenceIsReadableAndOrdered() throws {
        let result = try NeutralRenderer().render(
            recipe: testRecipe,
            background: .dark,
            configuration: .init(scale: 3)
        )

        #expect(result.actors.map(\.label) == ["A01", "A02", "A03"])
        #expect(Set(result.actors.map(\.luminance)).count == 3)
        #expect(result.actors.sorted { $0.depth < $1.depth }.map(\.luminance)
            == result.actors.map(\.luminance).sorted())
        #expect(result.actors.allSatisfy { $0.labelInkPixelCount > 0 })
        #expect(result.actors.allSatisfy { $0.localBlurPixels >= 0 })
        #expect(result.drawSequence == ["far", "middle", "foreground"])
    }

    @Test("debug overlay toggles emit only requested separate images")
    func overlayTogglesAreExact() throws {
        let requested: Set<NeutralOverlay> = [.crop, .overlap, .centerOfMass, .occupiedBounds]
        let result = try NeutralRenderer().render(
            recipe: testRecipe,
            background: .warm,
            configuration: .init(scale: 3, overlays: requested)
        )
        #expect(Set(result.debugOverlays.keys) == requested)
        #expect(result.debugOverlays.values.allSatisfy {
            $0.pixelWidth == 1_179 && $0.pixelHeight == 2_556
        })

        let clean = try NeutralRenderer().render(
            recipe: testRecipe,
            background: .warm,
            configuration: .init(scale: 3, overlays: [])
        )
        #expect(clean.debugOverlays.isEmpty)
    }

    @Test("actor blur changes only its local layer before scene compositing")
    func blurIsActorLocal() throws {
        let sharp = try NeutralRenderer().render(
            recipe: localBlurRecipe(firstBlur: 0),
            background: .dark,
            configuration: .init(scale: 1)
        )
        let locallyBlurred = try NeutralRenderer().render(
            recipe: localBlurRecipe(firstBlur: 0.05),
            background: .dark,
            configuration: .init(scale: 1)
        )
        let sharpImage = try decodePNG(sharp.fullScreen.pngData)
        let blurredImage = try decodePNG(locallyBlurred.fullScreen.pngData)

        #expect(try rgbaBytes(sharpImage) != rgbaBytes(blurredImage))
        let unaffectedActorRegion = CGRect(x: 274, y: 108, width: 92, height: 92)
        let sharpRegion = try #require(sharpImage.cropping(to: unaffectedActorRegion))
        let blurredRegion = try #require(blurredImage.cropping(to: unaffectedActorRegion))
        #expect(try rgbaBytes(sharpRegion) == rgbaBytes(blurredRegion))
    }

    @Test("composition coverage includes every breadth fixture and continuity stage at every phase and view")
    func packageCoverageIsComplete() {
        let manifest = CorpusManifest.visibleV1()
        let coverage = EvidencePackage.compositionCoverage(for: manifest)

        #expect(coverage.breadth.count == 12 * 4 * 2)
        #expect(Set(coverage.breadth.map(\.fixtureIndex)) == Set(0..<12))
        #expect(Set(coverage.breadth.map(\.phase)) == Set([0, 0.25, 0.5, 0.75]))
        #expect(Set(coverage.breadth.map(\.view)) == Set(EvidenceView.allCases))

        #expect(coverage.continuity.count == 7 * 4 * 2)
        #expect(Set(coverage.continuity.compactMap(\.stage)) == Set(0..<7))
        #expect(coverage.continuityActorCounts == [1, 2, 3, 5, 7, 10, 5])
        #expect(coverage.coreImageCount == 152)
    }

    @Test("sealed package verification fails after one artifact byte changes")
    func tamperFailsVerification() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-evidence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generated = try EvidencePackage.generateComposition(
            manifest: .visibleV1(),
            sourceCommit: canonicalTestCommit,
            outputDirectory: directory,
            renderConfiguration: .init(scale: 1, overlays: [])
        )
        let packageHash = generated.packageHash
        #expect(try EvidencePackage.verify(
            directory: directory,
            expectedSourceCommit: canonicalTestCommit
        ) == packageHash)

        let artifact = directory.appendingPathComponent("metrics.json")
        var bytes = try Data(contentsOf: artifact)
        bytes.append(0x20)
        try bytes.write(to: artifact, options: .atomic)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: directory, expectedSourceCommit: canonicalTestCommit)
        }
    }

    @Test("composition writer emits the complete sealed package contract")
    func compositionWriterProducesReviewFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-composition-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generated = try EvidencePackage.generateComposition(
            manifest: .visibleV1(),
            sourceCommit: canonicalTestCommit,
            outputDirectory: directory,
            renderConfiguration: .init(scale: 1, overlays: [])
        )

        #expect(generated.manifest.sourceCommit == canonicalTestCommit)
        #expect(generated.manifest.coreImageCount == 152)
        #expect(generated.manifest.frames.count == 152)
        #expect(Set(generated.manifest.frames.map(\.phase)) == Set([0, 0.25, 0.5, 0.75]))
        #expect(Set(generated.manifest.frames.map(\.view)) == Set(EvidenceView.allCases))
        #expect(generated.manifest.viewport.widthPoints == 393)
        #expect(generated.manifest.viewport.heightPoints == 852)
        #expect(generated.manifest.viewport.scale == 1)
        #expect(generated.manifest.artifacts.count >= 155)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("metrics.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("contact-sheets/breadth.png").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("contact-sheets/continuity.png").path))
        #expect(try EvidencePackage.verify(
            directory: directory,
            expectedSourceCommit: canonicalTestCommit
        ) == generated.packageHash)
    }

    @Test("visible-v1 generation rejects a manifest with eleven breadth fixtures")
    func generationRejectsMissingBreadthFixture() throws {
        let malformed = try mutatedVisibleManifest { json in
            var breadth = try #require(json["breadth"] as? [[String: Any]])
            breadth.removeLast()
            json["breadth"] = breadth
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-incomplete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.generateComposition(
                manifest: malformed,
                sourceCommit: canonicalTestCommit,
                outputDirectory: directory,
                renderConfiguration: .init(scale: 1, overlays: [])
            )
        }
    }

    @Test("visible-v1 generation rejects reordered fixtures and changed phase, stage, or authority metadata")
    func generationRejectsOtherCanonicalCorpusMutations() throws {
        let malformedManifests = try [
            mutatedVisibleManifest { json in
                var breadth = try #require(json["breadth"] as? [[String: Any]])
                breadth.swapAt(0, 1)
                json["breadth"] = breadth
            },
            mutatedVisibleManifest { json in
                json["phases"] = [0, 0.25, 0.5, 0.80]
            },
            mutatedVisibleManifest { json in
                var continuity = try #require(json["continuity"] as? [String: Any])
                var stages = try #require(continuity["stages"] as? [[String: Any]])
                stages[6]["actorCount"] = 7
                continuity["stages"] = stages
                json["continuity"] = continuity
            },
            mutatedVisibleManifest { json in
                json["nonce"] = "substituted-visible-nonce"
            },
            mutatedVisibleManifest { json in
                json["specificationCommit"] = String(repeating: "0", count: 40)
            },
            mutatedVisibleManifest { json in
                var stress = try #require(json["stress"] as? [[String: Any]])
                stress.removeLast()
                json["stress"] = stress
            },
        ]

        for (index, malformed) in malformedManifests.enumerated() {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("editorial-field-invalid-\(index)-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            #expect(throws: EvidencePackageError.self) {
                try EvidencePackage.generateComposition(
                    manifest: malformed,
                    sourceCommit: canonicalTestCommit,
                    outputDirectory: directory,
                    renderConfiguration: .init(scale: 1, overlays: [])
                )
            }
        }
    }

    @Test("verification rejects checksum-valid corpus, manifest, and metrics substitutions")
    func verifyRejectsResealedSemanticSubstitution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-semantic-\(UUID().uuidString)", isDirectory: true)
        let canonicalDirectory = root.appendingPathComponent("canonical", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try EvidencePackage.generateComposition(
            manifest: .visibleV1(),
            sourceCommit: canonicalTestCommit,
            outputDirectory: canonicalDirectory,
            renderConfiguration: .init(scale: 1, overlays: [])
        )

        let corpusForgery = root.appendingPathComponent("corpus-forgery", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: corpusForgery)
        let incomplete = try mutatedVisibleManifest { json in
            var breadth = try #require(json["breadth"] as? [[String: Any]])
            breadth.removeLast()
            json["breadth"] = breadth
        }
        try incomplete.canonicalJSON().write(
            to: corpusForgery.appendingPathComponent("corpus-manifest.json"),
            options: .atomic
        )
        _ = try EvidencePackage.seal(directory: corpusForgery)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: corpusForgery, expectedSourceCommit: canonicalTestCommit)
        }

        let manifestForgery = root.appendingPathComponent("manifest-forgery", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: manifestForgery)
        _ = try rewriteJSON(manifestForgery.appendingPathComponent("manifest.json")) { json in
            var frames = try #require(json["frames"] as? [[String: Any]])
            frames.removeLast()
            json["frames"] = frames
            json["coreImageCount"] = 151
        }
        _ = try EvidencePackage.seal(directory: manifestForgery)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: manifestForgery, expectedSourceCommit: canonicalTestCommit)
        }

        let metricsForgery = root.appendingPathComponent("metrics-forgery", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: metricsForgery)
        let metricsData = try rewriteJSON(metricsForgery.appendingPathComponent("metrics.json")) { json in
            json["breadthSceneCount"] = 47
        }
        _ = try rewriteJSON(metricsForgery.appendingPathComponent("manifest.json")) { json in
            var artifacts = try #require(json["artifacts"] as? [[String: Any]])
            let index = try #require(artifacts.firstIndex { $0["path"] as? String == "metrics.json" })
            artifacts[index]["byteCount"] = metricsData.count
            artifacts[index]["sha256"] = sha256Hex(metricsData)
            json["artifacts"] = artifacts
        }
        _ = try EvidencePackage.seal(directory: metricsForgery)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: metricsForgery, expectedSourceCommit: canonicalTestCommit)
        }

        let pathForgery = root.appendingPathComponent("path-forgery", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: pathForgery)
        let missingPath = "renders/breadth/breadth-11-phase-075-tile@1x.png"
        try FileManager.default.removeItem(at: pathForgery.appendingPathComponent(missingPath))
        _ = try rewriteJSON(pathForgery.appendingPathComponent("manifest.json")) { json in
            var artifacts = try #require(json["artifacts"] as? [[String: Any]])
            artifacts.removeAll { $0["path"] as? String == missingPath }
            json["artifacts"] = artifacts
        }
        _ = try EvidencePackage.seal(directory: pathForgery)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: pathForgery, expectedSourceCommit: canonicalTestCommit)
        }
    }

    @Test("verification rejects a checksum-valid tile swapped from another scene")
    func verifyRejectsCrossSceneTileSubstitution() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-tile-swap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try EvidencePackage.generateComposition(
            manifest: .visibleV1(),
            sourceCommit: canonicalTestCommit,
            outputDirectory: directory,
            renderConfiguration: .init(scale: 1, overlays: [])
        )

        let targetPath = "renders/breadth/breadth-00-phase-000-tile@1x.png"
        let substitutedPath = "renders/breadth/breadth-01-phase-000-tile@1x.png"
        let substituted = try Data(contentsOf: directory.appendingPathComponent(substitutedPath))
        try substituted.write(to: directory.appendingPathComponent(targetPath), options: .atomic)
        _ = try rewriteJSON(directory.appendingPathComponent("manifest.json")) { json in
            var artifacts = try #require(json["artifacts"] as? [[String: Any]])
            let index = try #require(artifacts.firstIndex { $0["path"] as? String == targetPath })
            artifacts[index]["byteCount"] = substituted.count
            artifacts[index]["sha256"] = sha256Hex(substituted)
            json["artifacts"] = artifacts
        }
        _ = try EvidencePackage.seal(directory: directory)

        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: directory, expectedSourceCommit: canonicalTestCommit)
        }
    }

    @Test("verification rejects checksum-valid forged and empty provenance metadata")
    func verifyRejectsForgedProvenance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-provenance-\(UUID().uuidString)", isDirectory: true)
        let canonicalDirectory = root.appendingPathComponent("canonical", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try EvidencePackage.generateComposition(
            manifest: .visibleV1(),
            sourceCommit: canonicalTestCommit,
            outputDirectory: canonicalDirectory,
            renderConfiguration: .init(scale: 1, overlays: [])
        )
        #expect(try EvidencePackage.verify(
            directory: canonicalDirectory,
            expectedSourceCommit: canonicalTestCommit
        ).count == 64)

        let invalidCommit = root.appendingPathComponent("invalid-commit", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: invalidCommit)
        _ = try rewriteJSON(invalidCommit.appendingPathComponent("manifest.json")) { json in
            json["sourceCommit"] = "forged-nonempty"
        }
        _ = try EvidencePackage.seal(directory: invalidCommit)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: invalidCommit, expectedSourceCommit: canonicalTestCommit)
        }

        let emptyMetadata = root.appendingPathComponent("empty-metadata", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: emptyMetadata)
        _ = try rewriteJSON(emptyMetadata.appendingPathComponent("manifest.json")) { json in
            json["toolchain"] = ""
            json["device"] = ""
            json["operatingSystem"] = ""
        }
        _ = try EvidencePackage.seal(directory: emptyMetadata)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: emptyMetadata, expectedSourceCommit: canonicalTestCommit)
        }

        let mismatchedCommit = root.appendingPathComponent("mismatched-commit", isDirectory: true)
        try FileManager.default.copyItem(at: canonicalDirectory, to: mismatchedCommit)
        _ = try rewriteJSON(mismatchedCommit.appendingPathComponent("manifest.json")) { json in
            json["sourceCommit"] = otherTestCommit
        }
        _ = try EvidencePackage.seal(directory: mismatchedCommit)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: mismatchedCommit, expectedSourceCommit: canonicalTestCommit)
        }

        let invalidGeneration = root.appendingPathComponent("invalid-generation", isDirectory: true)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.generateComposition(
                manifest: .visibleV1(),
                sourceCommit: "forged-nonempty",
                outputDirectory: invalidGeneration,
                renderConfiguration: .init(scale: 1, overlays: [])
            )
        }
    }

    private var testRecipe: CompositionRecipe {
        CompositionRecipe(
            daySeed: 42,
            grammar: .depthScatter,
            viewport: .phone,
            actors: [
                ActorCompositionRecipe(
                    eventID: "far",
                    position: .init(x: 0.22, y: 0.20),
                    diameter: 0.12,
                    depth: 0.10,
                    localBlur: 0.004,
                    cropAllowance: 0,
                    drawOrder: 0
                ),
                ActorCompositionRecipe(
                    eventID: "middle",
                    position: .init(x: 0.56, y: 0.48),
                    diameter: 0.28,
                    depth: 0.50,
                    localBlur: 0,
                    cropAllowance: 0,
                    drawOrder: 1
                ),
                ActorCompositionRecipe(
                    eventID: "foreground",
                    position: .init(x: 0.80, y: 0.75),
                    diameter: 0.62,
                    depth: 0.90,
                    localBlur: 0.055,
                    cropAllowance: 0.25,
                    drawOrder: 2
                ),
            ]
        )
    }

    private func localBlurRecipe(firstBlur: Double) -> CompositionRecipe {
        CompositionRecipe(
            daySeed: 9,
            grammar: .openField,
            viewport: .phone,
            actors: [
                ActorCompositionRecipe(
                    eventID: "left",
                    position: .init(x: 0.20, y: 0.25),
                    diameter: 0.28,
                    depth: 0.8,
                    localBlur: firstBlur,
                    cropAllowance: 0,
                    drawOrder: 1
                ),
                ActorCompositionRecipe(
                    eventID: "right",
                    position: .init(x: 0.82, y: 0.82),
                    diameter: 0.18,
                    depth: 0.4,
                    localBlur: 0,
                    cropAllowance: 0,
                    drawOrder: 0
                ),
            ]
        )
    }
}

private func mutatedVisibleManifest(
    _ mutate: (inout [String: Any]) throws -> Void
) throws -> CorpusManifest {
    let canonical = try CorpusManifest.visibleV1().canonicalJSON()
    var json = try #require(
        JSONSerialization.jsonObject(with: canonical) as? [String: Any]
    )
    try mutate(&json)
    let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    return try JSONDecoder().decode(CorpusManifest.self, from: data)
}

@discardableResult
private func rewriteJSON(
    _ url: URL,
    mutate: (inout [String: Any]) throws -> Void
) throws -> Data {
    var json = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    try mutate(&json)
    var data = try JSONSerialization.data(
        withJSONObject: json,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
    return data
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private enum TestImageError: Error {
    case cannotDecodePNG
    case cannotCreateContext
}

private func decodePNG(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw TestImageError.cannotDecodePNG }
    return image
}

private func rgbaBytes(_ image: CGImage) throws -> Data {
    let bytesPerRow = image.width * 4
    var data = Data(count: bytesPerRow * image.height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let created = data.withUnsafeMutableBytes { bytes in
        CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.withDrawn(image)
    }
    guard created == true else { throw TestImageError.cannotCreateContext }
    return data
}

private extension CGContext {
    func withDrawn(_ image: CGImage) -> Bool {
        draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
}
