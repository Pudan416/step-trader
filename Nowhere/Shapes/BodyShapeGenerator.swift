import SwiftUI

extension ProceduralShapeGenerator {

    private static let noiseTableSize = 32

    private static func buildNoiseTable(rng: inout SeededRNG) -> [Double] {
        var table = [Double]()
        table.reserveCapacity(noiseTableSize)
        for _ in 0..<noiseTableSize {
            table.append(rng.nextDouble(in: -1...1))
        }
        return table
    }

    private static let bodyPointCount = 20
    private static var noiseTableCache: [UInt64: [[Double]]] = [:]
    private static let noiseTableCacheLimit = 24

    private static func cachedNoiseTables(for seed: UInt64) -> [[Double]] {
        if let tables = noiseTableCache[seed] { return tables }
        var rng = SeededRNG(seed: seed)
        var tables = [[Double]]()
        tables.reserveCapacity(bodyPointCount)
        for _ in 0..<bodyPointCount {
            tables.append(buildNoiseTable(rng: &rng))
        }
        if noiseTableCache.count >= noiseTableCacheLimit {
            noiseTableCache.removeAll(keepingCapacity: true)
        }
        noiseTableCache[seed] = tables
        return tables
    }

    private static func sampleNoise(
        table: [Double],
        at angle: Double,
        frequency: Double,
        octaves: Int
    ) -> Double {
        var value = 0.0
        var amp = 1.0
        var freq = frequency
        var totalAmp = 0.0

        for _ in 0..<octaves {
            let t = angle * freq / (2 * .pi)
            let wrapped = t - floor(t)
            let idx = wrapped * Double(noiseTableSize)
            let i0 = Int(idx) % noiseTableSize
            let i1 = (i0 + 1) % noiseTableSize
            let frac = idx - floor(idx)
            let smooth = frac * frac * (3 - 2 * frac)
            value += (table[i0] * (1 - smooth) + table[i1] * smooth) * amp
            totalAmp += amp
            amp *= 0.5
            freq *= 2
        }

        return value / totalAmp
    }

    /// Generates a closed organic blob shape.
    /// `complexity` 0...1 controls how many octaves of noise deform the contour.
    /// `time` animates the noise offset for breathing/morphing.
    static func bodyPath(
        seed: UInt64,
        complexity: Double = 0.0,
        time: Double = 0,
        in rect: CGRect
    ) -> Path {
        let tables = cachedNoiseTables(for: seed)

        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        let octaves = 3
        let baseAmplitude = 0.12 + complexity * 0.18
        let timeOffset = time * 0.05

        var points = [CGPoint]()
        points.reserveCapacity(bodyPointCount)

        for i in 0..<bodyPointCount {
            let angle = (Double(i) / Double(bodyPointCount)) * 2 * .pi
            let noise = sampleNoise(
                table: tables[i],
                at: angle + timeOffset,
                frequency: 3.0,
                octaves: octaves
            )
            let displacement = 1.0 + noise * baseAmplitude
            let x = cx + CGFloat(cos(angle) * displacement) * rx
            let y = cy + CGFloat(sin(angle) * displacement) * ry
            points.append(CGPoint(x: x, y: y))
        }

        return smoothClosedPath(through: points)
    }
}
