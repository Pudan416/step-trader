import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

// ════════════════════════════════════════════════════════════════════
// MARK: - Shader Parameter Struct  (must match ShaderParkShader.metal)
// ════════════════════════════════════════════════════════════════════

struct ShaderParkParams {
    var resolution: SIMD2<Float>
    var time: Float
    var click: Float
    var touch: SIMD2<Float>
    var velocity: SIMD2<Float>
    var hueOffset: Float
    var ringFreq: Float
}

// ════════════════════════════════════════════════════════════════════
// MARK: - MetalShaderParkRenderer
// ════════════════════════════════════════════════════════════════════

/// Always-running fullscreen-quad renderer for the cosmic FBM overlay.
/// No central shape — the whole canvas warps under finger position +
/// velocity. Decoupled from `MetalSmudgeRenderer` so the smudge code
/// stays untouched.
final class MetalShaderParkRenderer: NSObject, MTKViewDelegate {

    // ── Metal core ──────────────────────────────────────────────────
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    // ── Animation state ─────────────────────────────────────────────
    private let startTime: CFTimeInterval = CACurrentMediaTime()
    /// Random palette phase so each app launch feels a little different.
    private let hueOffset: Float = Float.random(in: 0..<1)
    private var click: Float = 0
    private var clickTarget: Float = 0
    private var touch: SIMD2<Float> = SIMD2<Float>(-99, -99)
    private var velocity: SIMD2<Float> = .zero
    private var prevTouch: SIMD2<Float>? = nil

    /// View size in pixels. Updated from `mtkView(_:drawableSizeWillChange:)`.
    private var drawableSize: SIMD2<Float> = SIMD2<Float>(1, 1)

    private(set) var isActive: Bool = true

    @available(*, unavailable)
    private override init() { fatalError() }

    private init(device: MTLDevice,
                 commandQueue: MTLCommandQueue,
                 pipeline: MTLRenderPipelineState) {
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        super.init()
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Factory
    // ════════════════════════════════════════════════════════════════

    static func create() -> MetalShaderParkRenderer? {
        guard let device  = MTLCreateSystemDefaultDevice(),
              let queue   = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            AppLogger.ui.error("[COSMIC] Metal init failed")
            return nil
        }

        guard let vertexFn   = library.makeFunction(name: "shaderParkVertex"),
              let fragmentFn = library.makeFunction(name: "shaderParkFragment")
        else {
            AppLogger.ui.error("[COSMIC] Shader functions not found")
            return nil
        }

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction   = vertexFn
        rpd.fragmentFunction = fragmentFn
        rpd.colorAttachments[0].pixelFormat                 = .bgra8Unorm
        // Premultiplied source-over: matches the alpha output of the fragment.
        rpd.colorAttachments[0].isBlendingEnabled           = true
        rpd.colorAttachments[0].rgbBlendOperation           = .add
        rpd.colorAttachments[0].alphaBlendOperation         = .add
        rpd.colorAttachments[0].sourceRGBBlendFactor        = .one
        rpd.colorAttachments[0].sourceAlphaBlendFactor      = .one
        rpd.colorAttachments[0].destinationRGBBlendFactor   = .oneMinusSourceAlpha
        rpd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let pipeline: MTLRenderPipelineState
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: rpd)
        } catch {
            AppLogger.ui.error("[COSMIC] Pipeline build failed: \(error)")
            return nil
        }

        return MetalShaderParkRenderer(
            device: device,
            commandQueue: queue,
            pipeline: pipeline
        )
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Input
    // ════════════════════════════════════════════════════════════════

    func setActive(_ active: Bool) { isActive = active }

    /// Map a UIKit point inside `bounds` to the shader's aspect-corrected
    /// uv space. Updates per-frame velocity = (current - previous).
    func setTouch(point: CGPoint, bounds: CGSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect = Float(bounds.width / bounds.height)
        let nx = Float((point.x / bounds.width)  * 2.0 - 1.0) * aspect
        let ny = Float(1.0 - (point.y / bounds.height) * 2.0)
        let cur = SIMD2<Float>(nx, ny)
        if let prev = prevTouch {
            let delta = cur - prev
            // Blend so a single frame spike doesn't overshoot the warp.
            velocity = velocity * 0.4 + delta * 0.6
        }
        prevTouch = cur
        touch     = cur
    }

    func touchBegan() {
        clickTarget = 1.0
        velocity    = .zero
    }

    func touchEnded() {
        clickTarget = 0.0
        prevTouch   = nil
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - MTKViewDelegate
    // ════════════════════════════════════════════════════════════════

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = SIMD2<Float>(Float(max(size.width,  1)),
                                    Float(max(size.height, 1)))
    }

    func draw(in view: MTKView) {
        guard isActive,
              let drawable = view.currentDrawable,
              let rpd      = view.currentRenderPassDescriptor,
              let cb       = commandQueue.makeCommandBuffer(),
              let encoder  = cb.makeRenderCommandEncoder(descriptor: rpd)
        else {
            // Drain swap-chain on inactive frames so the OS doesn't stall.
            if let drawable = view.currentDrawable,
               let rpd      = view.currentRenderPassDescriptor,
               let cb       = commandQueue.makeCommandBuffer(),
               let encoder  = cb.makeRenderCommandEncoder(descriptor: rpd) {
                encoder.endEncoding()
                cb.present(drawable)
                cb.commit()
            }
            return
        }

        // Smooth click attack/decay. Slower decay (0.06/frame ≈ 1s tail at
        // 60fps) keeps the cosmic dissipating like fog instead of vanishing.
        let attack: Float = 0.14
        let decay:  Float = 0.06
        let rate   = clickTarget > click ? attack : decay
        click += (clickTarget - click) * rate

        // Velocity decays slower (0.92/frame ≈ 0.7s tail) so swirls linger
        // long after the finger leaves the screen.
        velocity *= 0.92

        // When fully idle (click decayed + velocity dead), park the view so
        // we don't draw an invisible quad at 60 fps. Touch handlers in
        // `ShaderParkOverlayView` flip `isPaused` back to false on the next
        // touchBegan / setActive(true).
        let speed = simd_length(velocity)
        if click < 0.005 && speed < 0.0008 && clickTarget == 0 {
            click = 0
            velocity = .zero
            view.isPaused = true
            // Must close the encoder & flush the buffer before bailing out —
            // otherwise MTLDebugRenderCommandEncoder.dealloc asserts
            // "Command encoder released without endEncoding".
            encoder.endEncoding()
            cb.present(drawable)
            cb.commit()
            return
        }

        var params = ShaderParkParams(
            resolution: drawableSize,
            time:       Float(CACurrentMediaTime() - startTime),
            click:      click,
            touch:      touch,
            velocity:   velocity,
            hueOffset:  hueOffset,
            ringFreq:   0
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&params,
                                 length: MemoryLayout<ShaderParkParams>.stride,
                                 index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cb.present(drawable)
        cb.commit()
    }
}
