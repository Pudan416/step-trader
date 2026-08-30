import CoreGraphics
import Foundation
import ImageIO
import Testing
import EditorialFieldCore
import EditorialFieldEvidence
import EditorialFieldRender

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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifact = directory.appendingPathComponent("sample.bin")
        try Data([0x10, 0x20, 0x30]).write(to: artifact)
        let packageHash = try EvidencePackage.seal(directory: directory)
        #expect(try EvidencePackage.verify(directory: directory) == packageHash)

        try Data([0x10, 0x20, 0x30, 0x40]).write(to: artifact)
        #expect(throws: EvidencePackageError.self) {
            try EvidencePackage.verify(directory: directory)
        }
    }

    @Test("composition writer emits the complete sealed package contract")
    func compositionWriterProducesReviewFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editorial-field-composition-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generated = try EvidencePackage.generateComposition(
            manifest: .visibleV1(),
            sourceCommit: "0123456789abcdef",
            outputDirectory: directory,
            renderConfiguration: .init(scale: 1, overlays: [])
        )

        #expect(generated.manifest.sourceCommit == "0123456789abcdef")
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
        #expect(try EvidencePackage.verify(directory: directory) == generated.packageHash)
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
