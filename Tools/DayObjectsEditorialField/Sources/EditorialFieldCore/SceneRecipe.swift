import Foundation

public struct CompositionPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum EditorialViewport: String, Codable, CaseIterable, Sendable {
    case phone
    case calendarTile

    public var width: Double {
        switch self {
        case .phone: 393
        case .calendarTile: 1
        }
    }

    public var height: Double {
        switch self {
        case .phone: 852
        case .calendarTile: 1
        }
    }

    public var shortSide: Double { min(width, height) }
}

public struct ActorCompositionRecipe: Codable, Equatable, Sendable {
    public let eventID: String
    public let position: CompositionPoint
    public let diameter: Double
    public let depth: Double
    public let localBlur: Double
    public let cropAllowance: Double
    public let drawOrder: Int

    public init(
        eventID: String,
        position: CompositionPoint,
        diameter: Double,
        depth: Double,
        localBlur: Double,
        cropAllowance: Double,
        drawOrder: Int
    ) {
        self.eventID = eventID
        self.position = position
        self.diameter = diameter
        self.depth = depth
        self.localBlur = localBlur
        self.cropAllowance = cropAllowance
        self.drawOrder = drawOrder
    }
}

public struct CompositionRecipe: Codable, Equatable, Sendable {
    public let daySeed: UInt64
    public let grammar: EditorialGrammar
    public let viewport: EditorialViewport
    public let actors: [ActorCompositionRecipe]

    public init(
        daySeed: UInt64,
        grammar: EditorialGrammar,
        viewport: EditorialViewport,
        actors: [ActorCompositionRecipe]
    ) {
        self.daySeed = daySeed
        self.grammar = grammar
        self.viewport = viewport
        self.actors = actors
    }

    public func actor(_ eventID: String) -> ActorCompositionRecipe? {
        actors.first { $0.eventID == eventID }
    }

    public var minimumDiameter: Double {
        actors.map(\.diameter).min() ?? 0
    }

    public var maximumDiameter: Double {
        actors.map(\.diameter).max() ?? 0
    }

    /// Maximum penetration through an edge, expressed as a fraction of radius.
    public func cropFraction(of actor: ActorCompositionRecipe) -> Double {
        let radius = actor.diameter * 0.5
        guard radius > 0 else { return 0 }

        let widthInShortSides = viewport.width / viewport.shortSide
        let heightInShortSides = viewport.height / viewport.shortSide
        let centerX = actor.position.x * widthInShortSides
        let centerY = actor.position.y * heightInShortSides
        let penetration = max(
            radius - centerX,
            radius - (widthInShortSides - centerX),
            radius - centerY,
            radius - (heightInShortSides - centerY),
            0
        )
        return min(1, penetration / radius)
    }
}

/// Task 2 establishes the composition-only prefix of the versioned scene recipe.
public typealias SceneRecipe = CompositionRecipe

public struct CompositionGuardrailScores: Codable, Equatable, Sendable {
    public let ring: Double
    public let grid: Double
    public let row: Double
    public let commonFocalPoint: Double
    public let compactCluster: Double

    public static let zero = CompositionGuardrailScores(
        ring: 0,
        grid: 0,
        row: 0,
        commonFocalPoint: 0,
        compactCluster: 0
    )

    public init(
        ring: Double,
        grid: Double,
        row: Double,
        commonFocalPoint: Double,
        compactCluster: Double
    ) {
        self.ring = ring
        self.grid = grid
        self.row = row
        self.commonFocalPoint = commonFocalPoint
        self.compactCluster = compactCluster
    }

    public func componentwiseMaximum(_ other: CompositionGuardrailScores) -> CompositionGuardrailScores {
        CompositionGuardrailScores(
            ring: max(ring, other.ring),
            grid: max(grid, other.grid),
            row: max(row, other.row),
            commonFocalPoint: max(commonFocalPoint, other.commonFocalPoint),
            compactCluster: max(compactCluster, other.compactCluster)
        )
    }
}

public enum CompositionGuardrails {
    public static func evaluate(_ recipe: CompositionRecipe) -> CompositionGuardrailScores {
        let actors = recipe.actors
        guard actors.count >= 4 else { return .zero }

        let points = actors.map(\.position)
        let row = alignedShare(points.map(\.y), tolerance: 0.028)
        let column = alignedShare(points.map(\.x), tolerance: 0.028)
        let grid = row * column

        let center = CompositionPoint(
            x: points.map(\.x).reduce(0, +) / Double(points.count),
            y: points.map(\.y).reduce(0, +) / Double(points.count)
        )
        let radii = points.map { hypot($0.x - center.x, $0.y - center.y) }
        let radialRegularity = regularity(of: radii, multiplier: 5)
        let angles = points.map { atan2($0.y - center.y, $0.x - center.x) }.sorted()
        let gaps = angles.indices.map { index -> Double in
            let next = index == angles.index(before: angles.endIndex)
                ? angles[0] + 2 * Double.pi
                : angles[index + 1]
            return next - angles[index]
        }
        let angularRegularity = regularity(of: gaps, multiplier: 4)
        let ring = radialRegularity * angularRegularity

        let widthInShortSides = recipe.viewport.width / recipe.viewport.shortSide
        let heightInShortSides = recipe.viewport.height / recipe.viewport.shortSide
        var mostAtOnePoint = 0
        for probe in actors {
            let probeX = probe.position.x * widthInShortSides
            let probeY = probe.position.y * heightInShortSides
            let containing = actors.filter { actor in
                let dx = actor.position.x * widthInShortSides - probeX
                let dy = actor.position.y * heightInShortSides - probeY
                return hypot(dx, dy) <= actor.diameter * 0.5
            }.count
            mostAtOnePoint = max(mostAtOnePoint, containing)
        }
        let commonFocalPoint = Double(mostAtOnePoint) / Double(actors.count)

        let spanX = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
        let spanY = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        let compactCluster = max(0, 1 - max(spanX, spanY) / 0.82)

        return CompositionGuardrailScores(
            ring: ring,
            grid: grid,
            row: row,
            commonFocalPoint: commonFocalPoint,
            compactCluster: compactCluster
        )
    }

    private static func alignedShare(_ values: [Double], tolerance: Double) -> Double {
        let largestBand = values.map { anchor in
            values.filter { abs($0 - anchor) <= tolerance }.count
        }.max() ?? 0
        return Double(largestBand) / Double(values.count)
    }

    private static func regularity(of values: [Double], multiplier: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 1 }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return exp(-sqrt(variance) / mean * multiplier)
    }
}
