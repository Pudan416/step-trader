import CoreMotion
import MetalKit
import QuartzCore
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
    let scene: DayObjectScene
    let environment: DayObjectEnvironment
    let digitalImpact: DayObjectDigitalImpact
    let isAnimating: Bool
    var animatesContinuously = true
    let soundPulseBus: DayObjectsSoundPulseBus?
    var presentationMode: DayObjectsPresentationMode = .canvas
    var ambientMotionIsEnabled = false
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
            ambientMotionIsEnabled: ambientMotionIsEnabled,
            lunarPhysicsIsActive: lunarPhysicsIsActive,
            lunarAngularMotionIsEnabled: lunarAngularMotionIsEnabled,
            lunarInteractionBus: lunarInteractionBus,
            onWallImpact: onWallImpact,
            onLunarPhysicsReturnCompleted: onLunarPhysicsReturnCompleted
        )
    }

    func makeUIView(context: Context) -> DayObjectsSurfaceView {
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

        let surface = DayObjectsSurfaceView(drawableView: view)
        context.coordinator.mtkView = view
        updateUIView(surface, context: context)
        return surface
    }

    static func configureAnimationFrameRate(_ view: MTKView, prefersSixtyFPS: Bool = false) {
        // MTKView owns the display link and exposes its rate through this API.
        let preferred = prefersSixtyFPS ? 60 : 30
        if view.preferredFramesPerSecond != preferred {
            view.preferredFramesPerSecond = preferred
        }
    }

    func updateUIView(_ uiView: DayObjectsSurfaceView, context: Context) {
        context.coordinator.update(
            uiView.drawableView,
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact,
            soundPulseBus: soundPulseBus,
            presentationMode: presentationMode,
            isAnimating: isAnimating,
            animatesContinuously: animatesContinuously,
            ambientMotionIsEnabled: ambientMotionIsEnabled,
            lunarPhysicsIsActive: lunarPhysicsIsActive,
            lunarAngularMotionIsEnabled: lunarAngularMotionIsEnabled,
            lunarInteractionBus: lunarInteractionBus,
            onWallImpact: onWallImpact,
            onLunarPhysicsReturnCompleted: onLunarPhysicsReturnCompleted
        )
    }

    static func dismantleUIView(_ surface: DayObjectsSurfaceView, coordinator: Coordinator) {
        let uiView = surface.drawableView
        coordinator.cancelPreparation()
        coordinator.motionInput.stop()
        coordinator.renderer?.setAnimating(false)
        uiView.isPaused = true
        uiView.delegate = nil
        coordinator.mtkView = nil
    }

    @MainActor final class Coordinator {
        private(set) var renderer: DayObjectsRenderer?
        weak var mtkView: MTKView?
        private var preparation: Task<Void, Never>?
        private var scene: DayObjectScene
        private var environment: DayObjectEnvironment
        private var digitalImpact: DayObjectDigitalImpact
        private var soundPulseBus: DayObjectsSoundPulseBus?
        private var presentationMode: DayObjectsPresentationMode
        private var isAnimating = false
        private var animatesContinuously = true
        private var ambientMotionIsEnabled: Bool
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
            ambientMotionIsEnabled: Bool = false,
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
            self.ambientMotionIsEnabled = ambientMotionIsEnabled
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
            ambientMotionIsEnabled: Bool = false,
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
            self.ambientMotionIsEnabled = ambientMotionIsEnabled
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
            renderer.update(scene: scene, environment: environment, digitalImpact: digitalImpact,
                            soundPulseBus: soundPulseBus, presentationMode: presentationMode,
                            ambientMotionIsEnabled: ambientMotionIsEnabled,
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
            if let drawableView = view as? DayObjectsDrawableView {
                let viewportSize: CGSize?
                let cameraOrigin: CGPoint
                if case let .happeningPalette(presentation) = presentationMode {
                    viewportSize = presentation.viewportSize
                    cameraOrigin = presentation.cameraOrigin
                } else { viewportSize = nil; cameraOrigin = .zero }
                drawableView.configurePaletteViewportSize(viewportSize, cameraOrigin: cameraOrigin, isActive: isAnimating)
                (drawableView.superview as? DayObjectsSurfaceView)?.configurePaletteViewportSize(viewportSize)
                drawableView.synchronizePaletteResizeIfNeeded()
            }
        }
    }
}


/// A fixed world-sized host allocates no Metal surface. Its child stays
/// viewport-sized and retains the last submitted camera's world origin until
/// a replacement image and native layer position can commit together.
final class DayObjectsSurfaceView: UIView {
    let drawableView: DayObjectsDrawableView
    private var paletteViewportSize: CGSize?

    init(drawableView: DayObjectsDrawableView) {
        self.drawableView = drawableView
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        addSubview(drawableView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configurePaletteViewportSize(_ size: CGSize?) {
        paletteViewportSize = size
        layoutDrawable()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutDrawable()
    }

    private func layoutDrawable() {
        let frame: CGRect
        if let size = paletteViewportSize {
            frame = CGRect(origin: drawableView.paletteResizeHandoff.presentedCameraOrigin ?? .zero, size: size)
        } else {
            frame = bounds
        }
        if drawableView.frame != frame { drawableView.frame = frame }
    }

    /// Called inside the drawable's presentation transaction, after scheduling.
    func commitPaletteFrame(viewportSize: CGSize, cameraOrigin: CGPoint) {
        guard paletteViewportSize == viewportSize else { return }
        let frame = CGRect(origin: cameraOrigin, size: viewportSize)
        if drawableView.frame != frame { drawableView.frame = frame }
    }
}

/// A resized CAMetalLayer must not stretch its previous questionnaire frame
/// across the All world while waiting for the display link. A camera move at
/// the same size also needs a fresh frame before its layer can move. Only the
/// requested viewport and camera together can complete this handoff.
// "Presented" records successful submission to the layer transaction; actual
// on-screen presentation timing is measured separately on physical devices.
struct DayObjectsPaletteResizeHandoff: Equatable {
    private(set) var requestedViewportSize: CGSize?
    private(set) var presentedViewportSize: CGSize?
    private(set) var requestedCameraOrigin: CGPoint?
    private(set) var presentedCameraOrigin: CGPoint?

    var isPending: Bool {
        requestedViewportSize != nil && (requestedViewportSize != presentedViewportSize
            || requestedCameraOrigin != presentedCameraOrigin)
    }

    var isCameraChangePending: Bool {
        requestedViewportSize != nil && presentedViewportSize != nil
            && requestedCameraOrigin != presentedCameraOrigin
    }

    mutating func request(viewportSize: CGSize?, cameraOrigin: CGPoint = .zero) {
        requestedViewportSize = viewportSize
        requestedCameraOrigin = viewportSize == nil ? nil : cameraOrigin
        if viewportSize == nil {
            presentedViewportSize = nil
            presentedCameraOrigin = nil
        }
    }

    func canPresent(viewportSize: CGSize, boundsSize: CGSize, cameraOrigin: CGPoint = .zero) -> Bool {
        guard let requestedViewportSize else { return false }
        return viewportSize == requestedViewportSize && cameraOrigin == requestedCameraOrigin
            && abs(boundsSize.width - viewportSize.width) < 0.5
            && abs(boundsSize.height - viewportSize.height) < 0.5
    }

    @discardableResult
    mutating func didPresent(viewportSize: CGSize, cameraOrigin: CGPoint = .zero) -> Bool {
        guard viewportSize == requestedViewportSize, cameraOrigin == requestedCameraOrigin else { return false }
        presentedViewportSize = viewportSize
        presentedCameraOrigin = cameraOrigin
        return true
    }
}

/// Scroll fields can be much taller than the screen. Keep the drawable within
/// a conservative Metal texture limit while labels retain native UI resolution.
final class DayObjectsDrawableView: MTKView {
    private(set) var paletteResizeHandoff = DayObjectsPaletteResizeHandoff()
    private var isSynchronizingPaletteResize = false
    private var isPaletteCameraRetryScheduled = false
    private(set) var palettePresentationIsActive = true

    func configurePaletteViewportSize(_ size: CGSize?, cameraOrigin: CGPoint = .zero, isActive: Bool = true) {
        palettePresentationIsActive = isActive
        paletteResizeHandoff.request(viewportSize: size, cameraOrigin: cameraOrigin)
        updatePendingCameraVisibility()
        schedulePaletteCameraRetryIfNeeded()
    }

    func synchronizePaletteResizeIfNeeded() {
        guard palettePresentationIsActive, paletteResizeHandoff.isPending,
              // A paused/detached presentation keeps its latest request for
              // resume; it must not bypass lifecycle gating with explicit draws.
              (!paletteResizeHandoff.isCameraChangePending || window != nil),
              let size = paletteResizeHandoff.requestedViewportSize,
              let camera = paletteResizeHandoff.requestedCameraOrigin,
              paletteResizeHandoff.canPresent(viewportSize: size, boundsSize: bounds.size, cameraOrigin: camera),
              delegate != nil, !isSynchronizingPaletteResize else { return }
        resizeDrawableToMatchBounds()
        isSynchronizingPaletteResize = true
        defer { isSynchronizingPaletteResize = false }
        // Camera changes, just like size changes, must join the layer's new
        // position transaction. Reuse scheduled presentation; never wait for
        // GPU completion. Normal unchanged-camera frames remain asynchronous.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let prior = presentsWithTransaction
        presentsWithTransaction = true
        // A failed earlier attempt may have hidden the stale camera. An
        // explicit draw must run independently of visibility/display-link state.
        isHidden = false
        draw()
        presentsWithTransaction = prior
        updatePendingCameraVisibility()
        CATransaction.commit()
        schedulePaletteCameraRetryIfNeeded()
    }

    func didPresentPaletteFrame(viewportSize: CGSize, cameraOrigin: CGPoint = .zero) {
        guard paletteResizeHandoff.didPresent(viewportSize: viewportSize, cameraOrigin: cameraOrigin) else { return }
        (superview as? DayObjectsSurfaceView)?.commitPaletteFrame(viewportSize: viewportSize, cameraOrigin: cameraOrigin)
        updatePendingCameraVisibility()
    }

    private func updatePendingCameraVisibility() {
        // Normally draw() resolves this in the same transaction, so no hidden
        // frame reaches the screen. If drawable acquisition/encoding fails,
        // labels keep scrolling while stale artwork is withheld and retried.
        isHidden = paletteResizeHandoff.isPending && paletteResizeHandoff.presentedViewportSize != nil
    }

    private func schedulePaletteCameraRetryIfNeeded() {
        guard palettePresentationIsActive, paletteResizeHandoff.isPending,
              window != nil, !isPaletteCameraRetryScheduled else { return }
        isPaletteCameraRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self else { return }
            self.isPaletteCameraRetryScheduled = false
            // A previously queued retry must recheck both gates after a tab,
            // scene-phase or window change, rather than drawing in background.
            guard self.palettePresentationIsActive, self.window != nil else { return }
            self.synchronizePaletteResizeIfNeeded()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, palettePresentationIsActive else { return }
        // Reattachment may preserve size and skip layout/updateUIView. Resume
        // a pending camera once its native drawable can be presented again.
        synchronizePaletteResizeIfNeeded()
        schedulePaletteCameraRetryIfNeeded()
    }

    static func displayScale(for size: CGSize, nativeScale: CGFloat) -> CGFloat {
        min(max(1, nativeScale), 4096 / max(1, max(size.width, size.height)))
    }

    var drawableMatchesBounds: Bool {
        let scale = Self.displayScale(for: bounds.size, nativeScale: traitCollection.displayScale)
        return drawableSize == CGSize(width: max(1, floor(bounds.width * scale)),
            height: max(1, floor(bounds.height * scale)))
    }

    private func resizeDrawableToMatchBounds() {
        let scale = Self.displayScale(for: bounds.size, nativeScale: traitCollection.displayScale)
        if contentScaleFactor != scale { contentScaleFactor = scale }
        let size = CGSize(width: max(1, floor(bounds.width * scale)),
                          height: max(1, floor(bounds.height * scale)))
        if drawableSize != size {
            releaseDrawables()
            drawableSize = size
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizeDrawableToMatchBounds()
        synchronizePaletteResizeIfNeeded()
    }
}
