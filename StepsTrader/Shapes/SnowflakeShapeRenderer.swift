import SwiftUI

/// Self-contained renderer for the "Snowflake" shape type.
/// Provides positioning (Lissajous drift with wandering home zone),
/// symmetric rectmorph outline with morphing animation, and trail ghosts.
@MainActor
enum SnowflakeShapeRenderer {

    // MARK: - Positioning (Lissajous drift)

    private static let clampMargin: Double = 0.06

    private static func rawDriftState(
        _ e: CanvasElement,
        t: Double,
        ampScale: Double
    ) -> (nx: Double, ny: Double, vx: Double, vy: Double) {
        let p = e.phaseOffset
        let speed = 0.018 + e.driftSpeed * 0.035
        let amp = ampScale
        let freq = MindFrequencyProfile(phase: p)

        let mod = sin(t * speed * 0.08 + p * 3.7) * sin(t * speed * 0.04 + p * 1.3)
        let env = 0.75 + 0.25 * mod

        let hx = Double(e.basePosition.x) + sin(t * speed * 0.03 + p) * 0.10
        let hy = Double(e.basePosition.y) + cos(t * speed * 0.025 + p * 1.3) * 0.10

        let smoothFx1 = freq.fx1 * 0.6
        let smoothFx2 = freq.fx2 * 0.45
        let smoothFx3 = freq.fx3 * 0.25
        let smoothFy1 = freq.fy1 * 0.6
        let smoothFy2 = freq.fy2 * 0.45
        let smoothFy3 = freq.fy3 * 0.25

        let dx1 = sin(t * speed * smoothFx1 + p) * 0.22 * amp * env
        let dx2 = sin(t * speed * smoothFx2 + p * 2.3) * 0.07 * amp * env
        let dx3 = sin(t * speed * smoothFx3 + p * 4.1) * 0.02 * amp

        let dy1 = cos(t * speed * smoothFy1 + p * 1.7) * 0.20 * amp * env
        let dy2 = cos(t * speed * smoothFy2 + p * 3.1) * 0.06 * amp * env
        let dy3 = cos(t * speed * smoothFy3 + p * 5.3) * 0.02 * amp

        let nx = hx + dx1 + dx2 + dx3
        let ny = hy + dy1 + dy2 + dy3

        let vx1 = cos(t * speed * smoothFx1 + p) * speed * smoothFx1 * 0.22 * amp * env
        let vx2 = cos(t * speed * smoothFx2 + p * 2.3) * speed * smoothFx2 * 0.07 * amp * env
        let vx3 = cos(t * speed * smoothFx3 + p * 4.1) * speed * smoothFx3 * 0.02 * amp

        let vy1 = -sin(t * speed * smoothFy1 + p * 1.7) * speed * smoothFy1 * 0.20 * amp * env
        let vy2 = -sin(t * speed * smoothFy2 + p * 3.1) * speed * smoothFy2 * 0.06 * amp * env
        let vy3 = -sin(t * speed * smoothFy3 + p * 5.3) * speed * smoothFy3 * 0.02 * amp

        return (nx, ny, vx1 + vx2 + vx3, vy1 + vy2 + vy3)
    }

    static func driftPosition(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        let s = rawDriftState(e, t: t, ampScale: ampScale)
        let m = clampMargin
        let cx = min(1.0 - m, max(m, s.nx)) * Double(size.width)
        let cy = min(1.0 - m, max(m, s.ny)) * Double(size.height)
        return CGPoint(x: cx, y: cy)
    }

    static func center(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double,
        renderCache: RenderCache
    ) -> CGPoint {
        if let cached = renderCache.mindPositionCache[e.id],
           t == renderCache.mindPositionCacheTime {
            return cached
        }
        return driftPosition(e, size: size, t: t, ampScale: ampScale)
    }

    static func frozenCenter(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        driftPosition(e, size: size, t: t, ampScale: ampScale)
    }

    static func driftVelocity(
        _ e: CanvasElement,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        let s = rawDriftState(e, t: t, ampScale: ampScale)
        let m = clampMargin
        let edgeWidth = 0.04

        @inline(__always) func soft(_ d: Double) -> Double {
            max(0.0, min(1.0, d / edgeWidth))
        }
        let leftAllow  = soft(s.nx - m)
        let rightAllow = soft(1.0 - m - s.nx)
        let topAllow   = soft(s.ny - m)
        let botAllow   = soft(1.0 - m - s.ny)

        var vx = s.vx
        var vy = s.vy
        if vx < 0 { vx *= leftAllow }
        if vx > 0 { vx *= rightAllow }
        if vy < 0 { vy *= topAllow }
        if vy > 0 { vy *= botAllow }

        let mag2 = vx * vx + vy * vy
        let rawMag2 = s.vx * s.vx + s.vy * s.vy
        let cornerBand = rawMag2 * 0.0025
        if rawMag2 > 1e-9, mag2 < cornerBand {
            let bleed = max(0.0, 1.0 - mag2 / cornerBand)
            vx += s.vx * bleed * 0.05
            vy += s.vy * bleed * 0.05
        }
        return CGPoint(x: vx, y: vy)
    }

    // MARK: - Sizing

    static let sizeScale: Double = 1.1

    static func radius(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> Double {
        let breathePhase = sin(t * (0.25 + e.phaseOffset * 0.1) + e.phaseOffset * 3.7)
        let pulse = 1.0 + breathePhase * 0.015 * ampScale
        let dim = Double(min(size.width, size.height))
        let effectiveSize = Double(e.userSize ?? CGFloat(e.size))
        return effectiveSize * dim * sizeScale * pulse
    }

    // MARK: - Pre-compute Positions

    static func precomputePositions(
        elements: [CanvasElement],
        shapeFilter: (CanvasElement) -> Bool,
        size: CGSize,
        t: Double,
        ampScale: Double,
        renderCache: RenderCache
    ) {
        var posHasher = Hasher()
        for e in elements where shapeFilter(e) {
            posHasher.combine(e.id)
            posHasher.combine(e.basePosition.x)
            posHasher.combine(e.basePosition.y)
        }
        let elemHash = posHasher.finalize()
        if t != renderCache.mindPositionCacheTime || elemHash != renderCache.mindPositionCacheElementHash {
            renderCache.mindPositionCache.removeAll(keepingCapacity: true)
            for e in elements where shapeFilter(e) {
                renderCache.mindPositionCache[e.id] = driftPosition(e, size: size, t: t, ampScale: ampScale)
            }
            renderCache.mindPositionCacheTime = t
            renderCache.mindPositionCacheElementHash = elemHash
        }
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
        renderCache: RenderCache,
        decayedColor: Color? = nil,
        decayedColor2: Color? = nil
    ) {
        let breathePhase = sin(t * (0.25 + e.phaseOffset * 0.1) + e.phaseOffset * 3.7)
        let center = center(e, size: size, t: t, ampScale: ampScale, renderCache: renderCache)
        let r = radius(e, size: size, t: t, ampScale: ampScale)
        let seed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))
        let idleOpacity = (0.92 + breathePhase * 0.04) * (1.0 - decay * 0.3)
        let trailLen = 20
        let trailSpacing: Double = 0.7
        let trailPeak: Double = 0.30
        let strokeW: CGFloat = 1.2

        let currentTick = Int(t / trailSpacing)

        if currentTick != renderCache.trailLastPruneTick {
            let oldestKeep = currentTick - trailLen - 1
            renderCache.trailFrames = renderCache.trailFrames.filter { $0.key.tickIndex >= oldestKeep }
            renderCache.trailLastPruneTick = currentTick
        }

        for k in (1...trailLen).reversed() {
            let tickIndex = currentTick - k
            guard tickIndex >= 0 else { continue }
            let trailKey = RenderCache.TrailKey(elementId: e.id, tickIndex: tickIndex)

            let cached: (center: CGPoint, frame: ProceduralShapeGenerator.RectMorphFrame)
            if let hit = renderCache.trailFrames[trailKey] {
                cached = hit
            } else {
                let ghostT = Double(tickIndex) * trailSpacing
                let ghostCenter = driftPosition(e, size: size, t: ghostT, ampScale: ampScale)
                let ghostRect = CGRect(
                    x: ghostCenter.x - r, y: ghostCenter.y - r,
                    width: r * 2, height: r * 2
                )
                let ghostFrame = ProceduralShapeGenerator.rectMorphFrame(
                    seed: seed, time: ghostT, in: ghostRect,
                    elementColor: decayedColor, elementColor2: decayedColor2
                )
                cached = (ghostCenter, ghostFrame)
                renderCache.trailFrames[trailKey] = cached
            }

            let linearAge = Double(trailLen - k + 1) / Double(trailLen + 1)
            let ghostAlpha = pow(linearAge, 2.2) * trailPeak
            context.drawLayer { ctx in
                ctx.opacity = ghostAlpha * idleOpacity
                ctx.blendMode = blendMode


                let c1 = cached.frame.color
                let c2 = cached.frame.color2 ?? c1

                let ghostFillGrad = Gradient(stops: [
                    .init(color: c1.opacity(0.06), location: 0),
                    .init(color: c2.opacity(0.14), location: 1.0),
                ])
                ctx.fill(
                    cached.frame.path,
                    with: .conicGradient(ghostFillGrad, center: cached.center, angle: .degrees(Double(tickIndex) * 15))
                )

                let strokeGrad = Gradient(colors: [c1, c2, c1])
                ctx.stroke(
                    cached.frame.path,
                    with: .conicGradient(strokeGrad, center: cached.center, angle: .degrees(Double(tickIndex) * 15)),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
            }
        }

        let morphRect = CGRect(
            x: center.x - r, y: center.y - r,
            width: r * 2, height: r * 2
        )
        let currentFrame = ProceduralShapeGenerator.rectMorphFrame(
            seed: seed, time: t, in: morphRect,
            elementColor: decayedColor, elementColor2: decayedColor2
        )

        let c1 = decayedColor ?? currentFrame.color
        let c2 = decayedColor2 ?? currentFrame.color2 ?? c1

        let rotAngle = Angle.degrees(t * 8 + e.phaseOffset * 120)

        context.drawLayer { ctx in
            ctx.opacity = idleOpacity
            ctx.blendMode = blendMode

            let fillGrad = Gradient(stops: [
                .init(color: c1.opacity(0.12), location: 0),
                .init(color: c2.opacity(0.28), location: 0.5),
                .init(color: c1.opacity(0.12), location: 1.0),
            ])
            ctx.fill(
                currentFrame.path,
                with: .conicGradient(fillGrad, center: center, angle: rotAngle)
            )

            let strokeGrad = Gradient(stops: [
                .init(color: c1, location: 0),
                .init(color: c2, location: 0.5),
                .init(color: c1, location: 1.0),
            ])
            ctx.stroke(
                currentFrame.path,
                with: .conicGradient(strokeGrad, center: center, angle: rotAngle),
                style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
