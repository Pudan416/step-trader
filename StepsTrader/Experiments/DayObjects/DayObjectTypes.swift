import Foundation

/// Viewport-normalized rectangle using top-left UI coordinates in `0...1`.
struct DayObjectNormalizedRect: Equatable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    static let dayObjectsLabControls = DayObjectNormalizedRect(
        minX: 0,
        minY: 0.58,
        maxX: 1,
        maxY: 1
    )

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let finiteMinX = minX.isFinite ? minX : 0
        let finiteMinY = minY.isFinite ? minY : 0
        let finiteMaxX = maxX.isFinite ? maxX : 0
        let finiteMaxY = maxY.isFinite ? maxY : 0
        let lowerX = min(finiteMinX, finiteMaxX)
        let lowerY = min(finiteMinY, finiteMaxY)
        let upperX = max(finiteMinX, finiteMaxX)
        let upperY = max(finiteMinY, finiteMaxY)
        self.minX = min(max(lowerX, 0), 1)
        self.minY = min(max(lowerY, 0), 1)
        self.maxX = min(max(upperX, 0), 1)
        self.maxY = min(max(upperY, 0), 1)
    }

    var area: Double {
        max(maxX - minX, 0) * max(maxY - minY, 0)
    }

    func contains(_ point: SIMD2<Double>) -> Bool {
        point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }

    func intersects(_ other: DayObjectNormalizedRect) -> Bool {
        minX < other.maxX && maxX > other.minX
            && minY < other.maxY && maxY > other.minY
    }
}

struct DayObjectSceneInput: Equatable {
    let dayKey: String
    let identity: String
    let eventIDs: [String]
    let motionEnergy: Double
    let visualClarity: Double
    let reduceMotion: Bool
    let uiExclusionRegion: DayObjectNormalizedRect

    init(
        dayKey: String,
        identity: String,
        eventIDs: [String],
        motionEnergy: Double,
        visualClarity: Double,
        reduceMotion: Bool,
        uiExclusionRegion: DayObjectNormalizedRect = .dayObjectsLabControls
    ) {
        self.dayKey = dayKey
        self.identity = identity
        self.eventIDs = eventIDs
        self.motionEnergy = motionEnergy
        self.visualClarity = visualClarity
        self.reduceMotion = reduceMotion
        self.uiExclusionRegion = uiExclusionRegion
    }
}

struct DayObjectActorID: Hashable, Comparable {
    let eventID: String
    let memberIndex: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.eventID != rhs.eventID {
            return lhs.eventID < rhs.eventID
        }
        return lhs.memberIndex < rhs.memberIndex
    }
}

enum DayObjectActorRole: String, CaseIterable, Equatable {
    case focal
    case support
    case bridge
    case satellite
    case accent
}

struct DayObjectActor: Equatable {
    let id: DayObjectActorID
    let seed: UInt64
    let role: DayObjectActorRole
    let shape: DayObjectShape
    let elongation: DayObjectElongation
    let sizeBand: DayObjectSizeBand
    let fill: DayObjectFill
    let trajectory: DayObjectTrajectory
    let spin: DayObjectSpin
    let speedRatio: Double
    let phaseOffset: Double
    let depthBand: Int
    let zIndex: Double

    var eventID: String { id.eventID }
}
