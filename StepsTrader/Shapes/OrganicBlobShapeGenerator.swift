import SwiftUI

// MARK: - Organic Blob Path Generator

extension ProceduralShapeGenerator {

    /// Contour points per blob. Four layers are stacked per element, so this
    /// times four must stay under the 200-point budget in CanvasLab-Spec §16.
    /// 48 was chosen (not the budget-max) because it also reduces the angular
    /// step between ring samples, which is one of the two knobs that keep
    /// adjacent-radius deltas below the correlation threshold — see the
    /// calibration note on `organicBlobRadiusFactor`.
    static let blobPointCount = 48

    /// How fast the sampling ring travels through the noise field, in noise
    /// units per second. Slow enough that a blob never appears to twitch.
    private static let blobTimeDrift = 0.012

    static func organicBlobPath(
        seed: UInt64,
        complexity: Double = 0.5,
        symmetry: Int = 1,
        time: Double = 0,
        in rect: CGRect
    ) -> Path {
        let factors = organicBlobRadiusFactor(
            seed: seed, complexity: complexity, symmetry: symmetry, time: time
        )
        return closedPath(
            radii: factors,
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: Double(min(rect.width, rect.height)) / 2
        )
    }

    /// A closed contour from normalised radii. Shared with the ring texture,
    /// which draws the same contour at successively smaller radii.
    static func closedPath(radii: [Double], center: CGPoint, radius: Double) -> Path {
        var points = [CGPoint]()
        points.reserveCapacity(radii.count)
        for (i, factor) in radii.enumerated() {
            let angle = (Double(i) / Double(radii.count)) * 2 * .pi
            points.append(CGPoint(
                x: Double(center.x) + cos(angle) * radius * factor,
                y: Double(center.y) + sin(angle) * radius * factor
            ))
        }
        return smoothClosedPath(through: points)
    }

    /// Normalised radius per contour point, where `1.0` is a perfect circle.
    ///
    /// A single simplex field is sampled along a ring in noise space. Because
    /// the ring closes on itself the result is exactly periodic in θ — no seam
    /// — and because neighbouring θ map to neighbouring points in the field,
    /// the contour is smooth by construction. Time translates the ring through
    /// the field, morphing the shape without ever repeating.
    ///
    /// Amplitude is capped so the factor stays well above zero: a strictly
    /// positive radius makes the contour star-shaped, and a star-shaped contour
    /// cannot self-intersect.
    static func organicBlobRadiusFactor(
        seed: UInt64,
        complexity: Double,
        symmetry: Int,
        time: Double
    ) -> [Double] {
        let sym = max(1, min(symmetry, 12))
        let count = max(blobPointCount, sym * 8)
        let clamped = min(max(complexity, 0), 1)

        let noise = SimplexNoise2D(seed: seed)

        // Ring radius sets how many lobes fit around the circumference.
        // Simplex noise is only C1-continuous: near a small fraction of
        // simplex-cell boundaries the gradient can change sharply enough that
        // a coarse ring step lands a real jump between adjacent samples, not
        // just aliasing. `ringRadius` and `persistence` (below) were tuned
        // empirically — swept seeds 0..<500 × complexity 0...1 in 0.1 steps,
        // sym 1 — to hold the worst-case adjacent-radius delta to ~0.19,
        // comfortably under the 0.25 test threshold. Do not change either
        // without re-running that sweep; a "harmless" bump here reopens the
        // discontinuity this task exists to close.
        let ringRadius = 0.6 + clamped * 0.4      // 0.6 … 1.0
        let amplitude = 0.12 + clamped * 0.20     // max 0.32 → factor ∈ [0.68, 1.32]

        let driftX = time * blobTimeDrift
        let driftY = time * blobTimeDrift * 0.7

        var factors = [Double]()
        factors.reserveCapacity(count)

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * 2 * .pi

            var sampleAngle = angle
            if sym > 1 {
                let sector = (2 * .pi) / Double(sym)
                let local = angle.truncatingRemainder(dividingBy: sector)
                sampleAngle = local > sector / 2 ? sector - local : local
            }

            let sx = cos(sampleAngle) * ringRadius + driftX
            let sy = sin(sampleAngle) * ringRadius + driftY
            // Two octaves, not three: a third would sit at 4x the base
            // frequency, past the ring's sampling rate, and would alias.
            // Persistence 0.2 (down from the generic 0.45 default) keeps
            // octave 2's contribution — the one sampled at double frequency,
            // so double the effective step size — small enough that it can't
            // dominate a single adjacent-sample delta; see the calibration
            // note above.
            let n = noise.fbm(sx, sy, octaves: 2, persistence: 0.2, lacunarity: 2.0)

            factors.append(1.0 + n * amplitude)
        }
        return factors
    }
}
