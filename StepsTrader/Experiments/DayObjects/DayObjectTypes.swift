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

    static let empty = DayObjectNormalizedRect(minX: 0, minY: 0, maxX: 0, maxY: 0)

    /// The unobscured canvas area reserved for opt-in Lead audition gestures.
    static let dayObjectsLeadAudition = DayObjectNormalizedRect(
        minX: 0,
        minY: 0,
        maxX: 1,
        maxY: 0.57
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
        area > 0
            && point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }

    func intersects(_ other: DayObjectNormalizedRect) -> Bool {
        minX < other.maxX && maxX > other.minX
            && minY < other.maxY && maxY > other.minY
    }
}

enum DayObjectCanvasCoverage: Equatable {
    case fullCanvas
    case excluding(DayObjectNormalizedRect)

    var exclusionRegion: DayObjectNormalizedRect {
        switch self {
        case .fullCanvas: .empty
        case .excluding(let region): region
        }
    }
}

/// Finite, viewport-normalized coordinates shared by the visual canvas and
/// optional manual audition surface.
struct DayObjectNormalizedPoint: Equatable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct DayObjectSceneInput: Equatable {
    let dayKey: String
    let identity: String
    let eventIDs: [String]
    let motionEnergy: Double
    let visualClarity: Double
    let reduceMotion: Bool
    let canvasCoverage: DayObjectCanvasCoverage
    let uiExclusionRegion: DayObjectNormalizedRect
    let paletteCategories: Set<ModernPaletteCategory>
    let usesEditorialField: Bool
    let editorialBackground: DayObjectEditorialBackground
    let lowSleep: Bool
    let editorialPreview: DayObjectEditorialPreviewSpec?
    let editorialLabConfiguration: DayObjectEditorialLabConfiguration?

    init(
        dayKey: String,
        identity: String,
        eventIDs: [String],
        motionEnergy: Double,
        visualClarity: Double,
        reduceMotion: Bool,
        uiExclusionRegion: DayObjectNormalizedRect = .dayObjectsLabControls,
        canvasCoverage: DayObjectCanvasCoverage? = nil,
        paletteCategories: Set<ModernPaletteCategory> = [],
        usesEditorialField: Bool = false,
        editorialBackground: DayObjectEditorialBackground = .dark,
        lowSleep: Bool = false,
        editorialPreview: DayObjectEditorialPreviewSpec? = nil,
        editorialLabConfiguration: DayObjectEditorialLabConfiguration? = nil
    ) {
        self.dayKey = dayKey
        self.identity = identity
        self.eventIDs = eventIDs
        self.motionEnergy = motionEnergy
        self.visualClarity = visualClarity
        self.reduceMotion = reduceMotion
        let resolvedCoverage = canvasCoverage ?? .excluding(uiExclusionRegion)
        self.canvasCoverage = resolvedCoverage
        self.uiExclusionRegion = resolvedCoverage.exclusionRegion
        self.paletteCategories = paletteCategories
        self.usesEditorialField = usesEditorialField
        self.editorialBackground = editorialBackground
        self.lowSleep = lowSleep
        self.editorialPreview = editorialPreview
        self.editorialLabConfiguration = editorialLabConfiguration
    }
}

#if DEBUG || INTERNAL_BUILD
extension DayObjectSceneInput {
    /// Keeps lab day-to-visual mapping at the renderer's existing input boundary.
    static func labPreview(
        dayKey: String,
        eventIDs: [String],
        stepsProgress: Double,
        sleepProgress: Double,
        reduceMotion: Bool,
        uiExclusionRegion: DayObjectNormalizedRect = .dayObjectsLabControls
    ) -> DayObjectSceneInput {
        let steps = clampedProgress(stepsProgress)
        let sleep = clampedProgress(sleepProgress)
        return DayObjectSceneInput(
            dayKey: dayKey,
            identity: "day-objects-lab",
            eventIDs: eventIDs,
            motionEnergy: 0.25 + 0.75 * steps,
            visualClarity: 0.35 + 0.55 * sleep,
            reduceMotion: reduceMotion,
            uiExclusionRegion: uiExclusionRegion
        )
    }

    private static func clampedProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
#endif

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
    let choreographyConfiguration: DayObjectChoreographyConfiguration
    let choreographySlot: DayObjectChoreographySlot
    let appearance: DayObjectAppearance
    let route: DayObjectRoute
    let depthSchedule: DayObjectDepthSchedule
    let role: DayObjectActorRole
    let shape: DayObjectShape
    let elongation: DayObjectElongation
    let sizeBand: DayObjectSizeBand
    let fill: DayObjectFill
    let trajectory: DayObjectTrajectory
    let spin: DayObjectSpin
    let phaseOffset: Double
    let depthBand: Int
    let zIndex: Double

    var eventID: String { id.eventID }
}

struct DayObjectDigitalImpact: Equatable {
    static let maximumSpentColors = 100
    static let none = DayObjectDigitalImpact(spentColors: 0)

    let spentColors: Int

    init(spentColors: Int) {
        self.spentColors = min(max(spentColors, 0), Self.maximumSpentColors)
    }

    var damage: Double {
        Double(spentColors) / Double(Self.maximumSpentColors)
    }

    var scarStrength: Double { damage }

    var signalCorruption: Double {
        pow(damage, 1.15)
    }

    var ambientMotion: Double {
        pow(damage, 1.35)
    }
}

struct DayObjectGlitchBand: Equatable {
    let centerY: Double
    let halfHeight: Double
    let displacementScale: Double
    let displacementDirection: Double
    let rgbDirection: Double
    let activationThreshold: Double
    let phaseOffset: Double
}

struct DayObjectGlitchLayout: Equatable {
    static let bandCount = 12

    let bands: [DayObjectGlitchBand]

    static func make(seed: UInt64) -> DayObjectGlitchLayout {
        var geometryRNG = SeededRNG.derived(
            from: seed,
            domain: "dayObjectGlitchGeometry"
        )
        var activationRNG = SeededRNG.derived(
            from: seed,
            domain: "dayObjectGlitchActivation"
        )
        var priorities: [(index: Int, value: UInt64)] = []
        priorities.reserveCapacity(bandCount)
        for index in 0..<bandCount {
            priorities.append((index: index, value: activationRNG.next()))
        }
        priorities.sort { lhs, rhs in
            lhs.value == rhs.value
                ? lhs.index < rhs.index
                : lhs.value < rhs.value
        }

        var ranks: [Int: Int] = [:]
        ranks.reserveCapacity(bandCount)
        for (rank, priority) in priorities.enumerated() {
            ranks[priority.index] = rank
        }

        return DayObjectGlitchLayout(
            bands: (0..<bandCount).map { index in
                let slotCenter = (Double(index) + 0.5) / Double(bandCount)
                let rank = ranks[index] ?? index
                return DayObjectGlitchBand(
                    centerY: min(
                        max(slotCenter + geometryRNG.nextDouble(in: -0.025...0.025), 0.01),
                        0.99
                    ),
                    halfHeight: geometryRNG.nextDouble(in: 0.008...0.040),
                    displacementScale: geometryRNG.nextDouble(in: 0.45...1.0),
                    displacementDirection: geometryRNG.nextInt(in: 0...1) == 0 ? -1 : 1,
                    rgbDirection: geometryRNG.nextInt(in: 0...1) == 0 ? -1 : 1,
                    activationThreshold: Double(rank) / Double(bandCount - 1),
                    phaseOffset: geometryRNG.nextDouble(in: 0...(2 * .pi))
                )
            }
        )
    }
}
