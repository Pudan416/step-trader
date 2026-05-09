import SwiftUI

// MARK: - Procedural Shape Generator

/// Pure-function shape generators for the three canvas element families.
/// Each returns a `Path` drawn within a given rect, seeded deterministically
/// so the same seed always produces the same shape.
enum ProceduralShapeGenerator {

    // MARK: - Value Noise

    /// 1D value noise with smooth interpolation, seeded per-element.
    /// `octaves` controls complexity (1 = smooth, 3 = detailed).
    private static func valueNoise(
        at angle: Double,
        frequency: Double,
        octaves: Int,
        rng: inout SeededRNG
    ) -> Double {
        let tableSize = 32
        var table = [Double]()
        table.reserveCapacity(tableSize)
        for _ in 0..<tableSize {
            table.append(rng.nextDouble(in: -1...1))
        }

        var value = 0.0
        var amp = 1.0
        var freq = frequency
        var totalAmp = 0.0

        for _ in 0..<octaves {
            let t = angle * freq / (2 * .pi)
            let wrapped = t - floor(t)
            let idx = wrapped * Double(tableSize)
            let i0 = Int(idx) % tableSize
            let i1 = (i0 + 1) % tableSize
            let frac = idx - floor(idx)
            let smooth = frac * frac * (3 - 2 * frac)
            value += (table[i0] * (1 - smooth) + table[i1] * smooth) * amp
            totalAmp += amp
            amp *= 0.5
            freq *= 2
        }

        return value / totalAmp
    }

    // MARK: - Body: Organic Blob (noise-deformed ellipse)

    /// Generates a closed organic blob shape.
    /// `complexity` 0...1 controls how many octaves of noise deform the contour.
    /// `time` animates the noise offset for breathing/morphing.
    static func bodyPath(
        seed: UInt64,
        complexity: Double = 0.0,
        time: Double = 0,
        in rect: CGRect
    ) -> Path {
        var rng = SeededRNG(seed: seed)

        let pointCount = 20
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        let octaves = 3
        let baseAmplitude = 0.12 + complexity * 0.18
        let timeOffset = time * 0.05

        var points = [CGPoint]()
        points.reserveCapacity(pointCount)

        for i in 0..<pointCount {
            let angle = (Double(i) / Double(pointCount)) * 2 * .pi
            let noise = valueNoise(
                at: angle + timeOffset,
                frequency: 3.0,
                octaves: octaves,
                rng: &rng
            )
            let displacement = 1.0 + noise * baseAmplitude
            let x = cx + CGFloat(cos(angle) * displacement) * rx
            let y = cy + CGFloat(sin(angle) * displacement) * ry
            points.append(CGPoint(x: x, y: y))
        }

        return smoothClosedPath(through: points)
    }

    // MARK: - Mind: Geometric Crystal (superformula)

    /// Generates a closed symmetric crystal/star shape using the superformula.
    /// r(θ) = (|cos(mθ/4)/a|^n2 + |sin(mθ/4)/b|^n3)^(-1/n1)
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

    // MARK: - Heart: Soft Light Rays

    /// A single soft ray emanating from a shared origin.
    struct HeartRay {
        let path: Path
        let tipPoint: CGPoint
    }

    /// Generates 3–4 soft tapered ray shapes fanning out from `origin` toward
    /// `direction`. Each ray is a filled wedge with curved edges — wide at the
    /// base, tapering to a rounded tip. `time` adds gentle wobble.
    static func heartRays(
        seed: UInt64,
        complexity: Double = 0.0,
        time: Double = 0,
        origin: CGPoint,
        direction: CGPoint,
        reach: CGFloat
    ) -> [HeartRay] {
        var rng = SeededRNG(seed: seed)
        let count = 3 + rng.nextInt(in: 0...1)

        let totalSpread = 0.5 + complexity * 0.3
        let startAngle = atan2(Double(direction.y), Double(direction.x))

        var rays = [HeartRay]()
        rays.reserveCapacity(count)

        for i in 0..<count {
            let t = count == 1 ? 0.5 : Double(i) / Double(count - 1)
            let angle = startAngle + (t - 0.5) * totalSpread
            let jitter = rng.nextDouble(in: -0.06...0.06)
            let rayAngle = angle + jitter

            let lengthFactor = rng.nextCGFloat(in: 0.7...1.0)
            let rayLength = reach * lengthFactor

            let baseHalfWidth = rayLength * rng.nextCGFloat(in: 0.10...0.18)

            let wobblePhase = rng.nextDouble(in: 0...(2 * .pi))
            let wobbleAmount = CGFloat(sin(time * 0.4 + wobblePhase)) * rayLength * 0.015

            let cosA = CGFloat(cos(rayAngle))
            let sinA = CGFloat(sin(rayAngle))
            let normX = -sinA
            let normY = cosA

            let tip = CGPoint(
                x: origin.x + cosA * rayLength + normX * wobbleAmount,
                y: origin.y + sinA * rayLength + normY * wobbleAmount
            )

            let baseL = CGPoint(
                x: origin.x + normX * baseHalfWidth,
                y: origin.y + normY * baseHalfWidth
            )
            let baseR = CGPoint(
                x: origin.x - normX * baseHalfWidth,
                y: origin.y - normY * baseHalfWidth
            )

            let midT: CGFloat = 0.45
            let midWidth = baseHalfWidth * 0.45
            let midPoint = CGPoint(
                x: origin.x + cosA * rayLength * midT + normX * wobbleAmount * midT,
                y: origin.y + sinA * rayLength * midT + normY * wobbleAmount * midT
            )
            let midL = CGPoint(x: midPoint.x + normX * midWidth, y: midPoint.y + normY * midWidth)
            let midR = CGPoint(x: midPoint.x - normX * midWidth, y: midPoint.y - normY * midWidth)

            var path = Path()
            path.move(to: baseL)
            path.addQuadCurve(to: midL, control: CGPoint(
                x: (baseL.x + midL.x) / 2 + normX * baseHalfWidth * 0.15,
                y: (baseL.y + midL.y) / 2 + normY * baseHalfWidth * 0.15
            ))
            path.addQuadCurve(to: tip, control: CGPoint(
                x: (midL.x + tip.x) / 2 + normX * midWidth * 0.2,
                y: (midL.y + tip.y) / 2 + normY * midWidth * 0.2
            ))
            path.addQuadCurve(to: midR, control: CGPoint(
                x: (tip.x + midR.x) / 2 - normX * midWidth * 0.2,
                y: (tip.y + midR.y) / 2 - normY * midWidth * 0.2
            ))
            path.addQuadCurve(to: baseR, control: CGPoint(
                x: (midR.x + baseR.x) / 2 - normX * baseHalfWidth * 0.15,
                y: (midR.y + baseR.y) / 2 - normY * baseHalfWidth * 0.15
            ))
            path.closeSubpath()

            rays.append(HeartRay(path: path, tipPoint: tip))
        }
        return rays
    }

    /// Generates a unique 3–4 color gradient palette for a heart element from its seed.
    /// Colors are analogous/triadic variations of the base hue with shifted saturation and brightness.
    static func heartGradientColors(seed: UInt64, baseHex: String) -> [Color] {
        var rng = SeededRNG(seed: seed &+ 0xBEEF)
        let base = UIColor(Color(hex: baseHex))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let count = 3 + rng.nextInt(in: 0...1)
        var colors = [Color]()
        colors.reserveCapacity(count)

        for i in 0..<count {
            let hueShift = rng.nextCGFloat(in: -0.12...0.12)
            let satShift = rng.nextCGFloat(in: -0.15...0.1)
            let briShift = rng.nextCGFloat(in: -0.1...0.15)

            let newH = (h + hueShift).truncatingRemainder(dividingBy: 1.0)
            let newS = min(1, max(0.15, s + satShift))
            let newB = min(1, max(0.3, b + briShift))

            let opacity = i == 0 ? 0.75 : rng.nextCGFloat(in: 0.45...0.7)
            colors.append(
                Color(hue: Double(newH < 0 ? newH + 1 : newH),
                      saturation: Double(newS),
                      brightness: Double(newB))
                .opacity(Double(opacity))
            )
        }
        return colors
    }

    // MARK: - Helpers

    private static func smoothClosedPath(through points: [CGPoint]) -> Path {
        guard points.count >= 3 else {
            var p = Path()
            if let first = points.first { p.move(to: first) }
            for pt in points.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
            return p
        }

        var path = Path()
        let n = points.count

        let mid0 = CGPoint(
            x: (points[0].x + points[n - 1].x) / 2,
            y: (points[0].y + points[n - 1].y) / 2
        )
        path.move(to: mid0)

        for i in 0..<n {
            let current = points[i]
            let next = points[(i + 1) % n]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }

        path.closeSubpath()
        return path
    }

    private static func interpolateSpine(_ controls: [CGPoint], segments: Int) -> [CGPoint] {
        guard controls.count >= 2 else { return controls }

        var result = [CGPoint]()
        result.reserveCapacity(segments + 1)

        for s in 0...segments {
            let t = CGFloat(s) / CGFloat(segments)
            let point = catmullRomPoint(t: t, controls: controls)
            result.append(point)
        }
        return result
    }

    private static func catmullRomPoint(t: CGFloat, controls: [CGPoint]) -> CGPoint {
        let n = controls.count
        let scaled = t * CGFloat(n - 1)
        let segment = min(Int(scaled), n - 2)
        let localT = scaled - CGFloat(segment)

        let p0 = controls[max(0, segment - 1)]
        let p1 = controls[segment]
        let p2 = controls[min(n - 1, segment + 1)]
        let p3 = controls[min(n - 1, segment + 2)]

        let tt = localT * localT
        let ttt = tt * localT

        let x = 0.5 * ((2 * p1.x) +
                        (-p0.x + p2.x) * localT +
                        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * tt +
                        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * ttt)
        let y = 0.5 * ((2 * p1.y) +
                        (-p0.y + p2.y) * localT +
                        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * tt +
                        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * ttt)

        return CGPoint(x: x, y: y)
    }

    private static func unitVector(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / len, y: dy / len)
    }

    // MARK: - Metaball (merged body blobs)

    struct BlobSource {
        let center: CGPoint
        let radius: CGFloat
    }

    /// Computes a merged metaball contour for multiple blob sources using marching squares.
    /// Returns a path that envelops all nearby blobs, merging them where they overlap.
    static func metaballPath(
        blobs: [BlobSource],
        in rect: CGRect,
        gridResolution: Int = 50,
        threshold: CGFloat = 1.0
    ) -> Path {
        guard !blobs.isEmpty else { return Path() }

        let cols = gridResolution
        let rows = Int(CGFloat(gridResolution) * rect.height / rect.width)
        let cellW = rect.width / CGFloat(cols)
        let cellH = rect.height / CGFloat(rows)

        var field = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: cols + 1), count: rows + 1)
        for row in 0...rows {
            for col in 0...cols {
                let px = rect.minX + CGFloat(col) * cellW
                let py = rect.minY + CGFloat(row) * cellH
                var value: CGFloat = 0
                for blob in blobs {
                    let dx = px - blob.center.x
                    let dy = py - blob.center.y
                    let distSq = dx * dx + dy * dy
                    let rSq = blob.radius * blob.radius
                    value += rSq / max(distSq, 1)
                }
                field[row][col] = value
            }
        }

        return marchingSquaresPath(field: field, cols: cols, rows: rows,
                                    cellW: cellW, cellH: cellH,
                                    originX: rect.minX, originY: rect.minY,
                                    threshold: threshold)
    }

    private static func marchingSquaresPath(
        field: [[CGFloat]], cols: Int, rows: Int,
        cellW: CGFloat, cellH: CGFloat,
        originX: CGFloat, originY: CGFloat,
        threshold: CGFloat
    ) -> Path {
        var segments = [(CGPoint, CGPoint)]()

        for row in 0..<rows {
            for col in 0..<cols {
                let tl = field[row][col]
                let tr = field[row][col + 1]
                let br = field[row + 1][col + 1]
                let bl = field[row + 1][col]

                let x = originX + CGFloat(col) * cellW
                let y = originY + CGFloat(row) * cellH

                let config = (tl >= threshold ? 8 : 0) |
                             (tr >= threshold ? 4 : 0) |
                             (br >= threshold ? 2 : 0) |
                             (bl >= threshold ? 1 : 0)

                guard config != 0 && config != 15 else { continue }

                func lerpX(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
                    let t = (threshold - a) / (b - a)
                    return x + t * cellW
                }
                func lerpY(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
                    let t = (threshold - a) / (b - a)
                    return y + t * cellH
                }

                let top    = CGPoint(x: lerpX(tl, tr), y: y)
                let right  = CGPoint(x: x + cellW, y: lerpY(tr, br))
                let bottom = CGPoint(x: lerpX(bl, br), y: y + cellH)
                let left   = CGPoint(x: x, y: lerpY(tl, bl))

                switch config {
                case 1:  segments.append((left, bottom))
                case 2:  segments.append((bottom, right))
                case 3:  segments.append((left, right))
                case 4:  segments.append((top, right))
                case 5:  segments.append((top, left)); segments.append((bottom, right))
                case 6:  segments.append((top, bottom))
                case 7:  segments.append((top, left))
                case 8:  segments.append((top, left))
                case 9:  segments.append((top, bottom))
                case 10: segments.append((top, right)); segments.append((left, bottom))
                case 11: segments.append((top, right))
                case 12: segments.append((left, right))
                case 13: segments.append((bottom, right))
                case 14: segments.append((left, bottom))
                default: break
                }
            }
        }

        return connectSegmentsIntoPath(segments)
    }

    private static func connectSegmentsIntoPath(_ segments: [(CGPoint, CGPoint)]) -> Path {
        guard !segments.isEmpty else { return Path() }

        var remaining = segments
        var path = Path()
        let epsilon: CGFloat = 2.0

        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            var chain = [first.0, first.1]

            var changed = true
            while changed {
                changed = false
                for i in (0..<remaining.count).reversed() {
                    let seg = remaining[i]
                    if distance(chain.last!, seg.0) < epsilon {
                        chain.append(seg.1)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.last!, seg.1) < epsilon {
                        chain.append(seg.0)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.first!, seg.1) < epsilon {
                        chain.insert(seg.0, at: 0)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.first!, seg.0) < epsilon {
                        chain.insert(seg.1, at: 0)
                        remaining.remove(at: i)
                        changed = true
                    }
                }
            }

            if chain.count >= 3 {
                path.addPath(smoothClosedPath(through: chain))
            }
        }

        return path
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
