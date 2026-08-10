import SwiftUI

/// Mutable render cache for `GenerativeCanvasView`. Stored as a class
/// so mutations inside the Canvas closure don't trigger a SwiftUI diff.
@MainActor
final class RenderCache {
    var sortSignature: Int = .min
    var sortedOrder: [UUID] = []
    var sortedIndexMap: [UUID: Int] = [:]
    var interactions: [UUID: ElementInteraction] = [:]

    struct TrailKey: Hashable { let elementId: UUID; let tickIndex: Int }
    var trailFrames: [TrailKey: (center: CGPoint, frame: ProceduralShapeGenerator.RectMorphFrame)] = [:]
    var trailLastPruneTick: Int = .min

    struct ClusterCacheEntry {
        let blobCenters: [CGPoint]
        let mergedPath: Path
    }
    var clusterCache: [Set<UUID>: ClusterCacheEntry] = [:]

    var mindPositionCache: [UUID: CGPoint] = [:]
    var mindPositionCacheTime: Double = -.greatestFiniteMagnitude
    var mindPositionCacheElementHash: Int = .min

    /// Textures are geometry, not per-frame work. A stipple fill runs a
    /// Poisson sample of up to 90 points; at 20 fps across 15 elements that
    /// would be ~27k samples a second. Generated once per bucket and reused.
    struct TextureCacheKey: Hashable {
        let seed: UInt64
        let spec: TextureSpec
        /// Quantised to 1e-4, same treatment as `TextureSpec`'s Doubles.
        /// `complexity` feeds `organicBlobRadiusFactor`'s amplitude and
        /// ringRadius — it changes the contour's *shape*, not just its scale
        /// — so a stale key here would keep serving rings/hatch/stipple
        /// built against a contour the element no longer has (e.g. mid
        /// interaction, where `noiseBoost` can move it by up to 0.4) for as
        /// long as a bucket lasts. Keyed on the quantised value, not on
        /// `radii` itself — keying on the array would defeat the cache
        /// entirely, since the contour changes every frame.
        let complexityKey: Int
        /// The contour morphs slowly (0.012 noise units per second), so the
        /// texture is generated against a time-quantised contour. One bucket
        /// per `bucketSeconds` — the texture lags the outline by well under a
        /// bucket, which is invisible at this drift rate. This is the
        /// *phased* bucket (see `texturePhase`), not a raw `time` bucket.
        let timeBucket: Int
    }

    /// Seconds per texture bucket. Small enough that a texture never visibly
    /// detaches from its contour, large enough that regeneration is rare.
    static let textureBucketSeconds: Double = 1.5

    static func textureBucket(for time: Double) -> Int {
        Int((time / textureBucketSeconds).rounded(.down))
    }

    /// Per-seed offset folded into the bucket clock. Without this, every
    /// element's front layer uses the same `layerT` offset, so all buckets
    /// flip on the same frame: one frame in every ~1.5s pays for ~15 Poisson
    /// fills back to back (each up to 90 points × 20 candidates, plus an
    /// O(n) clearance scan per candidate) instead of that cost being spread
    /// out. Folding a seed-derived phase into the bucket desynchronises the
    /// flips. Deterministic — derived only from `seed`, never wall-clock or
    /// a counter — so identical replays still land on identical buckets.
    /// Range `[0, textureBucketSeconds)`, i.e. up to a full bucket width, so
    /// any two seeds land at most one bucket apart at any given instant.
    static func texturePhase(for seed: UInt64) -> Double {
        Double(seed % 150) / 100
    }

    var textureCache: [TextureCacheKey: TextureGeometry] = [:]
    /// The highest bucket a prune has run for. Tracked as a running maximum,
    /// not "the last bucket we saw" — because different elements' phases
    /// mean consecutive calls within the same frame can report buckets that
    /// bounce between two adjacent values (an element on the "ahead" side of
    /// its phase vs one on the "behind" side). Comparing against the max
    /// keeps the prune to roughly once per bucket advance regardless of that
    /// jitter, instead of re-running the full-dictionary filter on almost
    /// every call.
    var textureCacheLastPruneBucket: Int = .min

    /// Cached lookup. Generates on miss.
    func textureGeometry(
        seed: UInt64,
        spec: TextureSpec,
        radii: [Double],
        complexity: Double,
        time: Double
    ) -> TextureGeometry {
        let bucket = Self.textureBucket(for: time + Self.texturePhase(for: seed))
        let complexityKey = Int((complexity * 10_000).rounded())
        let key = TextureCacheKey(seed: seed, spec: spec, complexityKey: complexityKey, timeBucket: bucket)
        if let hit = textureCache[key] { return hit }

        // Drop entries from older buckets so the cache cannot grow unbounded
        // over a long-running canvas. Keeping `bucket - 1` alongside `bucket`
        // covers the at-most-one-bucket spread `texturePhase` introduces
        // across elements, so a phase-behind element's still-current entry
        // is never evicted early.
        if bucket > textureCacheLastPruneBucket {
            textureCache = textureCache.filter { $0.key.timeBucket >= bucket - 1 }
            textureCacheLastPruneBucket = bucket
        }

        let geometry = ProceduralTexture.geometry(spec: spec, radii: radii, seed: seed)
        textureCache[key] = geometry
        return geometry
    }
}
