import SwiftUI

// MARK: - Organic Blob Path Generator

extension ProceduralShapeGenerator {

    static func organicBlobPath(
        seed: UInt64,
        complexity: Double = 0.5,
        symmetry: Int = 1,
        time: Double = 0,
        in rect: CGRect
    ) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        return generateOrganicBlob(
            center: center, radius: radius,
            seed: seed, complexity: complexity,
            symmetry: symmetry, time: time
        )
    }

    private static func generateOrganicBlob(
        center: CGPoint, radius: CGFloat,
        seed: UInt64, complexity: Double,
        symmetry: Int, time: Double
    ) -> Path {
        let sym = max(1, min(symmetry, 12))
        let pointCount = max(12, sym * 8)
        var rng = SeededRNG(seed: seed)
        let noiseFreq = 2.0 + complexity * 4.0
        let noiseAmp = 0.15 + complexity * 0.25

        var points = [CGPoint]()
        points.reserveCapacity(pointCount)

        for i in 0..<pointCount {
            let angle = (Double(i) / Double(pointCount)) * 2 * .pi

            var foldedAngle = angle
            if sym > 1 {
                let sector = (2 * .pi) / Double(sym)
                let local = angle.truncatingRemainder(dividingBy: sector)
                foldedAngle = local > sector / 2 ? sector - local : local
            }

            let noisePhase = rng.nextDouble(in: 0...(2 * .pi))
            let noise = sin(foldedAngle * noiseFreq + time * 0.08 + noisePhase) * noiseAmp
                + sin(foldedAngle * noiseFreq * 2.3 + time * 0.05 + noisePhase * 1.7) * noiseAmp * 0.3

            let r = Double(radius) * (1.0 + noise)
            points.append(CGPoint(
                x: Double(center.x) + cos(angle) * r,
                y: Double(center.y) + sin(angle) * r
            ))
        }

        return smoothClosedPath(through: points)
    }
}
