import SwiftUI
import MetalKit

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

        view.isOpaque            = false
        view.layer.isOpaque      = false
        view.backgroundColor     = .clear
        view.clearColor          = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let scale = view.contentScaleFactor
        let coord = context.coordinator

        view.onTouchBegan = { [weak coord, weak view] id, point in
            guard let coord = coord, let renderer = coord.renderer else { return }
            view?.isPaused = false
            if renderer.needsSnapshot {
                coord.snapshotCanvas(scale: scale)
            }
            renderer.handleTouchBegan(id: id, at: point, scale: scale)
        }
        view.onTouchMoved = { [weak coord] id, previous, current in
            coord?.renderer?.addStrokeSegment(id: id, from: previous, to: current, scale: scale)
        }
        view.onTouchEnded = { [weak coord] id in
            coord?.renderer?.handleTouchEnded(id: id)
            // DON'T pause here — let the render loop continue so
            // relaxation + age-based fade can run to completion.
            // The renderer will pause the view in draw() once fully faded.
        }

        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: SmudgeMTKView, context: Context) {
        context.coordinator.storedConfig = self
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Coordinator
    // ────────────────────────────────────────────────────────────────

    @MainActor final class Coordinator {
        let renderer: MetalSmudgeRenderer?
        weak var mtkView: SmudgeMTKView?
        var storedConfig: SmudgeOverlayView?

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

            let composite = ZStack {
                EnergyGradientBackground(
                    stepsPoints: cfg.stepsPoints,
                    sleepPoints: cfg.sleepPoints,
                    hasStepsData: cfg.hasStepsData,
                    hasSleepData: cfg.hasSleepData
                )

                GenerativeCanvasView(
                    elements: cfg.elements,
                    sleepPoints: cfg.sleepPoints,
                    stepsPoints: cfg.stepsPoints,
                    sleepColor: cfg.sleepColor,
                    stepsColor: cfg.stepsColor,
                    decayNorm: cfg.decayNorm,
                    backgroundColor: cfg.backgroundColor,
                    labelColor: cfg.labelColor,
                    showLabelsOnCanvas: false,
                    showsBackgroundGradient: false,
                    hasStepsData: cfg.hasStepsData,
                    hasSleepData: cfg.hasSleepData,
                    fixedTime: Date()
                )
            }
            .frame(width: pointW, height: pointH)

            let imageRenderer = ImageRenderer(content: composite)
            imageRenderer.scale = scale

            if let cgImage = imageRenderer.cgImage {
                renderer.updateBaseTexture(from: cgImage)
            }
        }
    }
}
