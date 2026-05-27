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
        // UIKit haptic is correct here: `.sensoryFeedback` is a SwiftUI view
        // modifier and can't attach to UIView touch callbacks. The generator
        // is captured by the closure below, allocated once per representable
        // and reused. (CODE_AUDIT.md §4.1 — exempt by architecture)
        let touchHaptic = UIImpactFeedbackGenerator(style: .light)
        touchHaptic.prepare()

        view.onTouchBegan = { [weak coord, weak view] point in
            guard let coord = coord, let view = view else { return }
            view.isPaused = false
            coord.renderer?.touchBegan()
            coord.renderer?.setTouch(point: point, bounds: view.bounds.size)
            touchHaptic.impactOccurred(intensity: 0.6)
        }
        view.onTouchMoved = { [weak coord, weak view] point in
            guard let coord = coord, let view = view else { return }
            view.isPaused = false
            coord.renderer?.setTouch(point: point, bounds: view.bounds.size)
        }
        view.onTouchEnded = { [weak coord] in
            coord?.renderer?.touchEnded()
        }

        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: ShaderParkMTKView, context: Context) {
        // Only resume if the renderer was explicitly deactivated (teardown).
        // SwiftUI calls updateUIView on every recomposition; unconditionally
        // unpausing here would wake an idle renderer that self-parked after
        // touch decay, burning GPU on invisible empty frames until it re-parks.
        guard let renderer = context.coordinator.renderer else { return }
        if !renderer.isActive {
            renderer.setActive(true)
            uiView.isPaused = false
        }
    }

    static func dismantleUIView(_ uiView: ShaderParkMTKView, coordinator: Coordinator) {
        coordinator.renderer?.setActive(false)
        uiView.isPaused = true
        uiView.delegate = nil
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Coordinator
    // ────────────────────────────────────────────────────────────────

    @MainActor final class Coordinator {
        let renderer: MetalShaderParkRenderer?
        weak var mtkView: ShaderParkMTKView?

        init() { renderer = MetalShaderParkRenderer.create() }
    }
}
