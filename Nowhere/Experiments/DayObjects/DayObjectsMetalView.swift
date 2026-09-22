import CoreMotion
import MetalKit
import SwiftUI

/// Supplies the projection of real gravity into portrait canvas coordinates.
/// The renderer reads the latest sample without waiting for SwiftUI updates.
final class DayObjectMotionInputProvider: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "nowhere.day-objects.motion"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let lock = NSLock()
    private var storedGravity = SIMD2<Float>(0, -0.35)

    var projectedGravity: SIMD2<Float> {
        lock.lock()
        defer { lock.unlock() }
        return storedGravity
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let projected = SIMD2(Float(gravity.x), Float(gravity.y))
            guard projected.x.isFinite, projected.y.isFinite else { return }
            self.lock.lock()
            self.storedGravity = projected
            self.lock.unlock()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

@MainActor
final class DayObjectWallImpactSink {
    var handler: @MainActor (DayObjectWallImpact) -> Void

    init(handler: @escaping @MainActor (DayObjectWallImpact) -> Void) {
        self.handler = handler
    }

    func send(_ impact: DayObjectWallImpact) {
        handler(impact)
    }
}

@MainActor
final class DayObjectLunarPhysicsReturnSink {
    var handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func send() {
        handler()
    }
}

struct DayObjectsMetalView: UIViewRepresentable {
    @Environment(\.isTodayCanvasSource) private var isTodayCanvasSource
    let scene: DayObjectScene
    let environment: DayObjectEnvironment
    let digitalImpact: DayObjectDigitalImpact
    let isAnimating: Bool
    var animatesContinuously = true
    let soundPulseBus: DayObjectsSoundPulseBus?
    var presentationMode: DayObjectsPresentationMode = .canvas
    var lunarPhysicsIsActive = false
    var lunarAngularMotionIsEnabled = true
    var lunarInteractionBus: DayObjectLunarInteractionBus?
    var onWallImpact: @MainActor (DayObjectWallImpact) -> Void = { _ in }
    var onLunarPhysicsReturnCompleted: @MainActor () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact,
            soundPulseBus: soundPulseBus,
            presentationMode: presentationMode,
            lunarPhysicsIsActive: lunarPhysicsIsActive,
            lunarAngularMotionIsEnabled: lunarAngularMotionIsEnabled,
            lunarInteractionBus: lunarInteractionBus,
            onWallImpact: onWallImpact,
            onLunarPhysicsReturnCompleted: onLunarPhysicsReturnCompleted
        )
    }

    func makeUIView(context: Context) -> MTKView {
        let renderer = context.coordinator.renderer
        let view = DayObjectsDrawableView(frame: .zero, device: renderer?.device)
        view.autoResizeDrawable = false
        view.delegate = renderer
        DayObjectsRenderer.configureDisplay(view)
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        context.coordinator.mtkView = view
        updateUIView(view, context: context)
        return view
    }

    static func configureAnimationFrameRate(_ view: MTKView, prefersSixtyFPS: Bool = false) {
        // MTKView owns the display link and exposes its rate through this API.
        let preferred = prefersSixtyFPS ? 60 : 30
        if view.preferredFramesPerSecond != preferred {
            view.preferredFramesPerSecond = preferred
        }
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.isTodayCanvasSource = isTodayCanvasSource
        context.coordinator.update(
            uiView,
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact,
            soundPulseBus: soundPulseBus,
            presentationMode: presentationMode,
            isAnimating: isAnimating,
            animatesContinuously: animatesContinuously,
            lunarPhysicsIsActive: lunarPhysicsIsActive,
            lunarAngularMotionIsEnabled: lunarAngularMotionIsEnabled,
            lunarInteractionBus: lunarInteractionBus,
            onWallImpact: onWallImpact,
            onLunarPhysicsReturnCompleted: onLunarPhysicsReturnCompleted
        )
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        TodayCanvasBackdropStore.shared.unregisterSource(uiView)
        coordinator.cancelPreparation()
        coordinator.motionInput.stop()
        coordinator.renderer?.setAnimating(false)
        uiView.isPaused = true
        uiView.delegate = nil
        coordinator.mtkView = nil
    }

    @MainActor final class Coordinator {
        private(set) var renderer: DayObjectsRenderer?
        var isTodayCanvasSource = false
        weak var mtkView: MTKView?
        private var preparation: Task<Void, Never>?
        private var scene: DayObjectScene
        private var environment: DayObjectEnvironment
        private var digitalImpact: DayObjectDigitalImpact
        private var soundPulseBus: DayObjectsSoundPulseBus?
        private var presentationMode: DayObjectsPresentationMode
        private var isAnimating = false
        private var animatesContinuously = true
        let motionInput = DayObjectMotionInputProvider()
        private var lunarPhysicsIsActive: Bool
        private var lunarAngularMotionIsEnabled: Bool
        private var lunarInteractionBus: DayObjectLunarInteractionBus?
        let wallImpactSink: DayObjectWallImpactSink
        let lunarPhysicsReturnSink: DayObjectLunarPhysicsReturnSink

        init(
            scene: DayObjectScene,
            environment: DayObjectEnvironment,
            digitalImpact: DayObjectDigitalImpact,
            soundPulseBus: DayObjectsSoundPulseBus?,
            presentationMode: DayObjectsPresentationMode = .canvas,
            lunarPhysicsIsActive: Bool = false,
            lunarAngularMotionIsEnabled: Bool = true,
            lunarInteractionBus: DayObjectLunarInteractionBus? = nil,
            onWallImpact: @escaping @MainActor (DayObjectWallImpact) -> Void = { _ in },
            onLunarPhysicsReturnCompleted: @escaping @MainActor () -> Void = {}
        ) {
            self.scene = scene
            self.environment = environment
            self.digitalImpact = digitalImpact
            self.soundPulseBus = soundPulseBus
            self.presentationMode = presentationMode
            self.lunarPhysicsIsActive = lunarPhysicsIsActive
            self.lunarAngularMotionIsEnabled = lunarAngularMotionIsEnabled
            self.lunarInteractionBus = lunarInteractionBus
            wallImpactSink = DayObjectWallImpactSink(handler: onWallImpact)
            lunarPhysicsReturnSink = DayObjectLunarPhysicsReturnSink(
                handler: onLunarPhysicsReturnCompleted
            )
        }

        func prepareRenderer() async {
            guard renderer == nil else { return }
            await Task.detached(priority: .userInitiated) {
                DayObjectsRenderer.prepareResources()
            }.value
            guard !Task.isCancelled, renderer == nil else { return }
            renderer = DayObjectsRenderer.create(
                scene: scene, environment: environment, digitalImpact: digitalImpact,
                soundPulseBus: soundPulseBus, presentationMode: presentationMode
            )
        }

        func cancelPreparation() {
            preparation?.cancel()
            preparation = nil
        }

        func update(
            _ view: MTKView,
            scene: DayObjectScene,
            environment: DayObjectEnvironment,
            digitalImpact: DayObjectDigitalImpact,
            soundPulseBus: DayObjectsSoundPulseBus?,
            presentationMode: DayObjectsPresentationMode,
            isAnimating: Bool,
            animatesContinuously: Bool = true,
            lunarPhysicsIsActive: Bool = false,
            lunarAngularMotionIsEnabled: Bool = true,
            lunarInteractionBus: DayObjectLunarInteractionBus? = nil,
            onWallImpact: @escaping @MainActor (DayObjectWallImpact) -> Void = { _ in },
            onLunarPhysicsReturnCompleted: @escaping @MainActor () -> Void = {}
        ) {
            let playbackWasActive = self.lunarPhysicsIsActive
            self.scene = scene
            self.environment = environment
            self.digitalImpact = digitalImpact
            self.soundPulseBus = soundPulseBus
            self.presentationMode = presentationMode
            self.isAnimating = isAnimating
            self.animatesContinuously = animatesContinuously
            self.lunarPhysicsIsActive = lunarPhysicsIsActive
            self.lunarAngularMotionIsEnabled = lunarAngularMotionIsEnabled
            self.lunarInteractionBus = lunarInteractionBus
            wallImpactSink.handler = onWallImpact
            lunarPhysicsReturnSink.handler = onLunarPhysicsReturnCompleted
            mtkView = view
            guard renderer != nil else {
                view.isPaused = true
                if playbackWasActive && !lunarPhysicsIsActive {
                    Task { @MainActor [weak lunarPhysicsReturnSink] in
                        lunarPhysicsReturnSink?.send()
                    }
                }
                if preparation == nil {
                    preparation = Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.prepareRenderer()
                        guard !Task.isCancelled else { return }
                        self.preparation = nil
                        self.applyCurrentState()
                    }
                }
                return
            }
            applyCurrentState()
        }

        private func applyCurrentState() {
            guard let renderer, let view = mtkView else { return }
            if view.device == nil { view.device = renderer.device }
            view.delegate = renderer
            if isTodayCanvasSource {
                TodayCanvasBackdropStore.shared.registerSource(view, renderer: renderer)
            } else {
                TodayCanvasBackdropStore.shared.unregisterSource(view)
            }
            renderer.update(scene: scene, environment: environment, digitalImpact: digitalImpact,
                            soundPulseBus: soundPulseBus, presentationMode: presentationMode,
                            lunarPhysicsIsActive: lunarPhysicsIsActive,
                            lunarPhysicsReturnIsAnimated: isAnimating && !lunarPhysicsIsActive,
                            lunarAngularMotionIsEnabled: lunarAngularMotionIsEnabled,
                            motionInput: motionInput,
                            lunarInteractionBus: lunarInteractionBus,
                            wallImpactSink: wallImpactSink,
                            lunarPhysicsReturnSink: lunarPhysicsReturnSink)
            // Background audio can stay on while the canvas display link is paused.
            if lunarPhysicsIsActive && isAnimating { motionInput.start() } else { motionInput.stop() }
            renderer.setAnimating(isAnimating, continuously: animatesContinuously)
            renderer.configureAnimation(view)
        }
    }
}


/// Scroll fields can be much taller than the screen. Keep the drawable within
/// a conservative Metal texture limit while labels retain native UI resolution.
final class DayObjectsDrawableView: MTKView {
    static func displayScale(for size: CGSize, nativeScale: CGFloat) -> CGFloat {
        min(max(1, nativeScale), 4096 / max(1, max(size.width, size.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = Self.displayScale(for: bounds.size, nativeScale: traitCollection.displayScale)
        if contentScaleFactor != scale { contentScaleFactor = scale }
        let size = CGSize(width: max(1, floor(bounds.width * scale)),
                          height: max(1, floor(bounds.height * scale)))
        if drawableSize != size { drawableSize = size }
    }
}
