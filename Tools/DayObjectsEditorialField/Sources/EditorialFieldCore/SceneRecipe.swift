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
        CompositionGeometry.cropFraction(of: actor, viewport: viewport)
    }
}

/// Task 2 establishes the composition-only prefix of the versioned scene recipe.
public typealias SceneRecipe = CompositionRecipe

/// Converts axis-normalized recipe positions into the same short-side units
/// used by diameter, blur geometry, overlap, and crop measurements.
public enum CompositionGeometry {
    public static func shortSidePoint(
        _ position: CompositionPoint,
        viewport: EditorialViewport
    ) -> CompositionPoint {
        CompositionPoint(
            x: position.x * viewport.width / viewport.shortSide,
            y: position.y * viewport.height / viewport.shortSide
        )
    }

    public static func distance(
        from lhs: CompositionPoint,
        to rhs: CompositionPoint,
        viewport: EditorialViewport
    ) -> Double {
        let left = shortSidePoint(lhs, viewport: viewport)
        let right = shortSidePoint(rhs, viewport: viewport)
        return hypot(left.x - right.x, left.y - right.y)
    }

    public static func intersects(
        _ lhs: ActorCompositionRecipe,
        _ rhs: ActorCompositionRecipe,
        viewport: EditorialViewport
    ) -> Bool {
        distance(from: lhs.position, to: rhs.position, viewport: viewport)
            < (lhs.diameter + rhs.diameter) * 0.5
    }

    public static func cropFraction(
        of actor: ActorCompositionRecipe,
        viewport: EditorialViewport
    ) -> Double {
        let radius = actor.diameter * 0.5
        guard radius > 0 else { return 0 }

        let center = shortSidePoint(actor.position, viewport: viewport)
        let width = viewport.width / viewport.shortSide
        let height = viewport.height / viewport.shortSide
        let penetration = max(
            radius - center.x,
            radius - (width - center.x),
            radius - center.y,
            radius - (height - center.y),
            0
        )
        return min(1, penetration / radius)
    }
}

public struct CompositionGuardrailScores: Codable, Equatable, Sendable {
    public let ring: Double
    public let grid: Double
    public let row: Double
    public let commonFocalPoint: Double
    public let compactCluster: Double
    public let equalSpacing: Double
    public let equalScale: Double

    public static let zero = CompositionGuardrailScores(
        ring: 0,
        grid: 0,
        row: 0,
        commonFocalPoint: 0,
        compactCluster: 0,
        equalSpacing: 0,
        equalScale: 0
    )

    public init(
        ring: Double,
        grid: Double,
        row: Double,
        commonFocalPoint: Double,
        compactCluster: Double,
        equalSpacing: Double,
        equalScale: Double
    ) {
        self.ring = ring
        self.grid = grid
        self.row = row
        self.commonFocalPoint = commonFocalPoint
        self.compactCluster = compactCluster
        self.equalSpacing = equalSpacing
        self.equalScale = equalScale
    }

    public func componentwiseMaximum(_ other: CompositionGuardrailScores) -> CompositionGuardrailScores {
        CompositionGuardrailScores(
            ring: max(ring, other.ring),
            grid: max(grid, other.grid),
            row: max(row, other.row),
            commonFocalPoint: max(commonFocalPoint, other.commonFocalPoint),
            compactCluster: max(compactCluster, other.compactCluster),
            equalSpacing: max(equalSpacing, other.equalSpacing),
            equalScale: max(equalScale, other.equalScale)
        )
    }
}

public enum CompositionGuardrails {
    public static func evaluate(_ recipe: CompositionRecipe) -> CompositionGuardrailScores {
        let actors = recipe.actors
        guard actors.count >= 4 else { return .zero }

        let points = actors.map {
            CompositionGeometry.shortSidePoint($0.position, viewport: recipe.viewport)
        }
        let row = alignedPopulationShare(points.map(\.y), tolerance: 0.035)
        let column = alignedPopulationShare(points.map(\.x), tolerance: 0.035)
        let grid = sqrt(row * column)

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

        var mostAtOnePoint = 0
        let probes = points + [center]
        for probe in probes {
            let containing = actors.filter { actor in
                let actorCenter = CompositionGeometry.shortSidePoint(
                    actor.position,
                    viewport: recipe.viewport
                )
                let dx = actorCenter.x - probe.x
                let dy = actorCenter.y - probe.y
                return hypot(dx, dy) <= actor.diameter * 0.5
            }.count
            mostAtOnePoint = max(mostAtOnePoint, containing)
        }
        let commonFocalPoint = Double(mostAtOnePoint) / Double(actors.count)

        let width = recipe.viewport.width / recipe.viewport.shortSide
        let height = recipe.viewport.height / recipe.viewport.shortSide
        let spanX = ((points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)) / width
        let spanY = ((points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)) / height
        let compactCluster = max(0, 1 - max(spanX, spanY))

        let nearestDistances = points.indices.map { index -> Double in
            points.indices.filter { $0 != index }.map {
                hypot(points[index].x - points[$0].x, points[index].y - points[$0].y)
            }.min() ?? 0
        }
        let equalSpacing = regularity(of: nearestDistances, multiplier: 7)
        let equalScale = regularity(of: actors.map(\.diameter), multiplier: 8)

        return CompositionGuardrailScores(
            ring: ring,
            grid: grid,
            row: row,
            commonFocalPoint: commonFocalPoint,
            compactCluster: compactCluster,
            equalSpacing: equalSpacing,
            equalScale: equalScale
        )
    }

    private static func alignedPopulationShare(_ values: [Double], tolerance: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        var alignedCount = 0
        var clusterStart = 0
        for index in 1...sorted.count {
            let endsCluster = index == sorted.count || sorted[index] - sorted[index - 1] > tolerance
            if endsCluster {
                let clusterCount = index - clusterStart
                if clusterCount >= 2 { alignedCount += clusterCount }
                clusterStart = index
            }
        }
        return Double(alignedCount) / Double(values.count)
    }

    private static func regularity(of values: [Double], multiplier: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 1 }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return exp(-sqrt(variance) / mean * multiplier)
    }
}
