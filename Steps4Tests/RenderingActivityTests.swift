import XCTest
import Metal
import MetalKit
import SwiftUI
import simd
@testable import Steps4

final class RenderingActivityTests: XCTestCase {
    func testSelectedActiveViewWithoutReduceMotionAnimates() {
        XCTAssertTrue(
            RenderingActivity.shouldAnimate(
                isViewActive: true,
                sceneIsActive: true,
                reduceMotion: false
            )
        )
    }

    func testHiddenTabDoesNotAnimate() {
        XCTAssertFalse(
            RenderingActivity.shouldAnimate(
                isViewActive: false,
                sceneIsActive: true,
                reduceMotion: false
            )
        )
    }

    func testBackgroundSceneDoesNotAnimate() {
        XCTAssertFalse(
            RenderingActivity.shouldAnimate(
                isViewActive: true,
                sceneIsActive: false,
                reduceMotion: false
            )
        )
    }

    func testReduceMotionDoesNotAnimate() {
        XCTAssertFalse(
            RenderingActivity.shouldAnimate(
                isViewActive: true,
                sceneIsActive: true,
                reduceMotion: true
            )
        )
    }

    func testInactiveOverlayNeverRendersActiveEffect() {
        XCTAssertFalse(
            MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: false,
                hasActiveEffect: true
            )
        )
    }

    func testActiveOverlayRendersActiveEffect() {
        XCTAssertTrue(
            MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: true,
                hasActiveEffect: true
            )
        )
    }

    func testActiveOverlayKeepsIdleRendererParked() {
        XCTAssertFalse(
            MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: true,
                hasActiveEffect: false
            )
        )
    }

    func testCanvasControlsUseTheMeasuredTabBarCenter() {
        XCTAssertEqual(
            CanvasBottomControlsLayout.padding(
                canvasBottomY: 844,
                tabBarCenterY: 790,
                controlHeight: 52,
                fallbackSafeAreaBottom: 34
            ),
            28
        )
    }

    func testSmudgePathFilterSoftensAbruptDirectionChanges() {
        var filter = SmudgeTouchPathFilter(responseSeconds: 0.05)
        let beginning = filter.begin(at: CGPoint(x: 20, y: 20), time: 1)
        let firstMove = filter.move(to: CGPoint(x: 120, y: 20), time: 1.01)
        let reversal = filter.move(to: CGPoint(x: 20, y: 20), time: 1.02)

        XCTAssertEqual(beginning.point, CGPoint(x: 20, y: 20))
        XCTAssertGreaterThan(firstMove.point.x, 20)
        XCTAssertLessThan(firstMove.point.x, 120)
        XCTAssertGreaterThan(reversal.point.x, 20)
        XCTAssertTrue(firstMove.speed.isFinite)
        XCTAssertGreaterThanOrEqual(firstMove.speed, 0)
    }

    func testSmudgePathFilterCapsLongFrameIntervals() {
        var filter = SmudgeTouchPathFilter(responseSeconds: 0.05)
        _ = filter.begin(at: CGPoint(x: 0, y: 0), time: 1)
        let sample = filter.move(to: CGPoint(x: 1_000, y: 0), time: 3)

        XCTAssertLessThan(sample.point.x, 1_000)
        XCTAssertLessThanOrEqual(sample.speed, SmudgeTouchPathFilter.maximumSpeed)
    }

    func testSmudgeAccumulatorCoalescesWorkWithoutLeavingAGap() {
        let touch = ObjectIdentifier(NSObject())
        var accumulator = SmudgeStrokeAccumulator()
        accumulator.enqueue(
            StrokeSegment(
                p0: SIMD2(0, 0), p1: SIMD2(10, 0), radius: 20,
                strength: 0.2, dragFactor: 3, direction: SIMD2(1, 0)
            ),
            for: touch
        )
        accumulator.enqueue(
            StrokeSegment(
                p0: SIMD2(10, 0), p1: SIMD2(30, 0), radius: 24,
                strength: 0.3, dragFactor: 4, direction: SIMD2(1, 0)
            ),
            for: touch
        )

        let strokes = accumulator.drain()
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes[0].p0, SIMD2(0, 0))
        XCTAssertEqual(strokes[0].p1, SIMD2(30, 0))
        XCTAssertTrue(accumulator.drain().isEmpty)
    }

    func testSmudgeAccumulatorPreservesCornersAndReversalWithinAFrame() {
        let finger = NSObject()
        let id = ObjectIdentifier(finger)
        var accumulator = SmudgeStrokeAccumulator()
        let points: [SIMD2<Float>] = [.init(0, 0), .init(20, 0), .init(20, 20), .init(20, 0)]
        for pair in zip(points, points.dropFirst()) {
            let delta = pair.1 - pair.0
            accumulator.enqueue(StrokeSegment(p0: pair.0, p1: pair.1, radius: 20,
                strength: 0.4, dragFactor: 4, direction: delta / simd_length(delta)), for: id)
        }
        let strokes = accumulator.drain()
        XCTAssertEqual(strokes.map(\.p0), Array(points.dropLast()))
        XCTAssertEqual(strokes.map(\.p1), Array(points.dropFirst()))
    }

    func testSmudgeAccumulatorBoundsBurstWithoutLosingEndpointsOrContinuity() {
        let finger = NSObject()
        let id = ObjectIdentifier(finger)
        var accumulator = SmudgeStrokeAccumulator()
        for index in 0..<100 {
            let start = SIMD2<Float>(Float(index), index.isMultiple(of: 2) ? 0 : 10)
            let end = SIMD2<Float>(Float(index + 1), index.isMultiple(of: 2) ? 10 : 0)
            let delta = end - start
            accumulator.enqueue(StrokeSegment(p0: start, p1: end, radius: 20,
                strength: 0.4, dragFactor: 4, direction: delta / simd_length(delta)), for: id)
        }
        let strokes = accumulator.drain()
        XCTAssertGreaterThan(strokes.count, 1)
        XCTAssertLessThanOrEqual(strokes.count, 4)
        XCTAssertEqual(strokes.first?.p0, SIMD2<Float>(0, 0))
        XCTAssertEqual(strokes.last?.p1, SIMD2<Float>(100, 0))
        for pair in zip(strokes, strokes.dropFirst()) { XCTAssertEqual(pair.0.p1, pair.1.p0) }
        XCTAssertTrue(accumulator.isEmpty)
    }

}

final class SmudgeWaterRippleTests: XCTestCase {
    func testSingleTapRendersTwoSeparateEchoRingsBehindMainWave() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "smudgeDisplayVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "smudgeDisplayFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let width = 1024
        func texture(_ format: MTLPixelFormat, usage: MTLTextureUsage) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: 1, mipmapped: false)
            d.storageMode = .shared
            d.usage = usage
            return try XCTUnwrap(device.makeTexture(descriptor: d))
        }
        let base = try texture(.rgba8Unorm, usage: .shaderRead)
        let age = try texture(.r32Float, usage: .shaderRead)
        let output = try texture(.rgba8Unorm, usage: .renderTarget)
        let region = MTLRegionMake2D(0, 0, width, 1)
        let pixels = [UInt8](repeating: 128, count: width * 4)
        pixels.withUnsafeBytes { base.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let ages = [Float](repeating: 99, count: width)
        ages.withUnsafeBytes { age.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(base, index: 0)
        encoder.setFragmentTexture(base, index: 1)
        encoder.setFragmentTexture(age, index: 2)
        // Legacy tap fixture: after 1.8s the main ring is at radius 450px,
        // with separated trailing waves near 345px and 261px.
        var ripple = RippleInfo(center: SIMD2(512, 0.5), elapsed: 1.8, amplitude: 50,
                                ringSpeed: 250, mainWidth: 42, decay: 0.0015, duration: 3)
        var display = DisplayParams(rippleCount: 1, globalFade: 1)
        encoder.setFragmentBytes(&ripple, length: MemoryLayout<RippleInfo>.stride, index: 0)
        encoder.setFragmentBytes(&display, length: MemoryLayout<DisplayParams>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var result = [UInt8](repeating: 0, count: width * 4)
        result.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: region, mipmapLevel: 0) }
        func alpha(_ radius: Int) -> Int { Int(result[(512 + radius) * 4 + 3]) }
        XCTAssertGreaterThan(alpha(261), alpha(294) + 1, "Inner echo must remain visibly separate")
        XCTAssertGreaterThan(alpha(345), alpha(382) + 1, "Middle echo must remain visibly separate")
        XCTAssertGreaterThan(alpha(450), alpha(495) + 1, "Main wave must remain visible")
    }
}

final class SmudgeComputeRegionTests: XCTestCase {
    func testBrushRegionProducesSamePixelsAndAgesAsFullCanvasDispatch() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let function = try XCTUnwrap(library.makeFunction(name: "smudgeKernel"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let size = 64
        let region = MTLRegionMake2D(0, 0, size, size)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size { for x in 0..<size {
            pixels[(y * size + x) * 4] = UInt8(x * 4)
            pixels[(y * size + x) * 4 + 1] = UInt8(y * 4)
        } }
        let ages = [Float](repeating: 99, count: size * size)
        func texture(_ format: MTLPixelFormat, bytes: UnsafeRawPointer) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite]
            let result = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            result.replace(region: region, mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
            return result
        }
        func render(origin: SIMD2<UInt32>, extent: Int) throws -> ([UInt8], [Float]) {
            let input = try pixels.withUnsafeBytes { try texture(.rgba8Unorm, bytes: $0.baseAddress!) }
            let output = try pixels.withUnsafeBytes { try texture(.rgba8Unorm, bytes: $0.baseAddress!) }
            let ageIn = try ages.withUnsafeBytes { try texture(.r32Float, bytes: $0.baseAddress!) }
            let ageOut = try ages.withUnsafeBytes { try texture(.r32Float, bytes: $0.baseAddress!) }
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(input, index: 0)
            encoder.setTexture(output, index: 1)
            encoder.setTexture(ageIn, index: 2)
            encoder.setTexture(ageOut, index: 3)
            var params = SmudgeParams(p0: SIMD2(24, 24), p1: SIMD2(34, 34), radius: 6,
                                     strength: 0.6, dragFactor: 5, direction: SIMD2(0.70710677, 0.70710677))
            var offset = origin
            encoder.setBytes(&params, length: MemoryLayout<SmudgeParams>.stride, index: 0)
            encoder.setBytes(&offset, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: extent, height: extent, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            var result = pixels
            var resultAges = ages
            result.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: size * 4, from: region, mipmapLevel: 0) }
            resultAges.withUnsafeMutableBytes { ageOut.getBytes($0.baseAddress!, bytesPerRow: size * 4, from: region, mipmapLevel: 0) }
            return (result, resultAges)
        }
        let full = try render(origin: .zero, extent: 64)
        let cropped = try render(origin: SIMD2(18, 18), extent: 23)
        XCTAssertNotEqual(full.0, pixels, "Fixture must actually displace the image")
        XCTAssertTrue(cropped.0 == full.0, "Cropping must preserve all displaced and untouched pixels")
        XCTAssertTrue(cropped.1 == full.1, "Cropping must preserve the age field and relaxation behavior")
    }
}

final class CanvasResourceReuseTests: XCTestCase {
    @MainActor
    func testPosterCoordinatorDoesNotBuildMetalBeforeViewCanAppear() {
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-09-07", identity: "reuse-test", eventIDs: [],
            motionEnergy: 0.5, visualClarity: 0.5, canvasCoverage: .fullCanvas,
            usesEditorialField: true, editorialBackground: .lowContrast
        ))
        let coordinator = DayObjectsMetalView.Coordinator(
            scene: scene, environment: .init(motionEnergy: 0.5, visualClarity: 0.5),
            digitalImpact: .none, soundPulseBus: nil
        )
        XCTAssertNil(coordinator.renderer, "View construction must not synchronously initialize Metal")
    }

    func testPostersSharePipelinesButNotMutableBuffers() throws {
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-09-07", identity: "reuse-test", eventIDs: [],
            motionEnergy: 0.5, visualClarity: 0.5, canvasCoverage: .fullCanvas,
            usesEditorialField: true, editorialBackground: .lowContrast
        ))
        let environment = DayObjectEnvironment(motionEnergy: 0.5, visualClarity: 0.5)
        let first = try XCTUnwrap(DayObjectsRenderer.create(scene: scene, environment: environment))
        let second = try XCTUnwrap(DayObjectsRenderer.create(scene: scene, environment: environment))
        func member(_ object: Any, _ name: String) throws -> AnyObject {
            try XCTUnwrap(Mirror(reflecting: object).children.first { $0.label == name }?.value as AnyObject?)
        }
        for name in ["meshGradientPipeline", "sceneUpscalePipeline", "actorPipeline", "horizontalBlurPipeline", "verticalBlurPipeline", "displayPipeline", "linearSampler", "quadBuffer"] {
            XCTAssertTrue(try member(first, name) === member(second, name), name)
        }
        XCTAssertFalse(try member(first, "actorBufferRing") === member(second, "actorBufferRing"))
    }
}

@MainActor
final class SmudgePreparationTests: XCTestCase {
    func testSmudgeCoordinatorDoesNotCompileMetalDuringViewConstruction() {
        XCTAssertNil(SmudgeOverlayView.Coordinator().renderer)
    }

    func testGallerySmudgeCoversViewportAfterRotation() async throws {
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore()
        )
        let gallery = GalleryView(
            model: model, metricOverlay: .constant(nil),
            presentation: .constant(.canvas), externalDataPanelPullDistance: 0,
            paletteRoute: .constant(CanvasPaletteRouteState()), isCanvasSelected: true
        )
        let defaults = UserDefaults.stepsTrader()
        let previousStyle = defaults.object(forKey: SharedKeys.canvasOverlayStyle)
        defaults.set(CanvasOverlayStyle.smudge.rawValue, forKey: SharedKeys.canvasOverlayStyle)
        defer {
            if let previousStyle { defaults.set(previousStyle, forKey: SharedKeys.canvasOverlayStyle) }
            else { defaults.removeObject(forKey: SharedKeys.canvasOverlayStyle) }
        }
        let host = UIHostingController(rootView: gallery.canvasLayers
            .environment(\.scenePhase, .active))
        // Exercise the actual Gallery surface without its persistence/bootstrap tasks.
        // A child controller lets the test change viewport size independently of
        // the phone's physical orientation while still mounting SwiftUI in a window.
        let container = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = container
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func find(_ view: UIView) -> SmudgeMTKView? {
            if let match = view as? SmudgeMTKView { return match }
            return view.subviews.compactMap { find($0) }.first
        }
        for size in [CGSize(width: 320, height: 640), CGSize(width: 640, height: 320), CGSize(width: 320, height: 640)] {
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let smudge = try XCTUnwrap(find(host.view))
            XCTAssertEqual(smudge.bounds.width, size.width, accuracy: 1)
            XCTAssertEqual(smudge.bounds.height, size.height, accuracy: 1)
            let farCorner = smudge.convert(CGPoint(x: size.width - 2, y: size.height - 2), from: host.view)
            XCTAssertTrue(smudge.point(inside: farCorner, with: nil), "Landscape edge must accept smudge/music gestures")
        }
    }

    func testResizeRefreshesSmudgeTextureAndSoundGestureCoordinates() async throws {
        var samples: [CanvasTouchGestureSample] = []
        var endedGestures = 0
        let overlay = SmudgeOverlayView(
            elements: [], sleepPoints: 10, stepsPoints: 12, sleepColor: .blue,
            stepsColor: .orange, decayNorm: 0, backgroundColor: .black,
            isRenderingAllowed: true,
            onGestureBegan: { samples.append($0) },
            onGestureEnded: { endedGestures += 1 }
        )
        let host = UIHostingController(rootView: overlay)
        let container = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = container
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func find(_ view: UIView) -> SmudgeMTKView? {
            if let match = view as? SmudgeMTKView { return match }
            return view.subviews.compactMap { find($0) }.first
        }
        let touch = NSObject()
        for (index, size) in [CGSize(width: 160, height: 320), CGSize(width: 320, height: 160)].enumerated() {
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let view = try XCTUnwrap(find(host.view))
            for _ in 0..<200 {
                if let renderer = view.delegate as? MetalSmudgeRenderer, !renderer.needsSnapshot { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let renderer = try XCTUnwrap(view.delegate as? MetalSmudgeRenderer)
            XCTAssertFalse(renderer.needsSnapshot)
            let base = try XCTUnwrap(Mirror(reflecting: renderer).children.first { $0.label == "baseTexture" }?.value as? MTLTexture)
            XCTAssertEqual(base.width, Int(view.drawableSize.width))
            XCTAssertEqual(base.height, Int(view.drawableSize.height))
            XCTAssertEqual(endedGestures, index, "Rotation ends the previous sound gesture before accepting a new one")
            view.onTouchBegan?(ObjectIdentifier(touch), CGPoint(x: view.bounds.width * 0.98, y: view.bounds.height * 0.5), CACurrentMediaTime())
            let sample = try XCTUnwrap(samples.last)
            XCTAssertEqual(samples.count, index + 1)
            XCTAssertEqual(sample.normalizedX, 0.98, accuracy: 0.001)
            XCTAssertEqual(sample.normalizedY, 0.5, accuracy: 0.001)
            XCTAssertTrue(renderer.isDistorted, "The new landscape edge must produce an effect")
        }
    }

    func testVisibleSmudgePreparesTextureBeforeTouch() async throws {
        let overlay = SmudgeOverlayView(
            elements: [], sleepPoints: 10, stepsPoints: 12, sleepColor: .blue,
            stepsColor: .orange, decayNorm: 0, backgroundColor: .black,
            isRenderingAllowed: true
        )
        let host = UIHostingController(rootView: overlay)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 128, height: 256))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        func find(_ view: UIView) -> SmudgeMTKView? {
            if let match = view as? SmudgeMTKView { return match }
            return view.subviews.compactMap { find($0) }.first
        }
        let view = try XCTUnwrap(find(host.view))
        for _ in 0..<100 {
            if let renderer = view.delegate as? MetalSmudgeRenderer, !renderer.needsSnapshot { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let renderer = try XCTUnwrap(view.delegate as? MetalSmudgeRenderer)
        XCTAssertFalse(renderer.needsSnapshot, "First touch must not pay for ImageRenderer or texture upload")
        XCTAssertFalse(renderer.isDistorted, "Preparation must not show a phantom ripple")
        XCTAssertTrue(view.isPaused)
    }
}

final class SmudgeRegionSequenceTests: XCTestCase {
    func testProductionRegionCopyMatchesFullDispatchForOverlappingAndDisjointStrokes() throws {
        let renderer = try XCTUnwrap(MetalSmudgeRenderer.create())
        let device = renderer.device
        let size = 64
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }()).image { ctx in
            for x in 0..<size {
                UIColor(red: CGFloat(x) / 64, green: 0.3, blue: 1 - CGFloat(x) / 64, alpha: 1).setFill()
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: size))
            }
        }
        renderer.updateBaseTexture(from: try XCTUnwrap(image.cgImage))
        func member<T>(_ name: String, as type: T.Type) throws -> T {
            try XCTUnwrap(Mirror(reflecting: renderer).children.first { $0.label == name }?.value as? T)
        }
        let queue = try member("commandQueue", as: MTLCommandQueue.self)
        let base = try member("baseTexture", as: MTLTexture.self)
        let actual = try member("interactiveA", as: MTLTexture.self)
        let actualAge = try member("ageA", as: MTLTexture.self)
        let region = MTLRegionMake2D(0, 0, size, size)
        func texture(_ format: MTLPixelFormat) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        }
        let references = try [texture(.bgra8Unorm), texture(.bgra8Unorm)]
        let ages = try [texture(.r32Float), texture(.r32Float)]
        let readback = try texture(.bgra8Unorm)
        let ageReadback = try texture(.r32Float)
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let initial = try XCTUnwrap(command.makeBlitCommandEncoder())
        for i in 0..<2 {
            initial.copy(from: base, to: references[i])
            initial.copy(from: actualAge, to: ages[i])
        }
        initial.endEncoding()
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "smudgeKernel")))
        let strokes = [
            StrokeSegment(p0: SIMD2(2, 3), p1: SIMD2(22, 20), radius: 8, strength: 0.6, dragFactor: 5, direction: SIMD2(0.76, 0.65)),
            StrokeSegment(p0: SIMD2(22, 20), p1: SIMD2(12, 30), radius: 6, strength: 0.7, dragFactor: 8, direction: SIMD2(-0.707, 0.707)),
            StrokeSegment(p0: SIMD2(58, 56), p1: SIMD2(63, 63), radius: 10, strength: 0.9, dragFactor: 4, direction: SIMD2(0.58, 0.81))
        ]
        var index = 0
        for stroke in strokes {
            renderer.applySmudge(stroke, commandBuffer: command)
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(references[index], index: 0)
            encoder.setTexture(references[1 - index], index: 1)
            encoder.setTexture(ages[index], index: 2)
            encoder.setTexture(ages[1 - index], index: 3)
            var params = SmudgeParams(p0: stroke.p0, p1: stroke.p1, radius: stroke.radius, strength: stroke.strength, dragFactor: stroke.dragFactor, direction: stroke.direction)
            var origin = SIMD2<UInt32>.zero
            encoder.setBytes(&params, length: MemoryLayout<SmudgeParams>.stride, index: 0)
            encoder.setBytes(&origin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: size, height: size, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            encoder.endEncoding()
            index = 1 - index
        }
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: actual, to: readback)
        blit.copy(from: actualAge, to: ageReadback)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        func bytes(_ texture: MTLTexture) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: size * size * 4)
            result.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: size * 4, from: region, mipmapLevel: 0) }
            return result
        }
        XCTAssertEqual(bytes(readback), bytes(references[index]))
        XCTAssertEqual(bytes(ageReadback), bytes(ages[index]))
        XCTAssertNotEqual(bytes(readback), bytes(base))
    }
}

@MainActor
final class CanvasIdleTimerTests: XCTestCase {
    private func content(fullScreen: Bool = true, selected: Bool = true, playing: Bool = true, phase: ScenePhase = .active) -> some View {
        Color.black
            .modifier(CanvasIdleTimerModifier(isFullScreen: fullScreen, isCanvasSelected: selected, isMusicPlaying: playing))
            .environment(\.scenePhase, phase)
    }

    func testOnlyVisibleActiveFullScreenMusicDisablesIdleTimer() async throws {
        let original = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = false
        defer { UIApplication.shared.isIdleTimerDisabled = original }
        let host = UIHostingController(rootView: AnyView(content()))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)

        // Each exit condition independently releases the idle timer.
        for (fullScreen, selected, playing, phase) in [
            (false, true, true, ScenePhase.active),
            (true, false, true, .active),
            (true, true, false, .active),
            (true, true, true, .inactive),
            (true, true, true, .background)
        ] {
            host.rootView = AnyView(content(fullScreen: fullScreen, selected: selected, playing: playing, phase: phase))
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
            host.rootView = AnyView(content())
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        }
        host.rootView = AnyView(EmptyView())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "Removing the view must release its request even before audio finishes stopping")
    }

    func testReleasesOnlyItsOwnIdleTimerChange() async throws {
        let original = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = original }
        let host = UIHostingController(rootView: AnyView(content()))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(50))
        host.rootView = AnyView(content(playing: false))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "Preserve an idle-timer setting that predates this view's request")
    }
}
