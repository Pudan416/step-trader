import SwiftUI

/// Renderer for "Organic Blob" shape type.
///
/// Each element = one cohesive blob with depth: 4 sublayers at the same center,
/// back layers slightly larger and more blurred (halo), front layer = crisp core.
/// Radial gradient fill (0.8 → 0.3 → 0), crisp stroke, plusLighter blend.
@MainActor
enum OrganicBlobShapeRenderer {

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
        let wobbleX = sin(t * 0.010 + e.phaseOffset) * w * 0.003 * amp
            + sin(t * 0.006 + e.phaseOffset * 2.5) * w * 0.002 * amp
        let wobbleY = cos(t * 0.011 + e.phaseOffset * 1.2) * h * 0.003 * amp
            + cos(t * 0.007 + e.phaseOffset * 0.8) * h * 0.002 * amp
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

    static let sizeScale: Double = 1.1

    static func radius(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> Double {
        let dim = Double(min(size.width, size.height))
        let effectiveSize = Double(e.userSize ?? CGFloat(e.size))
        let breathe = 1.0 + 0.05 * sin(t * 0.15 + e.phaseOffset) * ampScale
        return effectiveSize * dim * sizeScale * breathe
    }

    // MARK: - Constants

    private static let layerCount = 4
    private static let blurSpread: Double = 8.0
    private static let baseOpacity: Double = 0.60
    private static let seedStride: UInt64 = 7919

    // MARK: - Drawing

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
        decayedColor2: Color? = nil,
        spec: TextureSpec = TextureSpec(kind: .gradient, density: 0.5, uniformity: 1, angle: 0),
        cache: RenderCache
    ) {
        let elementCenter = center(e, size: size, t: t, ampScale: ampScale)
        let elementRadius = radius(e, size: size, t: t, ampScale: ampScale)
        let baseSeed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))
        let baseComplexity = min(1.0, Double(e.activityCount ?? 1) / 30.0)
        let complexity = min(1.0, baseComplexity + (interaction?.noiseBoost ?? 0))
        let symmetry = 1
        let color = decayedColor
        let color2 = decayedColor2 ?? decayedColor
        let isTwoColor = decayedColor2 != nil

        var styleRng = SeededRNG(seed: baseSeed &+ 0xC010)
        let gradOffsetAngle = styleRng.nextDouble(in: 0...(2 * .pi))
        let gradOffsetFraction = styleRng.nextDouble(in: 0.15...0.35)

        for layer in 0..<layerCount {
            let layerSeed = baseSeed &+ UInt64(layer) &* seedStride

            let cx = Double(elementCenter.x)
            let cy = Double(elementCenter.y)
            // Back layers slightly larger (halo), front = core size
            let scale = 1.0 + Double(layerCount - 1 - layer) * 0.08
            let baseRadius = elementRadius * scale

            let layerT = t + Double(layer) * 2.3
            let breathe = 1.0 + 0.05 * sin(layerT * 0.15)
            let radius = CGFloat(baseRadius * breathe)

            let layerOpacity = baseOpacity * (1.0 - Double(layer) * 0.08)
            let blurRadius = blurSpread * Double(layer + 1) / Double(layerCount)

            let layerRadii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                seed: layerSeed, complexity: complexity, symmetry: symmetry, time: layerT)
            let path = ProceduralShapeGenerator.closedPath(
                radii: layerRadii,
                center: CGPoint(x: cx, y: cy),
                radius: Double(radius))

            // Only the front layer carries the texture; the halo layers stay
            // soft gradients, which is what keeps the glow.
            let layerSpec = layer == layerCount - 1
                ? spec
                : TextureSpec(kind: .gradient, density: spec.density,
                              uniformity: spec.uniformity, angle: spec.angle)

            // Cached, not regenerated per frame — see the Global Constraint.
            // The contour above is still computed every frame (it has to
            // morph); only the fill geometry is bucketed. complexity is part
            // of the cache key: it drives organicBlobRadiusFactor's
            // amplitude/ringRadius, so it changes the contour's shape, not
            // just layerRadii's values within it — a stale key would keep
            // serving geometry built for a contour the element no longer has.
            let textureGeometry = cache.textureGeometry(
                seed: layerSeed, spec: layerSpec, radii: layerRadii,
                complexity: complexity, time: layerT)

            let gradCenter = CGPoint(
                x: cx + cos(gradOffsetAngle) * Double(radius) * gradOffsetFraction,
                y: cy + sin(gradOffsetAngle) * Double(radius) * gradOffsetFraction)

            context.drawLayer { ctx in
                ctx.blendMode = blendMode
                ctx.opacity = max(0.05, layerOpacity)

                ProceduralTexture.draw(
                    textureGeometry, spec: layerSpec, contour: path,
                    context: &ctx, center: CGPoint(x: cx, y: cy), radius: Double(radius),
                    color: color, color2: isTwoColor ? color2 : nil,
                    gradientCenter: gradCenter)

                if blurRadius > 1 {
                    ctx.addFilter(.blur(radius: blurRadius))
                }

                let strokeColor = isTwoColor ? color2 : color
                ctx.stroke(path, with: .color(strokeColor.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
