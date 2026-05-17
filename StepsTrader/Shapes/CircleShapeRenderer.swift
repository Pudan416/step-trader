import SwiftUI

/// Self-contained renderer for the "Circle" shape type.
/// Dense gradient-filled perfect circles that overlap and blend.
/// No organic deformation — geometry is always a clean ellipse.
/// Radial gradient is thick and saturated (unlike the hollow rim
/// gradient of blobs), producing the layered risograph look.
@MainActor
enum CircleShapeRenderer {

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
        let wobbleX = sin(t * 0.012 + e.phaseOffset) * w * 0.004 * amp
            + sin(t * 0.006 + e.phaseOffset * 2.1) * w * 0.002 * amp
        let wobbleY = cos(t * 0.010 + e.phaseOffset * 1.4) * h * 0.004 * amp
            + cos(t * 0.007 + e.phaseOffset * 0.9) * h * 0.002 * amp
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

    // MARK: - Sizing

    static let sizeScale: Double = 1.15

    static func radius(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> Double {
        let dim = Double(min(size.width, size.height))
        let effectiveSize = e.userSize ?? e.size
        let pulse = 1.0 + sin(t * (0.2 + e.pulseFrequency * 0.2) + e.phaseOffset) * 0.015 * ampScale
        return Double(effectiveSize) * dim * sizeScale * pulse
    }

    // MARK: - Single Element Drawing

    static func draw(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double,
        blendMode: GraphicsContext.BlendMode,
        ampScale: Double,
        interaction: ElementInteraction?,
        decayedColor: Color,
        decayedColor2: Color? = nil
    ) {
        let c = center(e, size: size, t: t, ampScale: ampScale)
        let r = radius(e, size: size, t: t, ampScale: ampScale)
        let rotation = Angle.radians(e.phaseOffset * 0.3 + e.userRotation)
        let seed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))

        drawFill(
            center: c, radius: r,
            color: decayedColor, color2: decayedColor2,
            phase: e.phaseOffset,
            seed: seed,
            rotation: rotation,
            blendMode: blendMode,
            context: &context
        )
    }

    // MARK: - Fill Style

    /// Deterministic per-element style derived from seed.
    /// ~50% solid, ~50% gradient. Opacity varies ±15%.
    private struct FillStyle {
        let isSolid: Bool
        let opacityMul: Double   // 0.85 … 1.0

        init(seed: UInt64) {
            isSolid = (seed &>> 3) % 2 == 0
            let opacityBits = Double((seed &>> 7) % 16) / 15.0
            opacityMul = 0.85 + opacityBits * 0.15
        }
    }

    // MARK: - Fill Rendering

    static func drawFill(
        center: CGPoint,
        radius r: Double,
        color: Color,
        color2: Color?,
        phase: Double,
        seed: UInt64,
        rotation: Angle,
        blendMode: GraphicsContext.BlendMode,
        context: inout GraphicsContext
    ) {
        let style = FillStyle(seed: seed)
        let innerColor = color
        let outerColor = color2 ?? color
        let om = style.opacityMul

        let ellipse = CGRect(
            x: center.x - r, y: center.y - r,
            width: r * 2, height: r * 2
        )
        let circlePath = Path(ellipseIn: ellipse)

        context.drawLayer { ctx in
            ctx.blendMode = blendMode
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)

            if style.isSolid {
                let blendColor = color2 != nil
                    ? Color.lerp(innerColor, outerColor, t: 0.35)
                    : innerColor
                let solidGrad = Gradient(stops: [
                    .init(color: blendColor.opacity(0.92 * om), location: 0),
                    .init(color: blendColor.opacity(0.88 * om), location: 0.75),
                    .init(color: blendColor.opacity(0.35 * om), location: 1.0),
                ])
                ctx.fill(
                    circlePath,
                    with: .radialGradient(solidGrad, center: center, startRadius: 0, endRadius: r)
                )
            } else {
                let gradCenter: CGPoint
                if color2 != nil {
                    let offsetAngle = phase * 2.3
                    let offsetR = r * 0.20
                    gradCenter = CGPoint(
                        x: center.x + CGFloat(cos(offsetAngle)) * offsetR,
                        y: center.y + CGFloat(sin(offsetAngle)) * offsetR
                    )
                } else {
                    gradCenter = center
                }

                let grad = Gradient(stops: [
                    .init(color: innerColor.opacity(0.95 * om), location: 0),
                    .init(color: innerColor.opacity(0.90 * om), location: 0.30),
                    .init(color: outerColor.opacity(0.80 * om), location: 0.55),
                    .init(color: outerColor.opacity(0.60 * om), location: 0.78),
                    .init(color: outerColor.opacity(0.30 * om), location: 1.0),
                ])
                ctx.fill(
                    circlePath,
                    with: .radialGradient(grad, center: gradCenter, startRadius: 0, endRadius: r)
                )
            }
        }
    }
}
