import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

// ════════════════════════════════════════════════════════════════════
// MARK: - Shader Parameter Structs  (must match SmudgeShaders.metal)
// ════════════════════════════════════════════════════════════════════

struct SmudgeParams {
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
    var radius: Float
    var strength: Float
    var dragFactor: Float
    var _pad: Float = 0
    var direction: SIMD2<Float>
}

struct RelaxParams {
    var alphaDiff: Float
    var baseReturn: Float
    var dt: Float
    var ageAccel: Float
}

struct RippleInfo {
    var center: SIMD2<Float> = .zero
    var elapsed: Float = 0
    var amplitude: Float = 0
    var ringSpeed: Float = 0
    var mainWidth: Float = 0
    var decay: Float = 0
    var duration: Float = 0
}

struct DisplayParams {
    var rippleCount: UInt32 = 0
    var globalFade: Float = 1.0
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Stroke Segment
// ════════════════════════════════════════════════════════════════════

struct StrokeSegment {
    let p0: SIMD2<Float>
    let p1: SIMD2<Float>
    let radius: Float
    let strength: Float
    let dragFactor: Float
    let direction: SIMD2<Float>
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Per-Touch State
// ════════════════════════════════════════════════════════════════════

private struct TouchState {
    var previousTime: CFTimeInterval
    var beganPixel: SIMD2<Float>
    var maxMovement: Float
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Active Ripple
// ════════════════════════════════════════════════════════════════════

private struct ActiveRipple {
    var info: RippleInfo
    var startTime: CFTimeInterval
}

// ════════════════════════════════════════════════════════════════════
// MARK: - MetalSmudgeRenderer
// ════════════════════════════════════════════════════════════════════

final class MetalSmudgeRenderer: NSObject, MTKViewDelegate {

    // ── Metal core ──────────────────────────────────────────────────
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let smudgePipeline: MTLComputePipelineState
    private let relaxDiffusePipeline: MTLComputePipelineState
    private let displayPipeline: MTLRenderPipelineState

    // ── Textures  (ping-pong A/B for interactive + age layers) ──────
    private var baseTexture: MTLTexture?
    private var interactiveA: MTLTexture?
    private var interactiveB: MTLTexture?
    private var ageA: MTLTexture?
    private var ageB: MTLTexture?
    private var useA = true

    private var textureWidth: Int = 0
    private var textureHeight: Int = 0

    // ── State ───────────────────────────────────────────────────────
    private var isBaseInitialized_ = false
    private(set) var isDistorted = false
    private var lastStrokeTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0

    var needsSnapshot: Bool { !isBaseInitialized_ }

    // ── Tuning constants ────────────────────────────────────────────
    private let relaxationTimeout: CFTimeInterval = 4.0
    private let targetReturnSeconds: Float = 1.0
    private let alphaDiffusion: Float = 0.05
    private let ageAcceleration: Float = 3.5
    private let fadeWindow: Float = 1.0

    private let baseRadius: Float = 80.0
    private let maxRadius: Float = 180.0
    private let baseStrength: Float = 0.60
    private let maxStrength: Float = 0.95
    private let baseDragFactor: Float = 1.8
    private let maxDragFactor: Float = 3.5

    // ── Stroke queue ────────────────────────────────────────────────
    private var pendingStrokes: [StrokeSegment] = []
    private let strokeLock = NSLock()

    // ── Multi-touch tracking ────────────────────────────────────────
    private var activeTouches: [ObjectIdentifier: TouchState] = [:]
    private let tapThreshold: Float = 30.0

    // ── Ripple state (up to 20 concurrent) ───────────────────────────
    private var activeRipples: [ActiveRipple] = []
    private let maxRipples = 20

    // ── Computed texture accessors ──────────────────────────────────
    private var currentInteractive: MTLTexture? { useA ? interactiveA : interactiveB }
    private var otherInteractive: MTLTexture?   { useA ? interactiveB : interactiveA }
    private var currentAge: MTLTexture?         { useA ? ageA : ageB }
    private var otherAge: MTLTexture?           { useA ? ageB : ageA }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Init (static factory)
    // ════════════════════════════════════════════════════════════════

    private override init() { fatalError("Use MetalSmudgeRenderer.create()") }

    private init(device: MTLDevice,
                 commandQueue: MTLCommandQueue,
                 smudgePipeline: MTLComputePipelineState,
                 relaxDiffusePipeline: MTLComputePipelineState,
                 displayPipeline: MTLRenderPipelineState) {
        self.device = device
        self.commandQueue = commandQueue
        self.smudgePipeline = smudgePipeline
        self.relaxDiffusePipeline = relaxDiffusePipeline
        self.displayPipeline = displayPipeline
        super.init()
    }

    static func create() -> MetalSmudgeRenderer? {
        guard let device  = MTLCreateSystemDefaultDevice(),
              let queue   = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            AppLogger.ui.error("[SMUDGE] Metal init failed")
            return nil
        }

        guard let smudgeFn = library.makeFunction(name: "smudgeKernel"),
              let relaxFn  = library.makeFunction(name: "relaxDiffuseKernel")
        else {
            AppLogger.ui.error("[SMUDGE] Compute functions not found")
            return nil
        }

        let smudgePSO: MTLComputePipelineState
        let relaxPSO:  MTLComputePipelineState
        do {
            smudgePSO = try device.makeComputePipelineState(function: smudgeFn)
            relaxPSO  = try device.makeComputePipelineState(function: relaxFn)
        } catch {
            AppLogger.ui.error("[SMUDGE] Compute pipeline error: \(error)")
            return nil
        }

        guard let vertexFn   = library.makeFunction(name: "smudgeDisplayVertex"),
              let fragmentFn = library.makeFunction(name: "smudgeDisplayFragment")
        else {
            AppLogger.ui.error("[SMUDGE] Display functions not found")
            return nil
        }

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction   = vertexFn
        rpd.fragmentFunction = fragmentFn
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm

        let displayPSO: MTLRenderPipelineState
        do {
            displayPSO = try device.makeRenderPipelineState(descriptor: rpd)
        } catch {
            AppLogger.ui.error("[SMUDGE] Display pipeline error: \(error)")
            return nil
        }

        return MetalSmudgeRenderer(
            device: device,
            commandQueue: queue,
            smudgePipeline: smudgePSO,
            relaxDiffusePipeline: relaxPSO,
            displayPipeline: displayPSO
        )
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Texture Management
    // ════════════════════════════════════════════════════════════════

    private func makeGPUTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false
        )
        desc.usage       = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private func makeSharedTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false
        )
        desc.usage       = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    private func makeAgeTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width, height: height, mipmapped: false
        )
        desc.usage       = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    private func ensureTextures(width: Int, height: Int) {
        guard width != textureWidth || height != textureHeight else { return }
        textureWidth  = width
        textureHeight = height

        baseTexture   = makeSharedTexture(width: width, height: height)
        interactiveA  = makeGPUTexture(width: width, height: height)
        interactiveB  = makeGPUTexture(width: width, height: height)
        ageA          = makeAgeTexture(width: width, height: height)
        ageB          = makeAgeTexture(width: width, height: height)
        useA = true
        isBaseInitialized_ = false
        isDistorted = false
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Base Texture Upload
    // ════════════════════════════════════════════════════════════════

    func updateBaseTexture(from cgImage: CGImage) {
        let width  = cgImage.width
        let height = cgImage.height
        ensureTextures(width: width, height: height)
        guard let base = baseTexture else { return }

        let bpp = 4
        let bytesPerRow = bpp * width
        var pixels = [UInt8](repeating: 0, count: width * height * bpp)

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
                       | CGImageAlphaInfo.noneSkipFirst.rawValue

        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        base.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow
        )

        copyBaseToInteractive()
    }

    private func copyBaseToInteractive() {
        guard let base = baseTexture,
              let a = interactiveA,
              let b = interactiveB,
              let cb = commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder()
        else { return }

        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        let size   = MTLSize(width: textureWidth, height: textureHeight, depth: 1)

        blit.copy(from: base, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: origin, sourceSize: size,
                  to: a, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: origin)
        blit.copy(from: base, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: origin, sourceSize: size,
                  to: b, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: origin)

        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        initializeAgeTextures()

        useA = true
        isBaseInitialized_ = true
    }

    private func initializeAgeTextures() {
        guard let a = ageA, let b = ageB else { return }
        let w = textureWidth
        let h = textureHeight
        let bytesPerRow = w * MemoryLayout<Float>.size
        var data = [Float](repeating: 99.0, count: w * h)
        let region = MTLRegionMake2D(0, 0, w, h)
        a.replace(region: region, mipmapLevel: 0, withBytes: &data, bytesPerRow: bytesPerRow)
        b.replace(region: region, mipmapLevel: 0, withBytes: &data, bytesPerRow: bytesPerRow)
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Gesture Input (multi-touch)
    // ════════════════════════════════════════════════════════════════

    func handleTouchBegan(id: ObjectIdentifier, at point: CGPoint, scale: CGFloat) {
        let now   = CACurrentMediaTime()
        let pixel = SIMD2<Float>(Float(point.x * scale), Float(point.y * scale))

        activeTouches[id] = TouchState(
            previousTime: now,
            beganPixel:   pixel,
            maxMovement:  0
        )

        // Fire a ripple immediately on every touch
        let ripple = RippleInfo(
            center:    pixel,
            elapsed:   0,
            amplitude: 50,
            ringSpeed: 250,
            mainWidth: 42,
            decay:     0.0015,
            duration:  3.0
        )
        activeRipples.append(ActiveRipple(info: ripple, startTime: now))
        if activeRipples.count > maxRipples {
            activeRipples.removeFirst()
        }

        lastStrokeTime = now
        if lastFrameTime == 0 { lastFrameTime = 0 }
        isDistorted = true
    }

    func addStrokeSegment(id: ObjectIdentifier,
                          from previous: CGPoint, to current: CGPoint,
                          scale: CGFloat) {
        guard isBaseInitialized_,
              var state = activeTouches[id]
        else { return }

        let now = CACurrentMediaTime()
        let dt  = Float(now - state.previousTime)
        state.previousTime = now

        let p0 = SIMD2<Float>(Float(previous.x * scale), Float(previous.y * scale))
        let p1 = SIMD2<Float>(Float(current.x  * scale), Float(current.y  * scale))

        state.maxMovement = max(state.maxMovement, simd_distance(state.beganPixel, p1))
        activeTouches[id] = state

        let v      = p1 - p0
        let speed  = simd_length(v) / max(dt, 1e-4)
        let segLen = simd_length(v)

        let radius     = min(max(baseRadius   + speed * 0.04,   baseRadius),   maxRadius)
        let strength   = min(max(baseStrength + speed * 0.0018, baseStrength), maxStrength)

        let rawDrag    = min(max(baseDragFactor + speed * 0.0008, baseDragFactor), maxDragFactor)
        let dragFactor = min(max(rawDrag * segLen, 8.0), 80.0)

        let direction  = segLen > 0.001 ? v / segLen : SIMD2<Float>(0, 0)

        let stroke = StrokeSegment(
            p0: p0, p1: p1,
            radius: radius,
            strength: strength,
            dragFactor: dragFactor,
            direction: direction
        )

        strokeLock.lock()
        pendingStrokes.append(stroke)
        strokeLock.unlock()

        lastStrokeTime = now
        isDistorted = true
    }

    func handleTouchEnded(id: ObjectIdentifier) {
        activeTouches.removeValue(forKey: id)
        lastStrokeTime = CACurrentMediaTime()
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - MTKViewDelegate
    // ════════════════════════════════════════════════════════════════

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd      = view.currentRenderPassDescriptor
        else { return }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if isDistorted && isBaseInitialized_ {
            let now = CACurrentMediaTime()
            let dt  = lastFrameTime > 0 ? Float(now - lastFrameTime) : Float(1.0 / 60.0)
            lastFrameTime = now

            // Update ripples, remove expired
            var liveRipples: [RippleInfo] = []
            activeRipples.removeAll { now - $0.startTime >= Double($0.info.duration) }
            for r in activeRipples {
                var info = r.info
                info.elapsed = Float(now - r.startTime)
                liveRipples.append(info)
            }

            let hasActiveRipple = !activeRipples.isEmpty
            let hasTouches      = !activeTouches.isEmpty
            let stillRelaxing   = (now - lastStrokeTime) < relaxationTimeout
                                  || hasActiveRipple
                                  || hasTouches

            if stillRelaxing {
                // 1. Apply pending smudge strokes
                strokeLock.lock()
                let strokes = pendingStrokes
                pendingStrokes.removeAll()
                strokeLock.unlock()

                for stroke in strokes {
                    applySmudge(stroke, commandBuffer: commandBuffer)
                }

                // 2. Diffusion + relaxation
                applyRelaxDiffuse(dt: dt, commandBuffer: commandBuffer)

                // 3. Smooth global fade ramp
                let timeSinceStroke = Float(now - lastStrokeTime)
                let timeoutF = Float(relaxationTimeout)
                let globalFade: Float
                if hasTouches || hasActiveRipple {
                    globalFade = 1.0
                } else if timeSinceStroke > (timeoutF - fadeWindow) {
                    globalFade = max(0.0, (timeoutF - timeSinceStroke) / fadeWindow)
                } else {
                    globalFade = 1.0
                }

                // 4. Build ripple buffer (fixed size 5)
                var rippleBuffer = [RippleInfo](repeating: RippleInfo(), count: maxRipples)
                for (i, r) in liveRipples.prefix(maxRipples).enumerated() {
                    rippleBuffer[i] = r
                }
                var displayParams = DisplayParams(
                    rippleCount: UInt32(min(liveRipples.count, maxRipples)),
                    globalFade:  globalFade
                )

                // 5. Render
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd),
                   let tex = currentInteractive,
                   let base = baseTexture,
                   let age = currentAge {
                    encoder.setRenderPipelineState(displayPipeline)
                    encoder.setFragmentTexture(tex,  index: 0)
                    encoder.setFragmentTexture(base, index: 1)
                    encoder.setFragmentTexture(age,  index: 2)
                    encoder.setFragmentBytes(&rippleBuffer,
                                             length: MemoryLayout<RippleInfo>.stride * maxRipples,
                                             index: 0)
                    encoder.setFragmentBytes(&displayParams,
                                             length: MemoryLayout<DisplayParams>.stride,
                                             index: 1)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    encoder.endEncoding()
                }
            } else {
                isDistorted = false
                isBaseInitialized_ = false
                activeRipples.removeAll()
                activeTouches.removeAll()
                view.isPaused = true
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
                    encoder.endEncoding()
                }
            }

        } else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
                encoder.endEncoding()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Compute Passes
    // ════════════════════════════════════════════════════════════════

    private func applySmudge(_ stroke: StrokeSegment, commandBuffer: MTLCommandBuffer) {
        guard let input   = currentInteractive,
              let output  = otherInteractive,
              let ageIn   = currentAge,
              let ageOut  = otherAge,
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return }

        encoder.setComputePipelineState(smudgePipeline)

        var params = SmudgeParams(
            p0: stroke.p0, p1: stroke.p1,
            radius: stroke.radius,
            strength: stroke.strength,
            dragFactor: stroke.dragFactor,
            direction: stroke.direction
        )

        encoder.setTexture(input,  index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setTexture(ageIn,  index: 2)
        encoder.setTexture(ageOut, index: 3)
        encoder.setBytes(&params, length: MemoryLayout<SmudgeParams>.stride, index: 0)

        let tgs = MTLSize(width: 16, height: 16, depth: 1)
        let tgc = MTLSize(
            width:  (textureWidth  + 15) / 16,
            height: (textureHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(tgc, threadsPerThreadgroup: tgs)
        encoder.endEncoding()

        useA.toggle()
    }

    private func applyRelaxDiffuse(dt: Float, commandBuffer: MTLCommandBuffer) {
        guard let input   = currentInteractive,
              let output  = otherInteractive,
              let base    = baseTexture,
              let ageIn   = currentAge,
              let ageOut  = otherAge,
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return }

        encoder.setComputePipelineState(relaxDiffusePipeline)

        var params = RelaxParams(
            alphaDiff:  alphaDiffusion,
            baseReturn: dt / targetReturnSeconds,
            dt:         dt,
            ageAccel:   ageAcceleration
        )

        encoder.setTexture(input,  index: 0)
        encoder.setTexture(base,   index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setTexture(ageIn,  index: 3)
        encoder.setTexture(ageOut, index: 4)

        encoder.setBytes(&params, length: MemoryLayout<RelaxParams>.stride, index: 0)

        let tgs = MTLSize(width: 16, height: 16, depth: 1)
        let tgc = MTLSize(
            width:  (textureWidth  + 15) / 16,
            height: (textureHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(tgc, threadsPerThreadgroup: tgs)
        encoder.endEncoding()

        useA.toggle()
    }
}
