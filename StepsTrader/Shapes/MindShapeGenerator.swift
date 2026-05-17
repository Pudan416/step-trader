import SwiftUI

extension ProceduralShapeGenerator {

    /// Generates a closed symmetric crystal/star shape using the superformula.
    static func mindPath(
        seed: UInt64,
        complexity: Double = 0.0,
        time: Double = 0,
        in rect: CGRect
    ) -> Path {
        var rng = SeededRNG(seed: seed)

        let mOptions: [Double] = [3, 4, 5, 6, 8]
        let m = mOptions[rng.nextInt(in: 0...(mOptions.count - 1))]
        let n1 = rng.nextDouble(in: 0.3...3.0)
        let n2 = rng.nextDouble(in: 0.5...4.0)
        let n3 = rng.nextDouble(in: 0.5...4.0)
        let a = rng.nextDouble(in: 0.8...1.2)
        let b = rng.nextDouble(in: 0.8...1.2)

        let cx = rect.midX
        let cy = rect.midY
        let scale = min(rect.width, rect.height) / 2

        let pointCount = 72 + Int(complexity * 48)
        var points = [CGPoint]()
        points.reserveCapacity(pointCount)
        var maxR: Double = 0

        var rawPoints = [(Double, Double)]()
        for i in 0..<pointCount {
            let theta = (Double(i) / Double(pointCount)) * 2 * .pi
            let r = superformulaRadius(theta: theta, m: m, n1: n1, n2: n2, n3: n3, a: a, b: b)
            rawPoints.append((theta, r))
            if r > maxR { maxR = r }
        }

        guard maxR > 0 else { return Path(ellipseIn: rect) }
        let normFactor = 0.85 / maxR

        for (theta, r) in rawPoints {
            let nr = r * normFactor
            let x = cx + CGFloat(cos(theta) * nr) * scale
            let y = cy + CGFloat(sin(theta) * nr) * scale
            points.append(CGPoint(x: x, y: y))
        }

        return smoothClosedPath(through: points)
    }

    private static func superformulaRadius(
        theta: Double, m: Double,
        n1: Double, n2: Double, n3: Double,
        a: Double, b: Double
    ) -> Double {
        let angle = m * theta / 4.0
        let cosComponent = pow(abs(cos(angle) / a), n2)
        let sinComponent = pow(abs(sin(angle) / b), n3)
        let sum = cosComponent + sinComponent
        guard sum > 1e-10 else { return 1.0 }
        return pow(sum, -1.0 / n1)
    }

    // MARK: - RectMorph (D6 Snowflake)

    private struct RectMorphShape {
        var cx: CGFloat
        var cy: CGFloat
        var radii: [CGFloat]
        var rotation: Double
        var colorIdx: Int
        var folds: Int
    }

    struct RectMorphFrame {
        let path: Path
        let color: Color
        let color2: Color?
        let alpha: Double
    }

    private static let rectMorphN = 64
    private static let rectMorphMorphDuration: Double = 16.0
    static let rectMorphTrailLen = 10
    static let rectMorphTrailPeakAlpha: Double = 0.35
    static let rectMorphTrailSpacing: Double = 0.8

    static func rectMorphFrame(
        seed: UInt64,
        time t: Double,
        in rect: CGRect,
        elementColor: Color? = nil,
        elementColor2: Color? = nil
    ) -> RectMorphFrame {
        let folds = mindFolds(seed: seed)
        let dur = rectMorphMorphDuration
        let n = t >= 0 ? Int(t / dur) : 0
        let localT = t >= 0 ? (t - Double(n) * dur) / dur : 0
        let tEase = (1.0 - cos(localT * .pi)) / 2.0

        let oldShape = pickSnowflake(seedForIndex: seed, index: n, folds: folds, in: rect)
        let nextShape = pickSnowflake(seedForIndex: seed, index: n + 1, folds: folds, in: rect)
        let lerped = lerpSnowflake(oldShape, nextShape, t: tEase)

        let color: Color
        let color2: Color?
        if let c1 = elementColor, let c2 = elementColor2 {
            color = c1
            color2 = c2
        } else if let c1 = elementColor {
            color = c1
            color2 = nil
        } else {
            let palette = CanvasColorPalette.paletteHex
            let oldColor = Color(hex: palette[oldShape.colorIdx % palette.count])
            let nextColor = Color(hex: palette[nextShape.colorIdx % palette.count])
            color = Color.lerp(oldColor, nextColor, t: tEase)
            color2 = nil
        }

        return RectMorphFrame(
            path: snowflakePath(lerped),
            color: color,
            color2: color2,
            alpha: 1.0
        )
    }

    static func mindFolds(seed: UInt64) -> Int {
        var rng = SeededRNG(seed: seed ^ 0xF01D)
        let options = [3, 4, 5, 6, 7, 8, 5, 6, 9, 10, 12]
        return options[rng.nextInt(in: 0...(options.count - 1))]
    }

    private static func pickSnowflake(seedForIndex seed: UInt64, index: Int, folds: Int, in rect: CGRect) -> RectMorphShape {
        var rng = SeededRNG(seed: seed ^ UInt64(bitPattern: Int64(index)))

        let dim = min(rect.width, rect.height)
        let margin = dim * 0.04
        let cx = rect.midX + rng.nextCGFloat(in: -margin...margin)
        let cy = rect.midY + rng.nextCGFloat(in: -margin...margin)

        let maxR = max(20, dim / 2 - margin)
        let scale = rng.nextCGFloat(in: maxR * 0.35...maxR * 0.98)
        let halfSector = Double.pi / Double(folds)
        let rotation = rng.nextDouble(in: 0...(2 * .pi / Double(folds)))
        let colorIdx = rng.nextInt(in: 0...(CanvasColorPalette.paletteHex.count - 1))

        let harmCount = 2 + rng.nextInt(in: 0...3)
        var harmonics = [(mult: Int, amp: Double)]()
        harmonics.reserveCapacity(harmCount)
        for i in 0..<harmCount {
            let maxMult = i == 0 ? 2 : (i < 2 ? 4 : 6)
            harmonics.append((
                mult: rng.nextInt(in: 1...maxMult),
                amp: rng.nextDouble(in: 0.06...0.55) * (i < 2 ? 1.0 : 0.5)
            ))
        }

        let hasBranch = rng.nextDouble(in: 0...1) < 0.4
        let branchDepth = hasBranch ? rng.nextDouble(in: 0.15...0.5) : 0
        let branchWidth = hasBranch ? rng.nextDouble(in: 0.15...0.4) : 0

        let hasNotch = rng.nextDouble(in: 0...1) < 0.35
        let notchDepth = hasNotch ? rng.nextDouble(in: 0.1...0.35) : 0
        let notchPos = hasNotch ? rng.nextDouble(in: 0.3...0.7) : 0.5

        var radii = [CGFloat](repeating: 0, count: rectMorphN)
        var maxRad: CGFloat = 0
        for i in 0..<rectMorphN {
            let theta = (Double(i) / Double(rectMorphN)) * 2 * .pi
            let localTheta = theta.truncatingRemainder(dividingBy: 2 * halfSector)
            let folded = localTheta > halfSector ? 2 * halfSector - localTheta : localTheta
            let u = (folded / halfSector) * .pi

            var r: Double = 1
            for h in harmonics {
                r += h.amp * cos(u * Double(h.mult))
            }

            if hasBranch {
                let branchU = folded / halfSector
                let spike = max(0, 1.0 - abs(branchU) / branchWidth)
                r += branchDepth * spike * spike
            }

            if hasNotch {
                let notchU = folded / halfSector
                let proximity = exp(-pow((notchU - notchPos) / 0.12, 2))
                r -= notchDepth * proximity
            }

            if r < 0.12 { r = 0.12 }
            radii[i] = CGFloat(r)
            if CGFloat(r) > maxRad { maxRad = CGFloat(r) }
        }
        let norm = maxRad > 0 ? scale / maxRad : 1
        for i in 0..<rectMorphN { radii[i] *= norm }

        return RectMorphShape(cx: cx, cy: cy, radii: radii, rotation: rotation, colorIdx: colorIdx, folds: folds)
    }

    private static func lerpSnowflake(_ a: RectMorphShape, _ b: RectMorphShape, t: Double) -> RectMorphShape {
        let ct = CGFloat(t)
        var radii = [CGFloat](repeating: 0, count: rectMorphN)
        for i in 0..<rectMorphN {
            radii[i] = a.radii[i] + (b.radii[i] - a.radii[i]) * ct
        }
        var dr = b.rotation - a.rotation
        while dr > .pi { dr -= 2 * .pi }
        while dr < -.pi { dr += 2 * .pi }
        return RectMorphShape(
            cx: a.cx + (b.cx - a.cx) * ct,
            cy: a.cy + (b.cy - a.cy) * ct,
            radii: radii,
            rotation: a.rotation + dr * t,
            colorIdx: b.colorIdx,
            folds: a.folds
        )
    }

    private static func snowflakePath(_ s: RectMorphShape) -> Path {
        var pts = [CGPoint](repeating: .zero, count: rectMorphN)
        for i in 0..<rectMorphN {
            let theta = (Double(i) / Double(rectMorphN)) * 2 * .pi + s.rotation
            pts[i] = CGPoint(
                x: s.cx + cos(theta) * Double(s.radii[i]),
                y: s.cy + sin(theta) * Double(s.radii[i])
            )
        }
        return smoothClosedPath(through: pts)
    }
}
