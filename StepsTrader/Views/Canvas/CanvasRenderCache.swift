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
        /// The contour morphs slowly (0.012 noise units per second), so the
        /// texture is generated against a time-quantised contour. One bucket
        /// per `bucketSeconds` — the texture lags the outline by well under a
        /// bucket, which is invisible at this drift rate.
        let timeBucket: Int
    }

    /// Seconds per texture bucket. Small enough that a texture never visibly
    /// detaches from its contour, large enough that regeneration is rare.
    static let textureBucketSeconds: Double = 1.5

    static func textureBucket(for time: Double) -> Int {
        Int((time / textureBucketSeconds).rounded(.down))
    }

    var textureCache: [TextureCacheKey: TextureGeometry] = [:]
    var textureCacheLastPruneBucket: Int = .min

    /// Cached lookup. Generates on miss.
    func textureGeometry(
        seed: UInt64,
        spec: TextureSpec,
        radii: [Double],
        time: Double
    ) -> TextureGeometry {
        let bucket = Self.textureBucket(for: time)
        let key = TextureCacheKey(seed: seed, spec: spec, timeBucket: bucket)
        if let hit = textureCache[key] { return hit }

        // Drop entries from older buckets so the cache cannot grow unbounded
        // over a long-running canvas.
        if bucket != textureCacheLastPruneBucket {
            textureCache = textureCache.filter { $0.key.timeBucket >= bucket - 1 }
            textureCacheLastPruneBucket = bucket
        }

        let geometry = ProceduralTexture.geometry(spec: spec, radii: radii, seed: seed)
        textureCache[key] = geometry
        return geometry
    }
}
