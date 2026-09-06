import SwiftUI
import MetalKit

enum SmudgeSnapshotInteractionPolicy {
    static func canBegin(needsSnapshot: Bool) -> Bool {
        !needsSnapshot
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
    var editorialSnapshotInput: EditorialCanvasRenderInput? = nil
    var editorialClock: DayObjectsClock? = nil
    let isRenderingAllowed: Bool
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

        let coord = context.coordinator
        coord.storedConfig = self
        coord.renderingIsAllowed = isRenderingAllowed
        renderer.setActive(isRenderingAllowed)

        // UIKit haptic is correct here: `.sensoryFeedback` is a SwiftUI view
        // modifier and can't attach to UIView touch callbacks. The generator
        // is captured by the closure below, allocated once per representable
        // and reused. (CODE_AUDIT.md §4.1 — exempt by architecture)
        let touchHaptic = UIImpactFeedbackGenerator(style: .medium)
        touchHaptic.prepare()

        view.onTouchBegan = { [weak coord, weak view] id, point in
            guard let coord,
                  coord.renderingIsAllowed,
                  let view,
                  let renderer = coord.renderer
            else { return }
            let scale = view.contentScaleFactor
            if renderer.needsSnapshot {
                if coord.storedConfig?.editorialSnapshotInput != nil {
                    coord.queuePendingTouch(id: id, point: point, scale: scale)
                }
                coord.snapshotCanvas(scale: scale)
            }
            guard SmudgeSnapshotInteractionPolicy.canBegin(
                needsSnapshot: renderer.needsSnapshot
            ) else { return }
            renderer.handleTouchBegan(id: id, at: point, scale: scale)
            view.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: coord.renderingIsAllowed,
                hasActiveEffect: renderer.isDistorted
            )
            touchHaptic.impactOccurred(intensity: 0.7)
        }
        view.onTouchMoved = { [weak coord, weak view] id, previous, current in
            guard let coord, coord.renderingIsAllowed, let view else { return }
            if coord.updatePendingTouch(id: id, point: current) { return }
            coord.renderer?.addStrokeSegment(
                id: id,
                from: previous,
                to: current,
                scale: view.contentScaleFactor
            )
        }
        view.onTouchEnded = { [weak coord] id in
            guard let coord, coord.renderingIsAllowed else { return }
            if coord.cancelPendingTouch(id: id) { return }
            coord.renderer?.handleTouchEnded(id: id)
            touchHaptic.impactOccurred(intensity: 0.5)
        }

        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: SmudgeMTKView, context: Context) {
        let coordinator = context.coordinator
        let previousEditorialInput = coordinator.storedConfig?.editorialSnapshotInput
        coordinator.storedConfig = self
        coordinator.renderingIsAllowed = isRenderingAllowed
        uiView.isUserInteractionEnabled = isRenderingAllowed

        guard let renderer = coordinator.renderer else {
            uiView.isPaused = true
            return
        }

        renderer.setActive(isRenderingAllowed)
        if previousEditorialInput != editorialSnapshotInput {
            coordinator.cancelSnapshot()
            renderer.invalidateBaseSnapshot()
        }
        if !isRenderingAllowed {
            coordinator.cancelSnapshot()
            renderer.cancelActiveInteraction()
        }

        uiView.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
            isRenderingAllowed: isRenderingAllowed,
            hasActiveEffect: renderer.isDistorted
        )
    }

    static func dismantleUIView(_ uiView: SmudgeMTKView, coordinator: Coordinator) {
        coordinator.renderingIsAllowed = false
        coordinator.cancelSnapshot()
        coordinator.renderer?.cancelActiveInteraction()
        coordinator.renderer?.setActive(false)
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
        private var editorialSnapshotTask: Task<Void, Never>?
        private var editorialSnapshotGeneration = 0
        private var pendingTouches: [ObjectIdentifier: PendingTouch] = [:]

        private struct PendingTouch {
            var point: CGPoint
            let scale: CGFloat
        }

        init() { renderer = MetalSmudgeRenderer.create() }

        func snapshotCanvas(scale: CGFloat) {
            guard let cfg = storedConfig,
                  let view = mtkView,
                  let renderer = renderer
            else { return }

            let drawableSize = view.drawableSize
            guard drawableSize.width > 0, drawableSize.height > 0 else { return }

            let pointW = drawableSize.width  / scale
            let pointH = drawableSize.height / scale

            if let editorial = cfg.editorialSnapshotInput {
                guard editorialSnapshotTask == nil else { return }
                let generation = editorialSnapshotGeneration
                let elapsedTime = cfg.editorialClock?.elapsedTime ?? 4
                editorialSnapshotTask = Task { @MainActor [weak self, weak view] in
                    defer {
                        if self?.editorialSnapshotGeneration == generation {
                            self?.editorialSnapshotTask = nil
                        }
                    }
                    let image = await DayObjectsImageRenderer.image(
                        input: editorial,
                        size: CGSize(width: pointW, height: pointH),
                        scale: scale,
                        elapsedTime: elapsedTime
                    )
                    guard !Task.isCancelled,
                          let self,
                          let view,
                          self.renderingIsAllowed,
                          self.editorialSnapshotGeneration == generation,
                          self.storedConfig?.editorialSnapshotInput == editorial,
                          let cgImage = image?.cgImage
                    else { return }
                    self.renderer?.updateBaseTexture(from: cgImage)
                    let touches = self.pendingTouches
                    self.pendingTouches.removeAll()
                    for (id, touch) in touches {
                        self.renderer?.handleTouchBegan(
                            id: id,
                            at: touch.point,
                            scale: touch.scale
                        )
                    }
                    if !touches.isEmpty {
                        view.isPaused = false
                    }
                }
                return
            }

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

        func queuePendingTouch(id: ObjectIdentifier, point: CGPoint, scale: CGFloat) {
            pendingTouches[id] = PendingTouch(point: point, scale: scale)
        }

        func updatePendingTouch(id: ObjectIdentifier, point: CGPoint) -> Bool {
            guard var touch = pendingTouches[id] else { return false }
            touch.point = point
            pendingTouches[id] = touch
            return true
        }

        func cancelPendingTouch(id: ObjectIdentifier) -> Bool {
            pendingTouches.removeValue(forKey: id) != nil
        }

        func cancelSnapshot() {
            editorialSnapshotGeneration += 1
            editorialSnapshotTask?.cancel()
            editorialSnapshotTask = nil
            pendingTouches.removeAll()
        }
    }
}
