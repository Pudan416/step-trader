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

    /// Textures are geometry, not per-frame work. Rings and hatch geometry are
    /// generated once per bucket and reused across animation frames.
    struct TextureCacheIdentity: Hashable {
        let family: TextureGeometryFamily
        let seed: UInt64
        let spec: TextureSpec
        let profileKey: Int
    }

    struct TextureCacheKey: Hashable {
        let family: TextureGeometryFamily
        let seed: UInt64
        let spec: TextureSpec
        /// Quantised identity for the radial-profile inputs that remain fixed
        /// within one bucket. Keying on the sampled radii themselves would
        /// defeat caching because animated contours change every frame.
        let profileKey: Int
        /// The contour morphs slowly (0.012 noise units per second), so the
        /// texture is generated against a time-quantised contour. One bucket
        /// per `bucketSeconds` — the texture lags the outline by well under a
        /// bucket, which is invisible at this drift rate. This is the
        /// *phased* bucket (see `texturePhase`), not a raw `time` bucket.
        let timeBucket: Int

        var identity: TextureCacheIdentity {
            TextureCacheIdentity(
                family: family,
                seed: seed,
                spec: spec,
                profileKey: profileKey)
        }
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
    /// fills back to back instead of that cost being spread out. Folding a
    /// full-seed-derived phase into the bucket desynchronises the flips.
    /// Deterministic — derived only from `seed`, never wall-clock or a counter
    /// — so identical replays still land on identical buckets.
    /// Range `[0, textureBucketSeconds)`, i.e. up to a full bucket width, so
    /// any two seeds land at most one bucket apart at any given instant.
    static func texturePhase(for seed: UInt64) -> Double {
        var rng = SeededRNG.derived(from: seed, domain: "texturePhase")
        return rng.nextDouble() * textureBucketSeconds
    }

    private static let textureCacheEntryLimit = 256

    var textureCache: [TextureCacheKey: TextureGeometry] = [:]
    private var textureCacheAccessOrder: [TextureCacheKey: UInt64] = [:]
    private var textureCacheAccessTick: UInt64 = 0

    /// Cached lookup. Generates on miss.
    func textureGeometry(
        family: TextureGeometryFamily,
        seed: UInt64,
        spec: TextureSpec,
        profileKey: Int,
        time: Double,
        radiiAtCanonicalTime: (Double) -> [Double]
    ) -> TextureGeometry {
        let phase = Self.texturePhase(for: seed)
        let bucket = Self.textureBucket(for: time + phase)
        let key = TextureCacheKey(
            family: family,
            seed: seed,
            spec: spec,
            profileKey: profileKey,
            timeBucket: bucket)
        if let hit = textureCache[key] {
            recordTextureCacheAccess(for: key)
            return hit
        }

        pruneTextureCache(identity: key.identity, keepingAround: bucket)

        let canonicalTime = (Double(bucket) + 0.5) * Self.textureBucketSeconds - phase
        let geometry = ProceduralTexture.geometry(
            spec: spec,
            radii: radiiAtCanonicalTime(canonicalTime),
            seed: seed)
        textureCache[key] = geometry
        recordTextureCacheAccess(for: key)
        enforceTextureCacheEntryLimit()
        return geometry
    }

    /// Keep the current and previous bucket for one stable request identity.
    /// Other identities may use deliberately offset clocks (OrganicBlob's
    /// four layers span several buckets), so their bucket numbers are not a
    /// valid basis for evicting this identity's still-current geometry.
    private func pruneTextureCache(
        identity: TextureCacheIdentity,
        keepingAround bucket: Int
    ) {
        let retainedBuckets = [bucket, bucket - 1]
        let staleKeys = textureCache.keys.filter {
            $0.identity == identity && !retainedBuckets.contains($0.timeBucket)
        }
        for staleKey in staleKeys {
            removeTextureCacheEntry(for: staleKey)
        }
    }

    /// Identity-local retention bounds time history. This global LRU cap also
    /// bounds changing identities, such as interaction-driven profile keys.
    private func enforceTextureCacheEntryLimit() {
        while textureCache.count > Self.textureCacheEntryLimit {
            guard let leastRecentlyUsed = textureCacheAccessOrder.min(
                by: { $0.value < $1.value })?.key
            else { return }
            removeTextureCacheEntry(for: leastRecentlyUsed)
        }
    }

    private func recordTextureCacheAccess(for key: TextureCacheKey) {
        textureCacheAccessTick &+= 1
        textureCacheAccessOrder[key] = textureCacheAccessTick
    }

    private func removeTextureCacheEntry(for key: TextureCacheKey) {
        textureCache.removeValue(forKey: key)
        textureCacheAccessOrder.removeValue(forKey: key)
    }
}
