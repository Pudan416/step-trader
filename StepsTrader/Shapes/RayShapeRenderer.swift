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
            drawSoftwareCone(
                context: &context,
                anchor: anchor,
                radius: scaledRadius,
                rotation: rotation,
                coneHalfAngle: .degrees(35 + Double(seed % 20)),
                near: near, mid: mid, far: far,
                opacity: opacity,
                blendMode: blendMode,
                time: t,
                phase: e.phaseOffset
            )
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

    // MARK: - Software Fallback

    /// Draws a spotlight cone using layered CoreGraphics paths + gradients
    /// with Gaussian blur to closely approximate the Metal `spotlightEffect`
    /// shader. Used by ImageRenderer (wallpaper export, history thumbnails)
    /// where Metal shaders are unavailable.
    private static func drawSoftwareCone(
        context: inout GraphicsContext,
        anchor: CGPoint,
        radius: Double,
        rotation: Angle,
        coneHalfAngle: Angle,
        near: Color,
        mid: Color,
        far: Color,
        opacity: Double,
        blendMode: GraphicsContext.BlendMode,
        time: Double,
        phase: Double
    ) {
        let halfRad = coneHalfAngle.radians
        let r = CGFloat(radius)
        let blur = r * 0.035

        context.drawLayer { ctx in
            ctx.opacity = opacity
            ctx.blendMode = blendMode
            ctx.translateBy(x: anchor.x, y: anchor.y)
            ctx.rotate(by: rotation)

            // Layer 1: Wide outer glow (far color, large cone)
            let outerHalf = halfRad * 1.35
            var outerPath = Path()
            outerPath.move(to: .zero)
            outerPath.addArc(
                center: .zero, radius: r,
                startAngle: .radians(-.pi / 2 - outerHalf),
                endAngle:   .radians(-.pi / 2 + outerHalf),
                clockwise: false
            )
            outerPath.closeSubpath()

            ctx.drawLayer { outer in
                outer.addFilter(.blur(radius: blur * 1.8))
                let grad = Gradient(stops: [
                    .init(color: mid.opacity(0.50), location: 0),
                    .init(color: far.opacity(0.30), location: 0.3),
                    .init(color: far.opacity(0.10), location: 0.65),
                    .init(color: far.opacity(0.0),  location: 1.0),
                ])
                outer.fill(outerPath, with: .radialGradient(grad, center: .zero, startRadius: 0, endRadius: r))
            }

            // Layer 2: Main cone body
            var mainPath = Path()
            mainPath.move(to: .zero)
            mainPath.addArc(
                center: .zero, radius: r * 0.92,
                startAngle: .radians(-.pi / 2 - halfRad),
                endAngle:   .radians(-.pi / 2 + halfRad),
                clockwise: false
            )
            mainPath.closeSubpath()

            ctx.drawLayer { main in
                main.addFilter(.blur(radius: blur))
                let grad = Gradient(stops: [
                    .init(color: near.opacity(0.90), location: 0),
                    .init(color: mid.opacity(0.60),  location: 0.25),
                    .init(color: far.opacity(0.25),  location: 0.55),
                    .init(color: far.opacity(0.04),  location: 0.85),
                    .init(color: far.opacity(0.0),   location: 1.0),
                ])
                main.fill(mainPath, with: .radialGradient(grad, center: .zero, startRadius: 0, endRadius: r * 0.92))
            }

            // Layer 3: Narrow bright core (near color, tight cone)
            let coreHalf = halfRad * 0.4
            let coreR = r * 0.7
            var corePath = Path()
            corePath.move(to: .zero)
            corePath.addArc(
                center: .zero, radius: coreR,
                startAngle: .radians(-.pi / 2 - coreHalf),
                endAngle:   .radians(-.pi / 2 + coreHalf),
                clockwise: false
            )
            corePath.closeSubpath()

            ctx.drawLayer { core in
                core.addFilter(.blur(radius: blur * 0.7))
                let grad = Gradient(stops: [
                    .init(color: near.opacity(0.85), location: 0),
                    .init(color: near.opacity(0.45), location: 0.30),
                    .init(color: mid.opacity(0.12),  location: 0.65),
                    .init(color: mid.opacity(0.0),   location: 1.0),
                ])
                core.fill(corePath, with: .radialGradient(grad, center: .zero, startRadius: 0, endRadius: coreR))
            }

            // Layer 4: Hotspot glow at origin
            let hotR = r * 0.15
            ctx.drawLayer { hot in
                hot.addFilter(.blur(radius: hotR * 0.5))
                let grad = Gradient(stops: [
                    .init(color: near.opacity(0.95), location: 0),
                    .init(color: near.opacity(0.50), location: 0.4),
                    .init(color: near.opacity(0.0),  location: 1.0),
                ])
                let hotRect = CGRect(x: -hotR, y: -hotR, width: hotR * 2, height: hotR * 2)
                hot.fill(Ellipse().path(in: hotRect), with: .radialGradient(grad, center: .zero, startRadius: 0, endRadius: hotR))
            }
        }
    }
}
