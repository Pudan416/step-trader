import SwiftUI

/// Self-contained renderer for the "Rays" shape type.
/// Provides positioning (edge-anchored with wobble), Metal spotlight shader
/// rendering via resolved Canvas symbols, and sweep oscillation animation.
@MainActor
enum RayShapeRenderer {

    static let symbolSize: CGFloat = 256

    // MARK: - Positioning

    static func center(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        let w = Double(size.width)
        let h = Double(size.height)
        let cx = Double(e.basePosition.x) * w
        let cy = Double(e.basePosition.y) * h
        let amp = ampScale
        let wobbleX = sin(t * 0.018 + e.phaseOffset) * w * 0.014 * amp
            + sin(t * 0.009 + e.phaseOffset * 2.3) * w * 0.007 * amp
        let wobbleY = cos(t * 0.015 + e.phaseOffset * 1.3) * h * 0.014 * amp
            + cos(t * 0.008 + e.phaseOffset * 0.7) * h * 0.007 * amp
        return CGPoint(x: cx + wobbleX, y: cy + wobbleY)
    }

    static func frozenCenter(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        center(e, size: size, t: t, ampScale: ampScale)
    }

    // MARK: - Sweep Animation

    static func sweepAngle(_ e: CanvasElement, t: Double, ampScale: Double) -> Angle {
        let sweepRange = (35.0 + e.rotationSpeed * 0.6) * ampScale
        let sweepSpeed = 0.025 + e.driftSpeed * 0.015
        let sweep = sin(t * sweepSpeed + e.phaseOffset * 2.1) * sweepRange
            + sin(t * sweepSpeed * 0.37 + e.phaseOffset * 0.8) * sweepRange * 0.3
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
        let effectiveSize = e.userSize ?? e.size
        let radius = Double(effectiveSize) * dim * 2.2
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
            let shaderTime = Float(t + e.phaseOffset)

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
            let n = Color(hex: e.hexColor)
            let f = Color(hex: hex2)
            return (n, Color.lerp(n, f, t: 0.5), f)
        } else {
            return ProceduralShapeGenerator.spotlightColors(seed: seed)
        }
    }

    // MARK: - CPU Spotlight Renderer (pixel-matched to SpotlightShader.metal)

    private static func rgbComponents(_ color: Color) -> (Float, Float, Float) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
        return (Float(r), Float(g), Float(b))
    }

    private static func sstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Pixel-accurate CPU port of `spotlightEffect` from SpotlightShader.metal.
    /// Produces a premultiplied-alpha CGImage matching the Metal shader output.
    /// ~10ms per 256×256 element on modern iPhones.
    private static func renderSpotlightBitmap(
        size: Int,
        time: Float,
        near: (Float, Float, Float),
        mid: (Float, Float, Float),
        far: (Float, Float, Float)
    ) -> CGImage? {
        let w = size, h = size
        let resF = Float(w)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        let nearC = SIMD3<Float>(near.0, near.1, near.2)
        let midC  = SIMD3<Float>(mid.0,  mid.1,  mid.2)
        let farC  = SIMD3<Float>(far.0,  far.1,  far.2)

        let lightPos = SIMD2<Float>(-0.5, -0.5)
        let aim = 1.15 + 0.55 * sinf(time * 0.55)
        let dirN = SIMD2<Float>(sinf(aim), cosf(aim))
        let coneAngle: Float = 30 + 80 * (0.5 + 0.5 * sinf(time * 0.45))
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

        let data = Data(pixels)
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
