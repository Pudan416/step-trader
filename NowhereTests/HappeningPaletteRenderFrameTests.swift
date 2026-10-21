import XCTest
import UIKit
import MetalKit
import SwiftUI
import ObjectiveC
@testable import Nowhere

final class HappeningPaletteRenderFrameTests: XCTestCase {
    func testViewportCameraKeepsNativeRenderCenterAndCapsuleHitAlignedIncludingOverscroll() throws {
        let assignment = try XCTUnwrap(makePresentation().slots.first?.assignment)
        let world = HappeningFieldLayout.Layout(sources: [.init(index: 0, center: CGPoint(x: 200, y: 300), radius: 64)],
            labelFrames: [], contourBounds: .zero, dockAnchor: .zero, completionBounds: nil,
            contentSize: CGSize(width: 1852, height: 1969))
        for (camera, expectedCenter) in [(CGPoint(x: 80, y: 60), CGPoint(x: 120, y: 240)),
                                         (CGPoint(x: -30, y: -50), CGPoint(x: 230, y: 350))] {
            let viewport = CGSize(width: 390, height: 844)
            let projected = world.translated(by: camera)
            let presentation = HappeningPaletteRenderPresentation(slots: [.init(happeningID: "camera-probe",
                assignment: assignment, visualState: .removalPreview, source: projected.sources[0])],
                viewportSize: viewport, reduceMotion: true, isTransitionActive: false,
                backgroundRevision: 0, usesSharedGeometry: true)
            let actor = try XCTUnwrap(HappeningPaletteRenderFrame.make(presentation: presentation,
                scene: makeScene(), elapsed: 1).actors.first)
            let rendered = CGPoint(x: Double(actor.gpuActor.position.x) * 390 + 195,
                                   y: 422 - Double(actor.gpuActor.position.y) * 390)
            XCTAssertEqual(rendered.x, expectedCenter.x, accuracy: 0.001)
            XCTAssertEqual(rendered.y, expectedCenter.y, accuracy: 0.001)
            let hit = HappeningPickerHitShape.make(side: 128, assignment: assignment,
                state: .removalPreview, reduceMotion: true)
            let hitFrame = CGRect(x: expectedCenter.x - hit.size.width / 2,
                y: expectedCenter.y - hit.size.height / 2, width: hit.size.width, height: hit.size.height)
            XCTAssertTrue(hit.path(in: hitFrame).contains(rendered))
            XCTAssertTrue(hit.path(in: hitFrame).contains(CGPoint(x: rendered.x + 42, y: rendered.y + 52)),
                "The visible lower capsule edge follows the same camera as its rendered figure")
            XCTAssertEqual(world.sources[0].center, CGPoint(x: 200, y: 300), "World labels and hit geometry stay unchanged")
            XCTAssertEqual(projected.sources[0].radius, 64)
            XCTAssertEqual(presentation.viewportSize, CGSize(width: 390, height: 844))
        }
    }

    /// This checks the real native hierarchy and the last submitted frame's
    /// camera, not GPU presentation time (unavailable on the simulator SDK).
    @MainActor
    func testNativeScrollKeepsDrawableWorldOriginAtLastSubmittedCameraWhileNextFrameIsDelayed() async throws {
        await Task.detached(priority: .userInitiated) { DayObjectsRenderer.prepareResources() }.value
        let viewport = CGSize(width: 390, height: 844)
        let layout = HappeningFieldLayout.layout(count: 106, in: viewport, safeInsets: EdgeInsets())
        let happenings = (0..<10).map { Happening(id: "h\($0)", title: "Happening \($0)", isBuiltIn: true) }
        let assignments = Dictionary(uniqueKeysWithValues: makePresentation().slots.map { ($0.happeningID, $0.assignment) })
        let input = editorialInput()
        let palette = HappeningPaletteView(happenings: happenings, assignments: assignments,
            layout: layout, artworkForLayout: { world, moving, rect in
                let projected = world.translated(by: rect.origin)
                let slots = happenings.enumerated().map { index, happening in
                    HappeningPaletteRenderSlot(happeningID: happening.id, assignment: assignments[happening.id]!,
                        visualState: .available, source: projected.sources[index])
                }
                return AnyView(DayObjectsView(sceneInput: input, presentationMode: .happeningPalette(
                    HappeningPaletteRenderPresentation(slots: slots, viewportSize: rect.size,
                        reduceMotion: true, isTransitionActive: moving, backgroundRevision: 0,
                        usesSharedGeometry: true, cameraOrigin: rect.origin))))
            }, interaction: HappeningPaletteInteractionState(), addedIDs: [], instruction: nil, onActivate: { _ in })
        let host = UIHostingController(rootView: palette.ignoresSafeArea().environment(\.scenePhase, .active))
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: viewport)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        func flushLayout() {
            window.setNeedsLayout(); window.layoutIfNeeded()
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            CATransaction.flush()
        }
        flushLayout()
        var readyView: DayObjectsDrawableView?
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(20))
            flushLayout()
            if let view = descendant(DayObjectsDrawableView.self, in: host.view),
               view.paletteResizeHandoff.presentedCameraOrigin != nil,
               !view.paletteResizeHandoff.isPending { readyView = view; break }
        }
        let drawable = try XCTUnwrap(readyView, "The real renderer must submit its initial frame")
        let scroll = try XCTUnwrap(descendant(UIScrollView.self, in: host.view))
        let initialCamera = try XCTUnwrap(drawable.paletteResizeHandoff.presentedCameraOrigin)
        var nativeWorld: UIView = drawable
        while let parent = nativeWorld.superview, parent !== scroll { nativeWorld = parent }
        XCTAssertTrue(nativeWorld.superview === scroll)
        // A real, fixed reference beside the SwiftUI field (not inside the
        // movable artwork ancestor) makes layer-to-world separation observable.
        let worldReference = UIView(frame: CGRect(x: 200, y: 300, width: 1, height: 1))
        worldReference.isUserInteractionEnabled = false
        nativeWorld.addSubview(worldReference)
        defer { worldReference.removeFromSuperview() }
        let initialWorldOrigin = drawable.convert(CGPoint.zero, to: worldReference)
        let initialOffset = scroll.contentOffset
        // Withhold this fixture's actual renderer entry point. Coordinator
        // updates may reinstall its delegate, so replacing the delegate alone
        // cannot delay a frame. No presentation result is manufactured.
        let selector = NSSelectorFromString("drawInMTKView:")
        let method = try XCTUnwrap(class_getInstanceMethod(DayObjectsRenderer.self, selector))
        let originalIMP = method_getImplementation(method)
        typealias Draw = @convention(c) (AnyObject, Selector, MTKView) -> Void
        let original = unsafeBitCast(originalIMP, to: Draw.self)
        var withholdsFrames = true
        let block: @convention(block) (AnyObject, MTKView) -> Void = { object, view in
            if view === drawable && withholdsFrames { return }
            original(object, selector, view)
        }
        let replacementIMP = imp_implementationWithBlock(block)
        method_setImplementation(method, replacementIMP)
        defer {
            method_setImplementation(method, originalIMP)
            imp_removeBlock(replacementIMP)
        }
        for delta in [CGPoint(x: 80, y: 60), CGPoint(x: 140, y: 110), CGPoint(x: -20, y: -30)] {
            let previousRequest = drawable.paletteResizeHandoff.requestedCameraOrigin
            scroll.setContentOffset(CGPoint(x: initialOffset.x + delta.x, y: initialOffset.y + delta.y), animated: false)
            let beforeDelivery = drawable.convert(CGPoint.zero, to: worldReference)
            XCTAssertEqual(beforeDelivery.x, initialWorldOrigin.x, accuracy: 1)
            XCTAssertEqual(beforeDelivery.y, initialWorldOrigin.y, accuracy: 1)
            // Deliver the async viewport observation/layout, but no new frame.
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(10))
                flushLayout()
                if drawable.paletteResizeHandoff.requestedCameraOrigin != previousRequest { break }
            }
            XCTAssertNotEqual(drawable.paletteResizeHandoff.requestedCameraOrigin, previousRequest,
                "The real scroll observation must deliver the changed viewport")
            XCTAssertEqual(drawable.paletteResizeHandoff.presentedCameraOrigin, initialCamera)
            let afterDelivery = drawable.convert(CGPoint.zero, to: worldReference)
            XCTAssertEqual(afterDelivery.x, initialWorldOrigin.x, accuracy: 1,
                "A new requested camera must not move the old image away from native world labels")
            XCTAssertEqual(afterDelivery.y, initialWorldOrigin.y, accuracy: 1)
        }
        withholdsFrames = false
        drawable.synchronizePaletteResizeIfNeeded()
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(10))
            flushLayout()
            if !drawable.paletteResizeHandoff.isPending { break }
        }
        XCTAssertFalse(drawable.paletteResizeHandoff.isPending, "Settled viewport coverage must recover")
        let latestCamera = try XCTUnwrap(drawable.paletteResizeHandoff.presentedCameraOrigin)
        let latestOrigin = drawable.convert(CGPoint.zero, to: worldReference)
        XCTAssertEqual(latestOrigin.x - latestCamera.x, initialWorldOrigin.x - initialCamera.x, accuracy: 1)
        XCTAssertEqual(latestOrigin.y - latestCamera.y, initialWorldOrigin.y - initialCamera.y, accuracy: 1)
        XCTAssertEqual(drawable.bounds.width, scroll.bounds.width, accuracy: 1)
        XCTAssertEqual(drawable.bounds.height, scroll.bounds.height, accuracy: 1)
    }

    /// Checks actual successful draw routing, not whether a drawable has appeared onscreen.
    @MainActor
    func testUnchangedPaletteDrawsKeepTransactionPresentationWhileCanvasRemainsAsynchronous() async throws {
        await Task.detached(priority: .userInitiated) { DayObjectsRenderer.prepareResources() }.value
        let presentation = makePresentation(reduceMotion: true)
        let input = DayObjectSceneInput(dayKey: "2026-10-21", identity: "palette-presentation-routing", eventIDs: [],
            motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true,
            nativeAtlasRecipe: .makeDaily(dayKey: "2026-10-21", paletteCategories: ModernPaletteSelection.all, collection: .circles))
        let scene = DayObjectScene.make(input: input)
        let environment = DayObjectEnvironment(motionEnergy: 0.5, visualClarity: 1)
        let renderer = try XCTUnwrap(DayObjectsRenderer.create(scene: scene, environment: environment,
            presentationMode: .happeningPalette(presentation)))
        renderer.setAnimating(false)
        let probe = DayObjectsRendererPerformanceProbe()
        renderer.installPerformanceProbe(probe)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.frame = CGRect(origin: .zero, size: presentation.viewportSize)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let view = DayObjectsDrawableView(frame: .zero, device: renderer.device)
        view.autoResizeDrawable = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = renderer
        DayObjectsRenderer.configureDisplay(view)
        let surface = DayObjectsSurfaceView(drawableView: view)
        surface.frame = window.bounds
        controller.view.addSubview(surface)
        view.configurePaletteViewportSize(presentation.viewportSize, cameraOrigin: presentation.cameraOrigin)
        surface.configurePaletteViewportSize(presentation.viewportSize)
        surface.layoutIfNeeded()
        view.synchronizePaletteResizeIfNeeded()
        XCTAssertFalse(view.paletteResizeHandoff.isPending, "Initial real camera draw must complete its handoff")
        XCTAssertGreaterThan(probe.snapshot.submittedFrames, 0)
        XCTAssertTrue(view.presentsWithTransaction, "Palette layer mode must remain synchronized between draws")

        let selector = NSSelectorFromString("setPresentsWithTransaction:")
        let method = try XCTUnwrap(class_getInstanceMethod(MTKView.self, selector))
        let originalIMP = method_getImplementation(method)
        typealias SetPresentation = @convention(c) (AnyObject, Selector, Bool) -> Void
        let original = unsafeBitCast(originalIMP, to: SetPresentation.self)
        var requestedModes: [Bool] = []
        let block: @convention(block) (AnyObject, Bool) -> Void = { object, value in
            if object === view { requestedModes.append(value) }
            original(object, selector, value)
        }
        let replacementIMP = imp_implementationWithBlock(block)
        method_setImplementation(method, replacementIMP)
        defer { method_setImplementation(method, originalIMP); imp_removeBlock(replacementIMP) }
        let beforePalette = probe.snapshot.submittedFrames
        view.draw()
        view.draw()
        XCTAssertEqual(probe.snapshot.submittedFrames - beforePalette, 2, "Both unchanged-camera draws must encode successfully")
        XCTAssertTrue(requestedModes.contains(true), "Successful palette draws must use transaction presentation")
        XCTAssertFalse(requestedModes.contains(false), "Palette draws must not return the layer to asynchronous mode")
        XCTAssertTrue(view.presentsWithTransaction, "Keep the transaction mode until the palette is dismissed")

        requestedModes.removeAll()
        view.configurePaletteViewportSize(nil)
        surface.configurePaletteViewportSize(nil)
        renderer.update(scene: scene, environment: environment)
        let beforeCanvas = probe.snapshot.submittedFrames
        view.draw()
        XCTAssertEqual(probe.snapshot.submittedFrames - beforeCanvas, 1, "Canvas control must encode successfully")
        XCTAssertFalse(requestedModes.contains(true), "Canvas retains its asynchronous presentation path")
    }

    func testConfirmationPreviewsStayNeutralDuringRevealAndKeepBreathing() throws {
        let scene = makeScene()
        for state in [HappeningPaletteSlotVisualState.additionPreview, .removalPreview] {
            let initial = makePresentation(stateForFirstSlot: state == .additionPreview ? .available : .added)
            let pending = makePresentation(stateForFirstSlot: state)
            var timeline = HappeningPaletteTransitionTimeline()
            timeline.update(to: initial, elapsed: 0)
            timeline.update(to: pending, elapsed: 1)
            for time in [1.08, 1.2, 1.4] {
                let frame = HappeningPaletteRenderFrame.make(presentation: pending, scene: scene,
                    elapsed: time, timeline: timeline)
                XCTAssertEqual(try actor(for: "h0", in: frame).gpuActor.presentationSaturation, 0,
                    "No color should flash while revealing a confirmation preview")
            }
            let small = HappeningPaletteRenderFrame.make(presentation: pending, scene: scene, elapsed: 1.6)
            let large = HappeningPaletteRenderFrame.make(presentation: pending, scene: scene, elapsed: 2.4)
            XCTAssertNotEqual(try actor(for: "h0", in: small).halfSize, try actor(for: "h0", in: large).halfSize)
            XCTAssertEqual(try actor(for: "h2", in: small).halfSize, try actor(for: "h2", in: large).halfSize,
                "Already added items must not pulse with the pending item")
            XCTAssertTrue(DayObjectsPresentationMode.happeningPalette(pending).prefersSixtyFPS)
        }
    }

    func testCancellingPreviewDoesNotRevealColorOnTheWayBackToACircle() throws {
        let pending = makePresentation(stateForFirstSlot: .additionPreview)
        let available = makePresentation(stateForFirstSlot: .available)
        var timeline = HappeningPaletteTransitionTimeline()
        timeline.update(to: pending, elapsed: 0)
        timeline.update(to: available, elapsed: 1)
        let frame = HappeningPaletteRenderFrame.make(presentation: available, scene: makeScene(), elapsed: 1.1, timeline: timeline)
        XCTAssertEqual(try actor(for: "h0", in: frame).gpuActor.presentationSaturation, 0)
    }

    func testReducedMotionConfirmationIsNeutralAndDoesNotPulseOrKeepRendering() throws {
        let pending = makePresentation(stateForFirstSlot: .additionPreview, reduceMotion: true)
        let first = HappeningPaletteRenderFrame.make(presentation: pending, scene: makeScene(), elapsed: 1.6)
        let second = HappeningPaletteRenderFrame.make(presentation: pending, scene: makeScene(), elapsed: 2.4)
        XCTAssertEqual(try actor(for: "h0", in: first).gpuActor.presentationSaturation, 0)
        XCTAssertEqual(try actor(for: "h0", in: first).halfSize, try actor(for: "h0", in: second).halfSize)
        XCTAssertFalse(DayObjectsPresentationMode.happeningPalette(pending).prefersSixtyFPS)
    }

    func testBuilderMapsTenPaletteSlotsToProductionActors() throws {
        let scene = makeScene()
        let presentation = makePresentation()

        let frame = HappeningPaletteRenderFrame.make(
            presentation: presentation,
            scene: scene,
            elapsed: 2
        )

        XCTAssertEqual(frame.actors.count, 10)

        let available = try actor(for: "h0", in: frame)
        let preview = try actor(for: "h1", in: frame)
        let added = try actor(for: "h2", in: frame)
        let removal = try actor(for: "h3", in: frame)
        let assignment = try XCTUnwrap(presentation.slots.first { $0.happeningID == "h1" }?.assignment)

        XCTAssertEqual(available.gpuActor.paletteMorph, 0)
        XCTAssertEqual(preview.gpuActor.paletteMorph, 1)
        XCTAssertEqual(preview.gpuActor.shape, assignment.shape.numericValue)
        XCTAssertEqual(preview.gpuActor.silhouetteVariant, assignment.silhouette.variant)
        XCTAssertEqual(preview.halfSize.y / preview.halfSize.x, assignment.silhouette.aspect, accuracy: 0.0001)
        XCTAssertEqual(preview.gpuAppearance, assignment.material.gpuAppearance)
        XCTAssertEqual(added.gpuActor.presentationSaturation, 1, accuracy: 0.001)
        XCTAssertEqual(removal.gpuActor.removalEmphasis, 1)
        XCTAssertEqual(frame.postProcess.grainIntensity, 0, "The transparent palette overlay does not duplicate Canvas grain")
        XCTAssertEqual(frame.postProcess.blurRadius, 0)
    }

    func testDepthSortedMultiMaterialUploadKeepsEveryActorOnItsOwnAppearance() throws {
        let presentation = makePresentation()
        let frame = HappeningPaletteRenderFrame.make(
            presentation: presentation,
            scene: makeScene(),
            elapsed: 2
        )
        let upload = DayObjectsActorUpload(
            actors: frame.actors,
            resolution: SIMD2(390, 844)
        )

        XCTAssertEqual(upload.actors.map(\.appearanceIndex), (0..<10).map(UInt32.init))
        for (index, actor) in frame.actors.enumerated() {
            XCTAssertEqual(upload.appearances[index], actor.gpuAppearance)
            XCTAssertEqual(
                upload.appearances[Int(upload.actors[index].appearanceIndex)],
                actor.gpuAppearance
            )
        }
        XCTAssertGreaterThan(Set(upload.appearances.map(\.metadata)).count, 1)
    }

    func testBuilderConvertsTopLeftPalettePointsToPositiveUpMetalCoordinates() throws {
        let scene = makeScene()
        let presentation = makePresentation()
        let source = try XCTUnwrap(presentation.slots.first?.source)

        let frame = HappeningPaletteRenderFrame.make(
            presentation: presentation,
            scene: scene,
            elapsed: 0
        )
        let actor = try actor(for: "h0", in: frame)

        XCTAssertEqual(actor.gpuActor.position.x, -0.4, accuracy: 0.0001)
        // SwiftUI y grows down from the top; the actor vertex shader writes
        // positive y directly to Metal clip space, which grows upward.
        XCTAssertEqual(actor.gpuActor.position.y, 1.0, accuracy: 0.0001)
        XCTAssertEqual(actor.gpuActor.halfSize.x, Float(source.radius / 390), accuracy: 0.0001)
        let silhouette = try XCTUnwrap(presentation.slots.first?.assignment.silhouette)
        XCTAssertEqual(actor.gpuActor.halfSize.y, Float(source.radius / 390) * silhouette.aspect, accuracy: 0.0001)
    }

    func testSharedModeGeometryReachesRendererWithoutASecondSizeAnimation() throws {
        var initial = makePresentation(stateForFirstSlot: .available)
        initial.usesSharedGeometry = true
        var updated = makePresentation(stateForFirstSlot: .available,
            firstSourceOffset: CGSize(width: 64, height: 32), firstSourceRadiusDelta: 16)
        updated.usesSharedGeometry = true
        var timeline = HappeningPaletteTransitionTimeline()
        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)
        let sampled = try slot(for: "h0", in: timeline.sample(at: 1))
        XCTAssertEqual(sampled.source, updated.slots[0].source)
        XCTAssertFalse(timeline.hasActiveTransitions(at: 1))
    }

    func testTransitionInterpolatesShapeButKeepsItsCenterAttachedToTheLabel() {
        let initial = makePresentation(stateForFirstSlot: .available)
        let updated = makePresentation(
            stateForFirstSlot: .additionPreview,
            firstSourceOffset: CGSize(width: 64, height: 32),
            firstSourceRadiusDelta: 16
        )
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)
        let start = try! slot(for: "h0", in: timeline.sample(at: 1))
        let quarter = try! slot(for: "h0", in: timeline.sample(at: 1.085))
        let complete = try! slot(for: "h0", in: timeline.sample(at: 1.341))

        XCTAssertEqual(start.controls.paletteMorph, 0, accuracy: 0.001)
        XCTAssertEqual(start.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(start.source.center.y, 64, accuracy: 0.001)
        XCTAssertEqual(start.source.radius, 32, accuracy: 0.001)

        XCTAssertEqual(quarter.controls.paletteMorph, 0.15625, accuracy: 0.001)
        XCTAssertEqual(quarter.controls.scale, 1.009375, accuracy: 0.001)
        XCTAssertEqual(quarter.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(quarter.source.center.y, 64, accuracy: 0.001)
        XCTAssertEqual(quarter.source.radius, 34.5, accuracy: 0.001)

        XCTAssertEqual(complete.controls.paletteMorph, 1, accuracy: 0.001)
        XCTAssertEqual(complete.controls.scale, 1.06, accuracy: 0.001)
        XCTAssertEqual(complete.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(complete.source.center.y, 64, accuracy: 0.001)
        XCTAssertEqual(complete.source.radius, 48, accuracy: 0.001)
    }

    func testReduceMotionSwitchesEndpointsWithoutResumingMorphing() {
        let initial = makePresentation(reduceMotion: true)
        let updated = makePresentation(
            stateForFirstSlot: .additionPreview,
            reduceMotion: true,
            firstSourceOffset: CGSize(width: 64, height: 32),
            firstSourceRadiusDelta: 16
        )
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)

        let beforeSwitch = try! slot(for: "h0", in: timeline.sample(at: 1.099))
        let switchPoint = try! slot(for: "h0", in: timeline.sample(at: 1.10))
        let beforeFadeInCompletes = try! slot(for: "h0", in: timeline.sample(at: 1.199))
        let completed = try! slot(for: "h0", in: timeline.sample(at: 1.20))
        let afterCompletion = try! slot(for: "h0", in: timeline.sample(at: 1.50))

        XCTAssertEqual(beforeSwitch.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(beforeSwitch.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(beforeSwitch.controls.opacity, 0.01, accuracy: 0.001)
        XCTAssertEqual(switchPoint.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(switchPoint.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(switchPoint.controls.opacity, 0, accuracy: 0.001)
        XCTAssertEqual(beforeFadeInCompletes.controls.opacity, 0.99, accuracy: 0.001)
        XCTAssertEqual(completed.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(completed.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(completed.controls.paletteMorph, 1, accuracy: 0.001)
        XCTAssertEqual(completed.controls.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(afterCompletion.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(afterCompletion.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(afterCompletion.controls.paletteMorph, 1, accuracy: 0.001)
    }

    func testRepeatedIdenticalUpdateDoesNotRestartAnExistingTransition() {
        let initial = makePresentation()
        let updated = makePresentation(stateForFirstSlot: .additionPreview)
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)
        timeline.update(to: updated, elapsed: 1.085)
        let sample = timeline.sample(at: 1.17)

        XCTAssertEqual(sample.controls(for: "h0").paletteMorph, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.controls(for: "h0").scale, 1.03, accuracy: 0.001)
    }

    func testUnrelatedSlotUpdateDoesNotRestartAnotherSlotTransition() {
        let initial = makePresentation()
        let firstChanged = makePresentation(stateForFirstSlot: .additionPreview)
        let secondChanged = makePresentation(
            stateForFirstSlot: .additionPreview,
            stateForSecondSlot: .removalPreview
        )
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: firstChanged, elapsed: 1)
        timeline.update(to: secondChanged, elapsed: 1.085)
        let sample = timeline.sample(at: 1.17)

        XCTAssertEqual(sample.controls(for: "h0").paletteMorph, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.controls(for: "h0").scale, 1.03, accuracy: 0.001)
    }

    func testPresentationModeRendersConfirmationUntilItIsResolved() {
        XCTAssertFalse(DayObjectsPresentationMode.canvas.prefersSixtyFPS)
        let pending = makePresentation(isTransitionActive: false)
        XCTAssertTrue(DayObjectsPresentationMode.happeningPalette(pending).prefersSixtyFPS)
        let settled = HappeningPaletteRenderPresentation(slots: pending.slots.filter {
            $0.visualState == .available || $0.visualState == .added
        }, viewportSize: pending.viewportSize, reduceMotion: false, isTransitionActive: false, backgroundRevision: 12)
        XCTAssertFalse(DayObjectsPresentationMode.happeningPalette(settled).prefersSixtyFPS)
        XCTAssertTrue(DayObjectsPresentationMode.happeningPalette(
            makePresentation(isTransitionActive: true)
        ).prefersSixtyFPS)
    }

    private func actor(for happeningID: String, in frame: DayObjectRenderFrame) throws -> DayObjectRenderActor {
        try XCTUnwrap(frame.actors.first { $0.eventID == happeningID })
    }

    private func slot(for happeningID: String, in sample: HappeningPaletteRenderSample) throws -> HappeningPaletteRenderSample.Slot {
        try XCTUnwrap(sample.slots.first { $0.happeningID == happeningID })
    }

    private func makePresentation(
        stateForFirstSlot: HappeningPaletteSlotVisualState = .available,
        stateForSecondSlot: HappeningPaletteSlotVisualState = .additionPreview,
        reduceMotion: Bool = false,
        isTransitionActive: Bool = false,
        firstSourceOffset: CGSize = .zero,
        firstSourceRadiusDelta: CGFloat = 0
    ) -> HappeningPaletteRenderPresentation {
        let assignments = HappeningEditorialAssignmentResolver.assignments(
            happenings: (0..<10).map {
                Happening(id: "h\($0)", title: "Happening \($0)", isBuiltIn: true)
            },
            baseInput: editorialInput(),
            colorNonce: 7
        )
        let states: [HappeningPaletteSlotVisualState] = [
            stateForFirstSlot, stateForSecondSlot, .added, .removalPreview,
            .available, .available, .available, .available, .available, .available,
        ]
        let sources = (0..<10).map { index in
            let isFirst = index == 0
            let baseCenter = CGPoint(
                x: 39 + CGFloat(index) * 31,
                y: 32 + CGFloat(index) * 51
            )
            let center = CGPoint(
                x: baseCenter.x + (isFirst ? firstSourceOffset.width : 0),
                y: baseCenter.y + (isFirst ? firstSourceOffset.height : 0)
            )
            return HappeningFieldLayout.Source(
                index: index,
                center: center,
                radius: 32 + (isFirst ? firstSourceRadiusDelta : 0)
            )
        }
        return HappeningPaletteRenderPresentation(
            slots: (0..<10).map { index in
                HappeningPaletteRenderSlot(
                    happeningID: "h\(index)",
                    assignment: assignments["h\(index)"]!,
                    visualState: states[index],
                    source: sources[index]
                )
            },
            viewportSize: CGSize(width: 390, height: 844),
            reduceMotion: reduceMotion,
            isTransitionActive: isTransitionActive,
            backgroundRevision: 12
        )
    }

    func testPanningMovesSourcesImmediatelyWithoutRestartingTheShapeMorph() {
        let initial = makePresentation(stateForFirstSlot: .available)
        let preview = makePresentation(stateForFirstSlot: .additionPreview)
        var timeline = HappeningPaletteTransitionTimeline()
        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: preview, elapsed: 1)
        let beforePan = timeline.sample(at: 1.15).slots[0].controls
        let panned = makePresentation(stateForFirstSlot: .additionPreview, firstSourceOffset: CGSize(width: -100, height: -75))
        timeline.update(to: panned, elapsed: 1.15)
        let sample = timeline.sample(at: 1.15).slots[0]
        XCTAssertEqual(sample.source, panned.slots[0].source)
        XCTAssertEqual(sample.controls, beforePan)
    }

    func testPaletteUploadRetainsMoreThanTenVisibleChoicesAndTheirMaterials() {
        let ten = makePresentation()
        let thirty = HappeningPaletteRenderPresentation(
            slots: (0..<30).map { index in
                let source = ten.slots[index % 10]
                return HappeningPaletteRenderSlot(happeningID: "choice_\(index)", assignment: source.assignment, visualState: .available, source: source.source)
            }, viewportSize: ten.viewportSize, reduceMotion: false, isTransitionActive: false, backgroundRevision: 0
        )
        let frame = HappeningPaletteRenderFrame.make(presentation: thirty, scene: makeScene(), elapsed: 0)
        let upload = DayObjectsActorUpload(actors: frame.actors, actorLimit: DayObjectsActorUpload.maximumActorCount, resolution: SIMD2(390, 844))
        XCTAssertEqual(upload.actors.count, 30)
        for (index, actor) in upload.actors.enumerated() {
            XCTAssertEqual(upload.appearances[Int(actor.appearanceIndex)], frame.actors[index].gpuAppearance)
        }
    }

    private func makeScene() -> DayObjectScene {
        DayObjectScene.make(input: editorialInput())
    }

    private func editorialInput() -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "2026-09-06",
            identity: "palette-render-frame",
            eventIDs: [],
            motionEnergy: 0.625,
            visualClarity: 0.625,
            canvasCoverage: .fullCanvas,
            paletteCategories: ModernPaletteSelection.all,
            usesEditorialField: true,
            editorialBackground: .dark,
            lowSleep: true,
            editorialLabConfiguration: DayObjectEditorialLabConfiguration(
                materialMode: .generativeDNA,
                placement: .depthField
            )
        )
    }
}


final class DayObjectsPaletteResizeHandoffTests: XCTestCase {
    @MainActor
    func testWorldHostRetainsSubmittedOriginAcrossRequestsAndReturnsCanvasToItsBounds() {
        let viewport = CGSize(width: 393, height: 852)
        let view = DayObjectsDrawableView(frame: .zero, device: nil)
        view.autoResizeDrawable = false
        let host = DayObjectsSurfaceView(drawableView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1852, height: 2136)
        let first = CGPoint(x: 300, y: 400)
        let next = CGPoint(x: 380, y: 460)
        view.configurePaletteViewportSize(viewport, cameraOrigin: first)
        host.configurePaletteViewportSize(viewport)
        XCTAssertEqual(view.frame, CGRect(origin: .zero, size: viewport))
        view.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: first)
        XCTAssertEqual(view.frame, CGRect(origin: first, size: viewport))

        view.configurePaletteViewportSize(viewport, cameraOrigin: next)
        host.setNeedsLayout(); host.layoutIfNeeded()
        XCTAssertEqual(view.frame, CGRect(origin: first, size: viewport),
            "Native layout cannot move an image to a camera it does not contain")
        XCTAssertTrue(view.isHidden)
        let resized = CGSize(width: 430, height: 932)
        view.configurePaletteViewportSize(resized, cameraOrigin: next)
        host.configurePaletteViewportSize(resized)
        XCTAssertEqual(view.frame.origin, first)
        XCTAssertEqual(view.bounds.size, resized)
        XCTAssertTrue(view.isHidden, "A resized old image must wait for replacement")
        view.didPresentPaletteFrame(viewportSize: resized, cameraOrigin: next)
        XCTAssertEqual(view.frame, CGRect(origin: next, size: resized))
        XCTAssertFalse(view.isHidden)

        host.frame = CGRect(origin: .zero, size: viewport)
        view.configurePaletteViewportSize(nil)
        host.configurePaletteViewportSize(nil)
        host.setNeedsLayout(); host.layoutIfNeeded()
        XCTAssertEqual(view.frame, host.bounds, "Canvas uses its complete native bounds with no scroll camera")
        XCTAssertFalse(view.paletteResizeHandoff.isPending)
    }

    @MainActor
    func testDrawableResizeMatchesCurrentBoundsWithoutHidingTheNativeView() {
        let view = DayObjectsDrawableView(frame: .zero, device: nil)
        view.autoResizeDrawable = false
        for size in [CGSize(width: 393, height: 852), CGSize(width: 1852, height: 2136)] {
            view.configurePaletteViewportSize(size)
            view.bounds = CGRect(origin: .zero, size: size)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            XCTAssertTrue(view.drawableMatchesBounds)
            XCTAssertLessThanOrEqual(max(view.drawableSize.width, view.drawableSize.height), 4096)
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.alpha, 1)
        }
    }

    func testSameSizeCameraMoveRequiresItsOwnFrameAndRejectsDelayedPriorCamera() {
        let viewport = CGSize(width: 393, height: 852)
        let first = CGPoint(x: 300, y: 400)
        let second = CGPoint(x: 380, y: 460)
        let latest = CGPoint(x: -20, y: -30)
        var handoff = DayObjectsPaletteResizeHandoff()
        handoff.request(viewportSize: viewport, cameraOrigin: first)
        XCTAssertTrue(handoff.didPresent(viewportSize: viewport, cameraOrigin: first))
        handoff.request(viewportSize: viewport, cameraOrigin: second)
        XCTAssertTrue(handoff.isPending, "The old camera's drawable cannot move to a new world origin")
        XCTAssertFalse(handoff.canPresent(viewportSize: viewport, boundsSize: viewport, cameraOrigin: first))
        XCTAssertFalse(handoff.didPresent(viewportSize: viewport, cameraOrigin: first),
            "A delayed frame for the old camera must not complete the handoff")
        handoff.request(viewportSize: viewport, cameraOrigin: latest)
        XCTAssertFalse(handoff.didPresent(viewportSize: viewport, cameraOrigin: second))
        XCTAssertTrue(handoff.isPending)
        XCTAssertTrue(handoff.didPresent(viewportSize: viewport, cameraOrigin: latest))
        XCTAssertFalse(handoff.isPending)
    }

    @MainActor
    func testDelayedCameraFrameNeverExposesTheOldDrawableAtTheNewOrigin() {
        let viewport = CGSize(width: 393, height: 852)
        let oldCamera = CGPoint(x: 300, y: 400)
        let newCamera = CGPoint(x: 380, y: 460)
        let view = DayObjectsDrawableView(frame: CGRect(origin: .zero, size: viewport), device: nil)
        view.configurePaletteViewportSize(viewport, cameraOrigin: oldCamera)
        view.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: oldCamera)
        XCTAssertFalse(view.isHidden)
        view.configurePaletteViewportSize(viewport, cameraOrigin: newCamera)
        // No renderer/drawable is available: the prior image must stay hidden
        // for any number of delayed display-link turns at the new layer origin.
        view.synchronizePaletteResizeIfNeeded()
        XCTAssertTrue(view.isHidden)
        view.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: oldCamera)
        XCTAssertTrue(view.isHidden, "A delayed old-camera completion cannot reveal stale artwork")
        view.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: newCamera)
        XCTAssertFalse(view.isHidden)
        XCTAssertFalse(view.paletteResizeHandoff.isPending)
    }

    @MainActor
    func testPendingCameraDrawsPauseInBackgroundAndResumeAfterActivationAndReattachment() async throws {
        let viewport = CGSize(width: 393, height: 852)
        let first = CGPoint(x: 300, y: 400)
        let second = CGPoint(x: 380, y: 460)
        let third = CGPoint(x: 420, y: 520)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let view = DayObjectsDrawableView(frame: CGRect(origin: .zero, size: viewport), device: device)
        view.autoResizeDrawable = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(view)
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        defer { window.isHidden = true; view.delegate = nil }
        view.configurePaletteViewportSize(viewport, cameraOrigin: first)
        view.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: first)
        let attempts = PaletteFrameAttemptDelegate()
        view.delegate = attempts
        attempts.onDraw = { [weak view] in
            view?.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: second)
        }
        // Queue a retry while active, then deactivate before it can execute.
        view.configurePaletteViewportSize(viewport, cameraOrigin: second, isActive: true)
        view.configurePaletteViewportSize(viewport, cameraOrigin: second, isActive: false)
        view.synchronizePaletteResizeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(attempts.count, 0, "Queued and explicit camera draws must stop with inactive presentation")
        view.configurePaletteViewportSize(viewport, cameraOrigin: second, isActive: true)
        view.synchronizePaletteResizeIfNeeded()
        XCTAssertEqual(attempts.count, 1, "Activation resumes the pending camera exactly once")
        XCTAssertFalse(view.paletteResizeHandoff.isPending)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(attempts.count, 1)

        attempts.onDraw = { [weak view] in
            view?.didPresentPaletteFrame(viewportSize: viewport, cameraOrigin: third)
        }
        view.configurePaletteViewportSize(viewport, cameraOrigin: third, isActive: true)
        view.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(attempts.count, 1, "Detached views must not consume a queued retry")
        host.view.addSubview(view)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(attempts.count, 2, "Same-size reattachment resumes the pending camera")
        XCTAssertFalse(view.paletteResizeHandoff.isPending)
    }

    private final class PaletteFrameAttemptDelegate: NSObject, MTKViewDelegate {
        var count = 0
        var onDraw: (() -> Void)?
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            count += 1
            onDraw?()
        }
    }

    func testOnlyTheRequestedPaletteSizeCanCompleteAResize() {
        let questionnaire = CGSize(width: 393, height: 852)
        let all = CGSize(width: 1852, height: 2136)
        let later = CGSize(width: 1974, height: 2347)
        var handoff = DayObjectsPaletteResizeHandoff()
        handoff.request(viewportSize: questionnaire)
        XCTAssertTrue(handoff.isPending)
        XCTAssertTrue(handoff.didPresent(viewportSize: questionnaire))
        XCTAssertFalse(handoff.isPending)
        handoff.request(viewportSize: all)
        XCTAssertTrue(handoff.isPending)
        XCTAssertFalse(handoff.canPresent(viewportSize: all, boundsSize: questionnaire))
        XCTAssertTrue(handoff.canPresent(viewportSize: all, boundsSize: all))
        XCTAssertFalse(handoff.didPresent(viewportSize: questionnaire))
        XCTAssertTrue(handoff.isPending)
        handoff.request(viewportSize: later)
        XCTAssertFalse(handoff.didPresent(viewportSize: all), "An older submitted frame cannot complete a newer resize")
        XCTAssertTrue(handoff.isPending)
        XCTAssertTrue(handoff.didPresent(viewportSize: later))
        XCTAssertFalse(handoff.isPending)
    }

    func testRepeatedAnimationSamplesDoNotRequestAnotherResize() {
        let size = CGSize(width: 1852, height: 2136)
        var handoff = DayObjectsPaletteResizeHandoff()
        handoff.request(viewportSize: size)
        handoff.didPresent(viewportSize: size)
        for _ in 0..<120 {
            handoff.request(viewportSize: size)
            XCTAssertFalse(handoff.isPending)
        }
        handoff.request(viewportSize: nil)
        XCTAssertFalse(handoff.isPending)
        XCTAssertNil(handoff.presentedViewportSize)
    }
}
