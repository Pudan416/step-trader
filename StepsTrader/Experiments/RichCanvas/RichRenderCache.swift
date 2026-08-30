import Foundation

struct RichGeometryCacheKey: Hashable {
    let family: RichFigureFamily
    let fill: RichFillKind
    let seed: UInt64
    let detailTier: RichFigureDetailTier
    let timeBucket: Int
}

struct RichCachedGeometry {
    let base: RichFigureGeometry
    let fill: RichFillGeometry
}

struct RichCadenceStats: Equatable {
    let observedFPS: Double
    let slowIntervalCount: Int

    static let zero = RichCadenceStats(observedFPS: 0, slowIntervalCount: 0)

    static func calculate(intervals: [Double], requestedFPS: Int) -> Self {
        let positive = intervals.filter { $0.isFinite && $0 > 0 }
        guard !positive.isEmpty, requestedFPS > 0 else { return .zero }
        let average = positive.reduce(0, +) / Double(positive.count)
        let threshold = 1.5 / Double(requestedFPS)
        return .init(
            observedFPS: 1 / average,
            slowIntervalCount: positive.filter { $0 > threshold }.count
        )
    }
}

@MainActor
final class RichRenderCache {
    private static let geometryLimit = 256
    private static let cadenceIntervalLimit = 60

    private var geometries: [RichGeometryCacheKey: RichCachedGeometry] = [:]
    private var accessTicks: [RichGeometryCacheKey: UInt64] = [:]
    private var accessTick: UInt64 = 0
    private var previousFrameTime: Double?
    private var frameIntervals: [Double] = []
    private var cadence = RichCadenceStats.zero
    private var cadenceRequestedFPS: Int?

    var geometryCount: Int { geometries.count }

    func geometry(
        for key: RichGeometryCacheKey,
        build: () -> RichCachedGeometry
    ) -> RichCachedGeometry {
        accessTick += 1
        if let cached = geometries[key] {
            accessTicks[key] = accessTick
            return cached
        }

        let geometry = build()
        geometries[key] = geometry
        accessTicks[key] = accessTick
        evictGeometryIfNeeded()
        return geometry
    }

    func removeAllGeometry() {
        geometries.removeAll(keepingCapacity: false)
        accessTicks.removeAll(keepingCapacity: false)
    }

    func beginCadenceSession(requestedFPS: Int) {
        previousFrameTime = nil
        frameIntervals.removeAll(keepingCapacity: true)
        cadence = .zero
        cadenceRequestedFPS = requestedFPS
    }

    func recordFrame(time: Double, requestedFPS: Int) {
        if cadenceRequestedFPS != requestedFPS {
            beginCadenceSession(requestedFPS: requestedFPS)
        }
        guard time.isFinite else { return }
        defer { previousFrameTime = time }

        if let previousFrameTime {
            let interval = time - previousFrameTime
            if interval.isFinite, interval > 0 {
                frameIntervals.append(interval)
                if frameIntervals.count > Self.cadenceIntervalLimit {
                    frameIntervals.removeFirst(
                        frameIntervals.count - Self.cadenceIntervalLimit
                    )
                }
            }
        }
        cadence = RichCadenceStats.calculate(
            intervals: frameIntervals,
            requestedFPS: requestedFPS
        )
    }

    func cadenceSnapshot() -> RichCadenceStats {
        cadence
    }

    private func evictGeometryIfNeeded() {
        while geometries.count > Self.geometryLimit,
              let leastRecentlyUsed = accessTicks.min(by: { $0.value < $1.value })?.key {
            geometries.removeValue(forKey: leastRecentlyUsed)
            accessTicks.removeValue(forKey: leastRecentlyUsed)
        }
    }
}
