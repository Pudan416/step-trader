import XCTest
import MetalKit
import SwiftUI
import ObjectiveC
@testable import Nowhere

final class HappeningPaletteTileSurfaceTests: XCTestCase {
    @MainActor
    func testFixedTilesMatchMonolithicNativePixelsAcrossBoundariesAndStates() async throws {
        await Task.detached { DayObjectsRenderer.prepareResources() }.value
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        for collection in [NativeAtlasDailyStyle.Collection.circles, .blobs, .flowers, .blurredSquares, .glowingContours] {
        let (scene, base) = try fixture(collection: collection)
        for state in [HappeningPaletteSlotVisualState.available, .added, .additionPreview, .removalPreview] {
            var presentation = base
            presentation = HappeningPaletteRenderPresentation(slots: base.slots.map {
                .init(happeningID: $0.happeningID, assignment: $0.assignment, visualState: state, source: $0.source)
            }, viewportSize: base.viewportSize, reduceMotion: true, isTransitionActive: false,
               backgroundRevision: 0, usesSharedGeometry: true)
            let referenceRenderer = try XCTUnwrap(DayObjectsRenderer.create(scene: scene,
                environment: .init(motionEnergy: 0.625, visualClarity: 0.625), presentationMode: .happeningPalette(presentation)))
            let reference: MTLTexture? = await withCheckedContinuation { continuation in
                referenceRenderer.renderOffscreen(size: presentation.viewportSize, pointScale: 1, elapsedTime: 1) { texture, _ in
                    continuation.resume(returning: texture)
                }
            }
            let referenceBytes = pixels(try XCTUnwrap(reference))
            let renderer = try XCTUnwrap(HappeningPaletteTileRenderer(device: device))
            let tiles = HappeningPaletteTilePlan.tiles(worldSize: presentation.viewportSize,
                visibleRect: CGRect(origin: .zero, size: presentation.viewportSize))
            let outputs = try tiles.map { tile -> HappeningPaletteTileRenderer.Output in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 256, height: 256, mipmapped: false)
                descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
                return .init(tile: tile, texture: try XCTUnwrap(device.makeTexture(descriptor: descriptor)))
            }
            var timeline = HappeningPaletteTransitionTimeline()
            timeline.update(to: presentation, elapsed: 1)
            let buffer = try XCTUnwrap(renderer.encode(outputs: outputs, scene: scene, presentation: presentation,
                sample: timeline.sample(at: 1), at: 1, pointScale: 1))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                buffer.addCompletedHandler { _ in continuation.resume() }
                buffer.commit()
            }
            XCTAssertEqual(buffer.status, .completed)
            var differences = 0
            var maximumDifference = 0
            for output in outputs {
                let bytes = pixels(output.texture)
                for y in 0..<256 { for x in 0..<256 { for c in 0..<4 {
                    let local = (y * 256 + x) * 4 + c
                    let world = ((output.tile.row * 256 + y) * 512 + output.tile.column * 256 + x) * 4 + c
                    let difference = abs(Int(bytes[local]) - Int(referenceBytes[world]))
                    maximumDifference = max(maximumDifference, difference)
                    if difference > 3 { differences += 1 }
                } } }
            }
            XCTAssertLessThanOrEqual(differences, 128, "Tile crops must retain native contour, material, alpha and world grain: \(state), max \(maximumDifference), collection \(collection)")
        }
        }
    }

    @MainActor
    func testNativePanKeepsSurvivingTilesAndTheirPixelsWithoutSubmittingAnotherFrame() async throws {
        let (scene, small) = try fixture()
        var presentation = HappeningPaletteRenderPresentation(slots: small.slots,
            viewportSize: CGSize(width: 1536, height: 1536), reduceMotion: true,
            isTransitionActive: false, backgroundRevision: 0, usesSharedGeometry: true)
        presentation.visibleRect = CGRect(x: 200, y: 200, width: 390, height: 844)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIViewController(); window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = presentation.viewportSize
        controller.view.addSubview(scroll)
        let surface = HappeningPaletteTileSurfaceView(frame: CGRect(origin: .zero, size: presentation.viewportSize))
        scroll.addSubview(surface)
        surface.update(scene: scene, presentation: presentation, isActive: true)
        scroll.contentOffset = CGPoint(x: 200, y: 200)
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(10))
            window.layoutIfNeeded()
            if surface.submittedFrameCount > 0 && !surface.isAnimatingFrames { break }
        }
        XCTAssertGreaterThan(surface.submittedFrameCount, 0, "Initial native pixels must actually be submitted")
        let previous = surface.residentTiles
        let submitted = surface.submittedFrameCount
        // A small pan stays inside the overscan's resident tile range. The
        // existing images must follow native scrolling with no redraw/camera.
        scroll.contentOffset = CGPoint(x: 210, y: 210)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(surface.submittedFrameCount, submitted, "A static pan must not re-render surviving tiles")
        for (tile, view) in previous where surface.residentTiles[tile] != nil {
            XCTAssertTrue(surface.residentTiles[tile] === view)
            XCTAssertEqual(view.frame, tile.frame)
            let screenOrigin = view.convert(CGPoint.zero, to: controller.view)
            XCTAssertEqual(screenOrigin.x, tile.frame.minX - 210, accuracy: 1)
            XCTAssertEqual(screenOrigin.y, tile.frame.minY - 210, accuracy: 1)
        }
        presentation = HappeningPaletteRenderPresentation(slots: presentation.slots.map {
            .init(happeningID: $0.happeningID, assignment: $0.assignment, visualState: .added, source: $0.source)
        }, viewportSize: presentation.viewportSize, reduceMotion: true, isTransitionActive: false,
           backgroundRevision: 1, usesSharedGeometry: true, visibleRect: presentation.visibleRect)
        let unavailableLayer = try XCTUnwrap(previous.keys.sorted {
            $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
        }.last.flatMap { previous[$0]?.layer as? CAMetalLayer })
        let selector = NSSelectorFromString("nextDrawable")
        let method = try XCTUnwrap(class_getInstanceMethod(CAMetalLayer.self, selector))
        let originalIMP = method_getImplementation(method)
        typealias Next = @convention(c) (AnyObject, Selector) -> AnyObject?
        let original = unsafeBitCast(originalIMP, to: Next.self)
        let gateLock = NSLock()
        var withholdsDrawable = true
        var acquisitionCount = 0
        var acquiredOnMain = false
        let block: @convention(block) (AnyObject) -> AnyObject? = { object in
            let shouldWithhold = gateLock.withLock {
                if object === unavailableLayer {
                    acquisitionCount += 1
                    acquiredOnMain = acquiredOnMain || Thread.isMainThread
                }
                return withholdsDrawable
            }
            if object === unavailableLayer && shouldWithhold { return nil }
            return original(object, selector)
        }
        let replacement = imp_implementationWithBlock(block)
        method_setImplementation(method, replacement)
        defer { method_setImplementation(method, originalIMP); imp_removeBlock(replacement) }
        surface.update(scene: scene, presentation: presentation, isActive: true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(surface.submittedFrameCount, submitted,
            "A missing tile must hold the whole dirty batch, never show adjacent tiles from different animation times")
        let acquisition = gateLock.withLock { () -> (Int, Bool) in
            withholdsDrawable = false
            return (acquisitionCount, acquiredOnMain)
        }
        XCTAssertGreaterThan(acquisition.0, 0)
        XCTAssertFalse(acquisition.1, "Drawable acquisition must never wait on the main thread")
        // Start a fresh transition after the missing-drawable exercise so
        // runner load cannot consume the short reduced-motion fade window.
        presentation = HappeningPaletteRenderPresentation(slots: presentation.slots.map {
            .init(happeningID: $0.happeningID, assignment: $0.assignment, visualState: .available, source: $0.source)
        }, viewportSize: presentation.viewportSize, reduceMotion: true, isTransitionActive: false,
           backgroundRevision: 2, usesSharedGeometry: true, visibleRect: presentation.visibleRect)
        surface.update(scene: scene, presentation: presentation, isActive: true)
        var observedAnimation = false
        var lastAnimatingSubmission = surface.submittedFrameCount
        for _ in 0..<1000 {
            try await Task.sleep(for: .milliseconds(1))
            if surface.isAnimatingFrames {
                observedAnimation = true
                lastAnimatingSubmission = surface.submittedFrameCount
            } else if observedAnimation { break }
        }
        XCTAssertTrue(observedAnimation, "The real reduction-motion transition must run")
        XCTAssertFalse(surface.isAnimatingFrames)
        XCTAssertGreaterThan(surface.submittedFrameCount, submitted, "State changes must submit fresh drawable images")
        XCTAssertGreaterThan(surface.submittedFrameCount, lastAnimatingSubmission,
            "Submit the exact terminal sample before stopping, rather than retaining a partly faded frame")
        surface.update(scene: scene, presentation: presentation, isActive: false)
        XCTAssertFalse(surface.isAnimatingFrames)
        surface.removeFromSuperview()
        XCTAssertTrue(surface.residentTiles.isEmpty, "Detach releases drawable residency")
    }

    private func pixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { ptr in
            texture.getBytes(ptr.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return bytes
    }

    private func fixture(collection: NativeAtlasDailyStyle.Collection = .circles) throws -> (DayObjectScene, HappeningPaletteRenderPresentation) {
        let happenings = (0..<4).map { Happening(id: "tile_\($0)", title: "Tile \($0)", isBuiltIn: true) }
        let input = DayObjectSceneInput(dayKey: "2026-10-21", identity: "tile-pixels", eventIDs: [],
            motionEnergy: 0.625, visualClarity: 0.625, usesEditorialField: true,
            nativeAtlasRecipe: .makeDaily(dayKey: "2026-10-21", paletteCategories: ModernPaletteSelection.all, collection: collection))
        let assignments = HappeningEditorialAssignmentResolver.assignments(happenings: happenings, baseInput: input, colorNonce: 7)
        let centers = [CGPoint(x: 245, y: 240), CGPoint(x: 290, y: 255), CGPoint(x: 246, y: 310), CGPoint(x: 125, y: 120)]
        let slots = try happenings.enumerated().map { index, happening in
            HappeningPaletteRenderSlot(happeningID: happening.id, assignment: try XCTUnwrap(assignments[happening.id]),
                visualState: .available, source: .init(index: index, center: centers[index], radius: 68))
        }
        return (DayObjectScene.make(input: input), .init(slots: slots, viewportSize: CGSize(width: 512, height: 512),
            reduceMotion: true, isTransitionActive: false, backgroundRevision: 0, usesSharedGeometry: true))
    }
}
