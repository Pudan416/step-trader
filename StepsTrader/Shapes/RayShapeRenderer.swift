import SwiftUI

/// Self-contained renderer for the "Rays" shape type.
/// Spotlight source stays at `basePosition`; the beam sweeps left/right via rotation.
@MainActor
enum RayShapeRenderer {

    static let symbolSize: CGFloat = 256

    /// Canvas draw radius = `normalizedSize × canvasDim × renderSizeScale`.
    static let renderSizeScale: Double = 2.2 * 1.5

    // Spotlight shader tuning — keep numeric values in sync with SpotlightShader.metal.
    // `nonisolated` so the off-main pixel loop (`renderSpotlightPixels`) can read them.
    nonisolated static let shaderAim: Float = 1.15
    nonisolated static let coneAngleMin: Float = 78
    nonisolated static let coneAngleMax: Float = 105
    nonisolated static let coneBreathSpeed: Float = 0.45

    /// Reference-date timestamps are ~8e8 seconds, which only have ~32-second
    /// resolution when narrowed to `Float`. That quantisation makes the shader's
    /// `sin(time * coneBreathSpeed)` jump 2+ full cycles between frames → visible
    /// brightness/cone-width pulsing. Wrap the Double timestamp with this period
    /// (an integer multiple of `2π / coneBreathSpeed`) before narrowing so the
    /// Float-side argument stays small and the sin wraps seamlessly.
    static let shaderTimeWrap: Double = (2 * .pi / Double(coneBreathSpeed)) * 100   // ≈ 1396.26 s

    /// Wraps a high-magnitude reference-date timestamp into a small range
    /// (multiple of the cone-breath period) so `Float(.)` keeps full precision
    /// for sub-second deltas.
    @inline(__always)
    static func wrapShaderTime(_ t: Double) -> Float {
        Float(t.truncatingRemainder(dividingBy: shaderTimeWrap))
    }

    // MARK: - Edit / Hit Test

    static func editBoundsDiameter(
        normalizedSize: Double,
        canvasDim: Double,
        shapeType: CanvasShapeType
    ) -> Double {
        let base = normalizedSize * canvasDim
        return shapeType == .rays ? base * renderSizeScale : base
    }

    static func editHitRadius(
        normalizedSize: Double,
        canvasDim: Double,
        shapeType: CanvasShapeType
    ) -> Double {
        editBoundsDiameter(normalizedSize: normalizedSize, canvasDim: canvasDim, shapeType: shapeType) * 0.5
    }

    // MARK: - Positioning

    /// Fixed source anchor — no positional wobble; sweep is rotation-only.
    /// `t` and `ampScale` are ignored but kept for uniform renderer dispatch.
    static func center(
        _ e: CanvasElement,
        size: CGSize,
        t: Double = 0,
        ampScale: Double = 1
    ) -> CGPoint {
        CGPoint(
            x: Double(e.basePosition.x) * Double(size.width),
            y: Double(e.basePosition.y) * Double(size.height)
        )
    }

    static func frozenCenter(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        center(e, size: size)
    }

    // MARK: - Sweep Animation

    /// Left/right oscillation around the fixed source corner.
    static func sweepAngle(_ e: CanvasElement, t: Double, ampScale: Double) -> Angle {
        let sweepRange = (40.0 + e.rotationSpeed * 0.8) * ampScale
        let sweepSpeed = 0.025 + e.driftSpeed * 0.015
        let sweep = sin(t * sweepSpeed + e.phaseOffset * 2.1) * sweepRange
        return Angle.degrees(sweep)
    }

    // MARK: - Drawing

    static func draw(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double,
        blendMode: GraphicsContext.BlendMode,
        ampScale: Double,
        interaction: ElementInteraction?
    ) {
        let dim = Double(min(size.width, size.height))
        let effectiveSize = Double(e.userSize ?? CGFloat(e.size))
        let radius = effectiveSize * dim * renderSizeScale
        let breathe = 0.80 + sin(t * e.pulseFrequency * 0.5 + e.phaseOffset) * 0.18
            + sin(t * e.pulseFrequency * 0.17 + e.phaseOffset * 1.7) * 0.08
        let sweep = sweepAngle(e, t: t, ampScale: ampScale)

        let attrOffset = interaction?.attractionOffset ?? .zero
        let c = center(e, size: size, t: t, ampScale: ampScale)
        let anchor = CGPoint(
            x: c.x + attrOffset.dx,
            y: c.y + attrOffset.dy
        )

        let canvasCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = canvasCenter.x - anchor.x
        let dy = canvasCenter.y - anchor.y
        let inwardAngle = Angle.radians(atan2(Double(dy), Double(dx)))
        let rotation = inwardAngle + .degrees(270) + Angle.radians(e.userRotation) + sweep

        let scaledRadius = radius * breathe
        let halfW = scaledRadius
        let halfH = scaledRadius
        let spotRect = CGRect(
            x: anchor.x - halfW,
            y: anchor.y - halfH,
            width: halfW * 2,
            height: halfH * 2
        )

        let opacity = (0.7 + breathe * 0.3) * (1.0 - decay * 0.4)

        if let symbol = context.resolveSymbol(id: e.id) {
            context.drawLayer { ctx in
                ctx.opacity = opacity
                ctx.blendMode = blendMode
                ctx.translateBy(x: anchor.x, y: anchor.y)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -anchor.x, y: -anchor.y)
                ctx.draw(symbol, in: spotRect)
            }
        } else {
            let seed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))
            let (near, mid, far) = resolveColors(e, seed: seed)
            // Wrap before narrowing to Float — see `shaderTimeWrap` doc.
            let shaderTime = wrapShaderTime(t + e.phaseOffset)

            guard let cgImage = renderSpotlightBitmap(
                size: Int(symbolSize),
                time: shaderTime,
                near: rgbComponents(near),
                mid: rgbComponents(mid),
                far: rgbComponents(far)
            ) else { return }

            let spotImage = Image(decorative: cgImage, scale: 1.0)
            context.drawLayer { ctx in
                ctx.opacity = opacity
                ctx.blendMode = blendMode
                ctx.translateBy(x: anchor.x, y: anchor.y)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -anchor.x, y: -anchor.y)
                ctx.draw(spotImage, in: spotRect)
            }
        }
    }

    // MARK: - Color Resolution

    private static func resolveColors(_ e: CanvasElement, seed: UInt64) -> (Color, Color, Color) {
        if let hex2 = e.hexColor2 {
            // Two-color gradient from tip (near) to edges (far)
            let n = Color(hex: e.hexColor)
            let f = Color(hex: hex2)
            return (n, Color.lerp(n, f, t: 0.5), f)
        } else {
            // Single color — uniform spotlight
            let baseColor = Color(hex: e.hexColor)
            return (baseColor, baseColor, baseColor)
        }
    }

    // MARK: - Radar Spotlight Cache (off the hot path)
    //
    // The radar (EnergySignatureView) draws one fixed-colour spotlight per axis.
    // The bitmap is *time-invariant* — the only time term in the shader is the
    // slow cone-width breath, which is imperceptible and is approximated here by
    // freezing the cone at mid-breath (time = 0). So each axis bitmap is rendered
    // exactly once, off the main thread, and cached permanently keyed by axis id.
    // The per-frame draw then becomes an O(1) dictionary lookup — no pixel work on
    // the render hot path. (The slow rotation + breathing scale + tip pulse are all
    // cheap transforms applied to this cached image, see EnergySignatureView.)
    //
    // NOTE: this is separate from `renderSpotlightBitmap`, which the Gallery canvas
    // element path still calls per-frame with live time for its sweeping shapes.

    private static var _radarSpotCache: [String: CGImage] = [:]

    /// Derives the radar gradient (near/mid/far) from a single axis colour —
    /// boosted at the source, full colour through the beam, dark at the edges.
    /// Kept here so the warm-up and the renderer agree on the exact colours.
    static func radarSpotlightColors(
        _ color: Color
    ) -> (near: (Float, Float, Float), mid: (Float, Float, Float), far: (Float, Float, Float)) {
        let (r, g, b) = rgbComponents(color)
        return (
            near: (min(1.0, r * 1.55), min(1.0, g * 1.55), min(1.0, b * 1.55)),
            mid:  (r, g, b),
            far:  (r * 0.35, g * 0.35, b * 0.35)
        )
    }

    /// Returns the cached radar bitmap for `id` if it has already been rendered,
    /// otherwise `nil`. Never renders synchronously — the hot path stays pixel-free;
    /// callers simply skip the ray until `warmRadarSpotlights` has filled the cache.
    static func radarSpotlightIfReady(id: String) -> CGImage? {
        _radarSpotCache[id]
    }

    /// Renders any not-yet-cached radar bitmaps on a background task, then publishes
    /// the results into the cache on the main actor. Idempotent and safe to call
    /// repeatedly (e.g. from `.task`); colours are fixed per axis id so a single warm
    /// per id suffices for the lifetime of the process.
    static func warmRadarSpotlights(_ specs: [(id: String, color: Color)]) async {
        // Resolve colours on the main actor (UIColor access), skip already-cached ids.
        let work: [(id: String, colors: (near: (Float, Float, Float),
                                         mid:  (Float, Float, Float),
                                         far:  (Float, Float, Float)))] =
            specs
                .filter { _radarSpotCache[$0.id] == nil }
                .map { (id: $0.id, colors: radarSpotlightColors($0.color)) }
        guard !work.isEmpty else { return }

        let size = Int(symbolSize)
        // Heavy pixel loop runs off the main thread; we ferry raw RGBA `Data`
        // (Sendable) back and build the CGImage on the main actor.
        let rendered: [(id: String, data: Data)] = await Task.detached(priority: .userInitiated) {
            work.compactMap { spec in
                guard let data = renderSpotlightPixels(
                    size: size, time: 0,
                    near: spec.colors.near, mid: spec.colors.mid, far: spec.colors.far
                ) else { return nil }
                return (id: spec.id, data: data)
            }
        }.value

        for item in rendered where _radarSpotCache[item.id] == nil {
            if let img = makeCGImage(from: item.data, size: size) {
                _radarSpotCache[item.id] = img
            }
        }
    }

    // MARK: - CPU Spotlight Renderer (pixel-matched to SpotlightShader.metal)

    /// Exposed for use by EnergySignatureView.
    static func rgbComponents(_ color: Color) -> (Float, Float, Float) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
        return (Float(r), Float(g), Float(b))
    }

    nonisolated private static func sstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Pixel-accurate CPU port of `spotlightEffect` from SpotlightShader.metal.
    /// Produces a premultiplied-alpha CGImage matching the Metal shader output.
    /// ~10ms per 256×256 element on modern iPhones. Exposed for EnergySignatureView.
    ///
    /// `nonisolated` so the heavy pixel loop can run off the main actor (see
    /// `warmRadarSpotlights`). It only reads immutable `Sendable` shader constants.
    nonisolated static func renderSpotlightBitmap(
        size: Int,
        time: Float,
        near: (Float, Float, Float),
        mid: (Float, Float, Float),
        far: (Float, Float, Float)
    ) -> CGImage? {
        guard let data = renderSpotlightPixels(
            size: size, time: time, near: near, mid: mid, far: far
        ) else { return nil }
        return makeCGImage(from: data, size: size)
    }

    /// The heavy CPU work: produces raw premultiplied RGBA pixel `Data` (Sendable),
    /// so it can be computed on a background task and the CGImage built later.
    nonisolated static func renderSpotlightPixels(
        size: Int,
        time: Float,
        near: (Float, Float, Float),
        mid: (Float, Float, Float),
        far: (Float, Float, Float)
    ) -> Data? {
        let w = size, h = size
        let resF = Float(w)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        let nearC = SIMD3<Float>(near.0, near.1, near.2)
        let midC  = SIMD3<Float>(mid.0,  mid.1,  mid.2)
        let farC  = SIMD3<Float>(far.0,  far.1,  far.2)

        let lightPos = SIMD2<Float>(-0.5, -0.5)
        let aim = shaderAim
        let dirN = SIMD2<Float>(sinf(aim), cosf(aim))
        let coneSpan = coneAngleMax - coneAngleMin
        let coneAngle = coneAngleMin + coneSpan * (0.5 + 0.5 * sinf(time * coneBreathSpeed))
        let halfRad = coneAngle * 0.5 * .pi / 180
        let halfSq06 = halfRad * halfRad * 0.6
        let ones = SIMD3<Float>(repeating: 1)

        for y in 0..<h {
            let fy = (Float(y) + 0.5) / resF
            let py = fy - 1
            for x in 0..<w {
                let fx = (Float(x) + 0.5) / resF
                let px = fx - 1

                let dltX = px - lightPos.x
                let dltY = py - lightPos.y
                let dist = sqrtf(dltX * dltX + dltY * dltY)

                let lx: Float, ly: Float
                if dist > 1e-4 { lx = dltX / dist; ly = dltY / dist }
                else { lx = dirN.x; ly = dirN.y }

                let dotVal = min(max(lx * dirN.x + ly * dirN.y, -1), 1)
                let pxAngle = acosf(dotVal)
                let cone = expf(-pxAngle * pxAngle / halfSq06)
                let att = 1 / (1.35 + 5.5 * dist * dist + 1.2 * dist)
                let light = cone * att

                let angT = min(max(pxAngle / max(halfRad, 0.01), 0), 1)
                let angColor: SIMD3<Float>
                if angT < 0.5 {
                    angColor = nearC + (midC - nearC) * (angT * 2)
                } else {
                    angColor = midC + (farC - midC) * ((angT - 0.5) * 2)
                }

                let tRad = powf(sstep(0.04, 0.68, dist), 0.82)
                var radColor = nearC + (midC - nearC) * min(max(tRad / 0.3, 0), 1)
                radColor = radColor + (farC - radColor) * min(max((tRad - 0.3) / 0.62, 0), 1)

                let rMix = 1 - expf(-dist * 2.5)
                var lc = radColor + (angColor - radColor) * rMix

                let hotspot = expf(-dist * dist * 12)
                lc = pointwiseMin(lc + nearC * hotspot * 0.4, ones)

                let coreMul: Float = 0.62 + 0.38 * sstep(0, 0.26, dist)
                let lightT = powf(min(max(light, 0), 1), 1.12)
                var ww = lightT * coreMul * 1.35

                let cx = fx - 0.5, cy = fy - 0.5
                let edgeFade = 1 - sstep(0.6, 1, sqrtf(cx * cx + cy * cy) * 2)
                ww *= edgeFade

                let a = min(max(ww, 0), 1)
                let premul = lc * a

                let idx = (y * w + x) * 4
                pixels[idx]     = UInt8(min(max(premul.x, 0), 1) * 255)
                pixels[idx + 1] = UInt8(min(max(premul.y, 0), 1) * 255)
                pixels[idx + 2] = UInt8(min(max(premul.z, 0), 1) * 255)
                pixels[idx + 3] = UInt8(a * 255)
            }
        }

        return Data(pixels)
    }

    /// Wraps premultiplied RGBA `Data` into a CGImage. Cheap; safe on any thread.
    nonisolated static func makeCGImage(from data: Data, size: Int) -> CGImage? {
        let w = size, h = size
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
