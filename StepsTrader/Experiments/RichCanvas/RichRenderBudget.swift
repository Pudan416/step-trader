import Foundation

struct RichRenderBudget: Equatable {
    let contourCount: Int
    let orbitalRingCount: Int
    let filamentCount: Int
    let glowPassCount: Int
    let globalParticleCount: Int
    let requestedFPS: Int
    let trailsEnabled: Bool

    static func resolve(elementCount: Int, lowPowerMode: Bool) -> Self {
        let normal: Self
        switch elementCount {
        case ...5:
            normal = .init(
                contourCount: 10, orbitalRingCount: 8, filamentCount: 32,
                glowPassCount: 2, globalParticleCount: 30,
                requestedFPS: 20, trailsEnabled: false
            )
        case ...10:
            normal = .init(
                contourCount: 8, orbitalRingCount: 8, filamentCount: 24,
                glowPassCount: 2, globalParticleCount: 24,
                requestedFPS: 20, trailsEnabled: false
            )
        default:
            normal = .init(
                contourCount: 6, orbitalRingCount: 6, filamentCount: 16,
                glowPassCount: 1, globalParticleCount: 16,
                requestedFPS: 20, trailsEnabled: false
            )
        }

        guard lowPowerMode else { return normal }
        return .init(
            contourCount: min(normal.contourCount, 5),
            orbitalRingCount: min(normal.orbitalRingCount, 5),
            filamentCount: min(normal.filamentCount, 12),
            glowPassCount: min(normal.glowPassCount, 1),
            globalParticleCount: min(normal.globalParticleCount, 8),
            requestedFPS: 15,
            trailsEnabled: false
        )
    }
}

enum RichTimeBuckets {
    static let bucketSeconds = 1.5

    static func phase(for seed: UInt64) -> Double {
        var rng = SeededRNG.derived(from: seed, domain: "richBucketPhase")
        return rng.nextDouble() * bucketSeconds
    }

    static func bucket(time: Double, seed: UInt64) -> Int {
        Int(floor((time + phase(for: seed)) / bucketSeconds))
    }

    static func geometryBucket(
        family: RichFigureFamily,
        time: Double,
        seed: UInt64
    ) -> Int {
        family == .crystallineStar ? bucket(time: time, seed: seed) : 0
    }
}
