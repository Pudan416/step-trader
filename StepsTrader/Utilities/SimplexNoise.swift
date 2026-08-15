import Foundation

/// Deterministic 2D simplex noise (Gustavson's formulation).
///
/// Unlike a sum of sines with per-sample random phase, neighbouring samples
/// here are correlated — which is what makes a generated contour or a texture
/// density field read as structured rather than as noise. The permutation
/// table is built from a `SeededRNG` shuffle, so the whole field is
/// reproducible from one `UInt64`.
///
/// The 2D simplex patent (US 6867776) expired in 2022; there are no licensing
/// constraints on this construction.
///
/// Reference: Stefan Gustavson, "Simplex noise demystified" (2005).
struct SimplexNoise2D {

    private let perm: [Int]        // 512 entries; perm[i] == perm[i & 255]
    private let permMod12: [Int]

    /// The twelve 3D gradients of the classic construction, projected to 2D by
    /// dropping z. Several collapse into duplicates — that is the standard
    /// behaviour and keeps the `% 12` indexing intact.
    private static let gradients: [(Double, Double)] = [
        (1, 1), (-1, 1), (1, -1), (-1, -1),
        (1, 0), (-1, 0), (1, 0), (-1, 0),
        (0, 1), (0, -1), (0, 1), (0, -1),
    ]

    private static let f2 = 0.5 * (3.0.squareRoot() - 1.0)
    private static let g2 = (3.0 - 3.0.squareRoot()) / 6.0

    init(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var source = Array(0..<256)
        // Fisher-Yates, same pattern as CanvasColorPalette.seededColorTriple.
        for i in stride(from: 255, through: 1, by: -1) {
            source.swapAt(i, rng.nextInt(in: 0...i))
        }

        var perm = [Int](repeating: 0, count: 512)
        var permMod12 = [Int](repeating: 0, count: 512)
        for i in 0..<512 {
            perm[i] = source[i & 255]
            permMod12[i] = perm[i] % 12
        }
        self.perm = perm
        self.permMod12 = permMod12
    }

    /// Noise value in approximately `[-1, 1]`.
    func value(_ x: Double, _ y: Double) -> Double {
        let skew = (x + y) * Self.f2
        let i = Int(floor(x + skew))
        let j = Int(floor(y + skew))

        let unskew = Double(i + j) * Self.g2
        let x0 = x - (Double(i) - unskew)
        let y0 = y - (Double(j) - unskew)

        let (i1, j1) = x0 > y0 ? (1, 0) : (0, 1)

        let x1 = x0 - Double(i1) + Self.g2
        let y1 = y0 - Double(j1) + Self.g2
        let x2 = x0 - 1.0 + 2.0 * Self.g2
        let y2 = y0 - 1.0 + 2.0 * Self.g2

        let ii = i & 255
        let jj = j & 255
        let g0 = permMod12[ii + perm[jj]]
        let g1 = permMod12[ii + i1 + perm[jj + j1]]
        let g2i = permMod12[ii + 1 + perm[jj + 1]]

        // 70.0 scales the three-corner sum into [-1, 1].
        return 70.0 * (contribution(x0, y0, g0)
            + contribution(x1, y1, g1)
            + contribution(x2, y2, g2i))
    }

    /// Fractal Brownian motion — stacked octaves, normalised back to `[-1, 1]`.
    func fbm(
        _ x: Double,
        _ y: Double,
        octaves: Int = 2,
        persistence: Double = 0.45,
        lacunarity: Double = 2.0
    ) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var normaliser = 0.0

        for _ in 0..<max(1, octaves) {
            total += value(x * frequency, y * frequency) * amplitude
            normaliser += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }
        return total / normaliser
    }

    private func contribution(_ x: Double, _ y: Double, _ gradientIndex: Int) -> Double {
        var falloff = 0.5 - x * x - y * y
        guard falloff > 0 else { return 0 }
        falloff *= falloff
        let g = Self.gradients[gradientIndex]
        return falloff * falloff * (g.0 * x + g.1 * y)
    }
}
