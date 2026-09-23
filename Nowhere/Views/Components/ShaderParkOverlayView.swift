import SwiftUI
import MetalKit

// ════════════════════════════════════════════════════════════════════
// MARK: - ShaderParkMTKView  (transparent fullscreen Metal overlay)
// ════════════════════════════════════════════════════════════════════

final class ShaderParkMTKView: MTKView {

    var onTouchBegan: ((_ point: CGPoint) -> Void)?
    var onTouchMoved: ((_ point: CGPoint) -> Void)?
    var onTouchEnded: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTouchBegan?(t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTouchMoved?(t.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchEnded?()
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - ShaderParkOverlayView  (SwiftUI wrapper)
// ════════════════════════════════════════════════════════════════════

struct ShaderParkOverlayView: UIViewRepresentable {

    let isRenderingAllowed: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ShaderParkMTKView {
        let view = ShaderParkMTKView()

        guard let renderer = context.coordinator.renderer else {
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            return view
        }

        view.device                  = renderer.device
        view.delegate                = renderer
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat        = .bgra8Unorm
        view.framebufferOnly         = true
        // Idle = paused (saves GPU + nothing visible at rest). Touch handlers
        // wake the view up; the renderer parks it again once `click` and
        // `velocity` have both decayed to zero. See `MetalShaderParkRenderer`.
        view.isPaused                = true
        view.enableSetNeedsDisplay   = false
        view.isUserInteractionEnabled = isRenderingAllowed

        view.isOpaque            = false
        view.layer.isOpaque      = false
        view.backgroundColor     = .clear
        view.clearColor          = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // The cosmic field is intentionally soft, so full retina pixel
        // density is wasted GPU. 1.25× point density still looks smooth
        // (no visible blockiness — bilinear sampling hides the upscale)
        // and cuts the per-frame fragment count by ~5× on a 3× device,
        // which matters because each fragment runs 6 × 5-octave FBM.
        view.contentScaleFactor  = min(UIScreen.main.scale, 1.25)

        let coord = context.coordinator
        coord.renderingIsAllowed = isRenderingAllowed
        renderer.setActive(isRenderingAllowed)
        // UIKit haptic is correct here: `.sensoryFeedback` is a SwiftUI view
        // modifier and can't attach to UIView touch callbacks. The generator
        // is captured by the closure below, allocated once per representable
        // and reused. (CODE_AUDIT.md §4.1 — exempt by architecture)
        let touchHaptic = UIImpactFeedbackGenerator(style: .light)
        touchHaptic.prepare()

        view.onTouchBegan = { [weak coord, weak view] point in
            guard let coord,
                  coord.renderingIsAllowed,
                  let view,
                  let renderer = coord.renderer
            else { return }
            renderer.touchBegan()
            renderer.setTouch(point: point, bounds: view.bounds.size)
            view.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: coord.renderingIsAllowed,
                hasActiveEffect: renderer.hasActiveEffect
            )
            touchHaptic.impactOccurred(intensity: 0.6)
        }
        view.onTouchMoved = { [weak coord, weak view] point in
            guard let coord,
                  coord.renderingIsAllowed,
                  let view,
                  let renderer = coord.renderer
            else { return }
            renderer.setTouch(point: point, bounds: view.bounds.size)
            view.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: coord.renderingIsAllowed,
                hasActiveEffect: renderer.hasActiveEffect
            )
        }
        view.onTouchEnded = { [weak coord] in
            guard let coord, coord.renderingIsAllowed else { return }
            coord.renderer?.touchEnded()
        }

        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: ShaderParkMTKView, context: Context) {
        let coordinator = context.coordinator
        coordinator.renderingIsAllowed = isRenderingAllowed
        uiView.isUserInteractionEnabled = isRenderingAllowed

        guard let renderer = coordinator.renderer else {
            uiView.isPaused = true
            return
        }

        renderer.setActive(isRenderingAllowed)
        if !isRenderingAllowed {
            renderer.cancelActiveInteraction()
        }

        // SwiftUI calls updateUIView on every recomposition. Gate the display
        // link by both lifecycle permission and actual effect state so an idle
        // renderer stays parked instead of waking for invisible frames.
        uiView.isPaused = !MetalOverlayRenderingPolicy.shouldRender(
            isRenderingAllowed: isRenderingAllowed,
            hasActiveEffect: renderer.hasActiveEffect
        )
    }

    static func dismantleUIView(_ uiView: ShaderParkMTKView, coordinator: Coordinator) {
        coordinator.renderingIsAllowed = false
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
        let renderer: MetalShaderParkRenderer?
        weak var mtkView: ShaderParkMTKView?
        var renderingIsAllowed = false

        init() { renderer = MetalShaderParkRenderer.create() }
    }
}
