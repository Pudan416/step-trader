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
}
