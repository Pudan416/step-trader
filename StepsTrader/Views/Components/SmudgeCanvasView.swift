import SwiftUI
import MetalKit

struct CanvasTouchGestureSample: Equatable, Sendable {
    let normalizedX: Double
    let normalizedY: Double
    let speed: Double
}

struct SmudgeTouchPathSample: Equatable {
    let point: CGPoint
    let speed: CGFloat
}

/// Time-based low-pass filtering keeps the same feel at 60 and 120 Hz while
/// preventing a delayed frame from turning into a single hard displacement.
struct SmudgeTouchPathFilter {
    static let maximumSpeed: CGFloat = 1_800

    let responseSeconds: TimeInterval
    private var point: CGPoint?
    private var time: TimeInterval?
    private var speed: CGFloat = 0
    var currentPoint: CGPoint? { point }

    init(responseSeconds: TimeInterval = 0.05) {
        self.responseSeconds = max(responseSeconds, 0.001)
    }

    mutating func begin(at point: CGPoint, time: TimeInterval) -> SmudgeTouchPathSample {
        self.point = point
        self.time = time
        speed = 0
        return SmudgeTouchPathSample(point: point, speed: 0)
    }

    mutating func move(to rawPoint: CGPoint, time rawTime: TimeInterval) -> SmudgeTouchPathSample {
        guard let previousPoint = point, let previousTime = time else {
            return begin(at: rawPoint, time: rawTime)
        }

        let elapsed = min(max(rawTime - previousTime, 1.0 / 240.0), 1.0 / 30.0)
        let alpha = CGFloat(1 - exp(-elapsed / responseSeconds))
        let filteredPoint = CGPoint(
            x: previousPoint.x + (rawPoint.x - previousPoint.x) * alpha,
            y: previousPoint.y + (rawPoint.y - previousPoint.y) * alpha
        )
        let distance = hypot(filteredPoint.x - previousPoint.x, filteredPoint.y - previousPoint.y)
        let instantaneousSpeed = min(distance / elapsed, Self.maximumSpeed)
        speed += (instantaneousSpeed - speed) * alpha
        point = filteredPoint
        time = rawTime
        return SmudgeTouchPathSample(point: filteredPoint, speed: speed)
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - SmudgeMTKView  (transparent Metal overlay with multi-touch)
// ════════════════════════════════════════════════════════════════════

final class SmudgeMTKView: MTKView {

    var onTouchBegan: ((_ id: ObjectIdentifier, _ point: CGPoint) -> Void)?
    var onTouchMoved: ((_ id: ObjectIdentifier, _ previous: CGPoint, _ current: CGPoint) -> Void)?
    var onTouchEnded: ((_ id: ObjectIdentifier) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            onTouchBegan?(ObjectIdentifier(touch), touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            onTouchMoved?(ObjectIdentifier(touch),
                          touch.previousLocation(in: self),
                          touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            onTouchEnded?(ObjectIdentifier(touch))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            onTouchEnded?(ObjectIdentifier(touch))
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - SmudgeOverlayView  (SwiftUI transparent Metal overlay)
// ════════════════════════════════════════════════════════════════════

struct SmudgeOverlayView: UIViewRepresentable {

    let elements: [CanvasElement]
    let sleepPoints: Int
    let stepsPoints: Int
    let sleepColor: Color
    let stepsColor: Color
    let decayNorm: Double
    let backgroundColor: Color
    var labelColor: Color? = nil
    var hasStepsData: Bool = true
    var hasSleepData: Bool = true
    let isRenderingAllowed: Bool
    var onGestureBegan: @MainActor (CanvasTouchGestureSample) -> Void = { _ in }
    var onGestureUpdated: @MainActor (CanvasTouchGestureSample) -> Void = { _ in }
    var onGestureEnded: @MainActor () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SmudgeMTKView {
        let view = SmudgeMTKView()

        guard let renderer = context.coordinator.renderer else {
            view.backgroundColor = .clear
            return view
        }

        view.device                  = renderer.device
        view.delegate                = renderer
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat        = .bgra8Unorm
        view.framebufferOnly         = true
        view.isPaused                = true
        view.enableSetNeedsDisplay   = false
        view.isMultipleTouchEnabled  = true
        view.isUserInteractionEnabled = isRenderingAllowed

        view.isOpaque            = false
        view.layer.isOpaque      = false
        view.backgroundColor     = .clear
        view.clearColor          = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let scale = view.contentScaleFactor
        let coord = context.coordinator
        coord.storedConfig = self
        coord.renderingIsAllowed = isRenderingAllowed
        renderer.setActive(isRenderingAllowed)

        // UIKit haptic is correct here: `.sensoryFeedback` is a SwiftUI view
        // modifier and can't attach to UIView touch callbacks. The generator
        // is captured by the closure below, allocated once per representable
        // and reused. (CODE_AUDIT.md §4.1 — exempt by architecture)
        let touchHaptic = UIImpactFeedbackGenerator(style: .soft)
        touchHaptic.prepare()

        view.onTouchBegan = { [weak coord, weak view] id, point in
            guard let coord,
                  coord.renderingIsAllowed,
                  let view,
                  let renderer = coord.renderer
            else { return }
            if renderer.needsSnapshot {
                coord.snapshotCanvas(scale: scale)
            }
            let sample = coord.beginTouch(id: id, at: point)
            renderer.handleTouchBegan(id: id, at: sample.point, scale: scale)
            coord.forwardLeadBeginning(id: id, sample: sample, in: view.bounds.size)
            view.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: coord.renderingIsAllowed,
                hasActiveEffect: renderer.isDistorted
            )
            touchHaptic.impactOccurred(intensity: 0.35)
        }
        view.onTouchMoved = { [weak coord, weak view] id, _, current in
            guard let coord, coord.renderingIsAllowed, let view else { return }
            let movement = coord.moveTouch(id: id, to: current)
            coord.renderer?.addStrokeSegment(
                id: id,
                from: movement.previous,
                to: movement.current.point,
                scale: scale
            )
            coord.forwardLeadUpdate(id: id, sample: movement.current, in: view.bounds.size)
        }
        view.onTouchEnded = { [weak coord] id in
            guard let coord else { return }
            let endedLead = coord.endTouch(id: id)
            if endedLead { coord.storedConfig?.onGestureEnded() }
            guard coord.renderingIsAllowed else { return }
            coord.renderer?.handleTouchEnded(id: id)
        }

        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: SmudgeMTKView, context: Context) {
        let coordinator = context.coordinator
        coordinator.storedConfig = self
        coordinator.renderingIsAllowed = isRenderingAllowed
        uiView.isUserInteractionEnabled = isRenderingAllowed

        guard let renderer = coordinator.renderer else {
            uiView.isPaused = true
            return
        }

        renderer.setActive(isRenderingAllowed)
        if !isRenderingAllowed {
            renderer.cancelActiveInteraction()
            coordinator.cancelTouches()
        }

        uiView.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
            isRenderingAllowed: isRenderingAllowed,
            hasActiveEffect: renderer.isDistorted
        )
    }

    static func dismantleUIView(_ uiView: SmudgeMTKView, coordinator: Coordinator) {
        coordinator.renderingIsAllowed = false
        coordinator.renderer?.cancelActiveInteraction()
        coordinator.renderer?.setActive(false)
        coordinator.cancelTouches()
        uiView.isUserInteractionEnabled = false
        uiView.isPaused = true
        uiView.delegate = nil
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Coordinator
    // ────────────────────────────────────────────────────────────────

    @MainActor final class Coordinator {
        let renderer: MetalSmudgeRenderer?
        weak var mtkView: SmudgeMTKView?
        var storedConfig: SmudgeOverlayView?
        var renderingIsAllowed = false
        private var touchFilters: [ObjectIdentifier: SmudgeTouchPathFilter] = [:]
        private var leadTouchID: ObjectIdentifier?

        init() { renderer = MetalSmudgeRenderer.create() }

        func beginTouch(id: ObjectIdentifier, at point: CGPoint) -> SmudgeTouchPathSample {
            var filter = SmudgeTouchPathFilter()
            let sample = filter.begin(at: point, time: CACurrentMediaTime())
            touchFilters[id] = filter
            return sample
        }

        func moveTouch(
            id: ObjectIdentifier,
            to point: CGPoint
        ) -> (previous: CGPoint, current: SmudgeTouchPathSample) {
            guard var filter = touchFilters[id] else {
                var filter = SmudgeTouchPathFilter()
                let sample = filter.begin(at: point, time: CACurrentMediaTime())
                touchFilters[id] = filter
                return (sample.point, sample)
            }
            let previous = filter.currentPoint ?? point
            let sample = filter.move(to: point, time: CACurrentMediaTime())
            touchFilters[id] = filter
            return (previous, sample)
        }

        func endTouch(id: ObjectIdentifier) -> Bool {
            touchFilters.removeValue(forKey: id)
            guard leadTouchID == id else { return false }
            leadTouchID = nil
            return true
        }

        func forwardLeadBeginning(
            id: ObjectIdentifier,
            sample: SmudgeTouchPathSample,
            in size: CGSize
        ) {
            guard leadTouchID == nil else { return }
            leadTouchID = id
            storedConfig?.onGestureBegan(normalized(sample, in: size))
        }

        func forwardLeadUpdate(
            id: ObjectIdentifier,
            sample: SmudgeTouchPathSample,
            in size: CGSize
        ) {
            guard leadTouchID == id else { return }
            storedConfig?.onGestureUpdated(normalized(sample, in: size))
        }

        func cancelTouches() {
            let hadLead = leadTouchID != nil
            leadTouchID = nil
            touchFilters.removeAll()
            if hadLead { storedConfig?.onGestureEnded() }
        }

        private func normalized(
            _ sample: SmudgeTouchPathSample,
            in size: CGSize
        ) -> CanvasTouchGestureSample {
            let width = max(size.width, 1)
            let height = max(size.height, 1)
            return CanvasTouchGestureSample(
                normalizedX: Double(min(max(sample.point.x / width, 0), 1)),
                normalizedY: Double(min(max(sample.point.y / height, 0), 1)),
                speed: Double(sample.speed / max(width, height))
            )
        }

        func snapshotCanvas(scale: CGFloat) {
            guard let cfg = storedConfig,
                  let view = mtkView,
                  let renderer = renderer
            else { return }

            let drawableSize = view.drawableSize
            guard drawableSize.width > 0, drawableSize.height > 0 else { return }

            let pointW = drawableSize.width  / scale
            let pointH = drawableSize.height / scale

            let composite = EnergyGradientBackground(
                stepsPoints: cfg.stepsPoints,
                sleepPoints: cfg.sleepPoints,
                hasStepsData: cfg.hasStepsData,
                hasSleepData: cfg.hasSleepData
            )
            .frame(width: pointW, height: pointH)

            let imageRenderer = ImageRenderer(content: composite)
            imageRenderer.scale = scale

            if let cgImage = imageRenderer.cgImage {
                renderer.updateBaseTexture(from: cgImage)
            }
        }
    }
}
