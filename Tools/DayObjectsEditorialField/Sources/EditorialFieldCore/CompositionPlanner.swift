import Foundation

public enum CompositionPlanner {
    public static let candidateCount = 64

    public static func make<EventIDs: Sequence>(
        daySeed: UInt64,
        eventIDs: EventIDs,
        viewport: EditorialViewport
    ) -> CompositionRecipe where EventIDs.Element == String {
        let grammar = EditorialGrammar.select(daySeed: daySeed)
        let requested = Set(eventIDs)
        let canonical = CorpusManifest.canonicalEventIDs
        let canonicalSet = Set(canonical)
        let extras = requested.subtracting(canonicalSet).sorted()
        let admittedIDs = (canonical.filter(requested.contains) + extras).prefix(10)

        // The canonical field is planned once and filtered afterward. This lets the
        // scorer consider neighbours while retained actor values survive removals.
        let canonicalActors = planCanonicalField(daySeed: daySeed, grammar: grammar, viewport: viewport)
        var actorByID = Dictionary(uniqueKeysWithValues: canonicalActors.map { ($0.eventID, $0) })
        for eventID in extras.prefix(10) {
            actorByID[eventID] = planExtra(
                eventID: eventID,
                daySeed: daySeed,
                grammar: grammar,
                viewport: viewport,
                referenceActors: canonicalActors
            )
        }

        let actors = admittedIDs.compactMap { actorByID[$0] }
        return CompositionRecipe(daySeed: daySeed, grammar: grammar, viewport: viewport, actors: actors)
    }

    private static func planCanonicalField(
        daySeed: UInt64,
        grammar: EditorialGrammar,
        viewport: EditorialViewport
    ) -> [ActorCompositionRecipe] {
        var admitted: [Candidate] = []
        for (rank, eventID) in CorpusManifest.canonicalEventIDs.enumerated() {
            let candidates = (0..<candidateCount).map {
                candidate(
                    daySeed: daySeed,
                    eventID: eventID,
                    rank: rank,
                    candidateIndex: $0,
                    grammar: grammar,
                    viewport: viewport
                )
            }
            let selected = candidates.map {
                ($0, score($0, rank: rank, admitted: admitted, grammar: grammar, daySeed: daySeed))
            }.max { $0.1 < $1.1 }!.0
            admitted.append(selected)
        }

        let drawOrderByID = Dictionary(
            uniqueKeysWithValues: admitted.sorted {
                $0.depth == $1.depth ? $0.eventID < $1.eventID : $0.depth < $1.depth
            }.enumerated().map { ($0.element.eventID, $0.offset) }
        )
        return admitted.map { $0.recipe(drawOrder: drawOrderByID[$0.eventID]!) }
    }

    private static func planExtra(
        eventID: String,
        daySeed: UInt64,
        grammar: EditorialGrammar,
        viewport: EditorialViewport,
        referenceActors: [ActorCompositionRecipe]
    ) -> ActorCompositionRecipe {
        let rank = Int(stableHash(eventID) % 10)
        let references = referenceActors.map(Candidate.init)
        let candidates = (0..<candidateCount).map {
            candidate(
                daySeed: daySeed,
                eventID: eventID,
                rank: rank,
                candidateIndex: $0,
                grammar: grammar,
                viewport: viewport
            )
        }
        let selected = candidates.map {
            ($0, score($0, rank: rank, admitted: references, grammar: grammar, daySeed: daySeed))
        }.max { $0.1 < $1.1 }!.0
        return selected.recipe(drawOrder: Int(stableHash(eventID) % 10_000) + 10)
    }

    private static func candidate(
        daySeed: UInt64,
        eventID: String,
        rank: Int,
        candidateIndex: Int,
        grammar: EditorialGrammar,
        viewport: EditorialViewport
    ) -> Candidate {
        var random = SplitMix64(seed: actorSeed(daySeed: daySeed, eventID: eventID, candidateIndex: candidateIndex))
        let diameter = diameter(rank: rank, grammar: grammar, random: &random)
        let depth = depth(rank: rank, grammar: grammar, random: &random)
        let cropAllowance: Double
        if grammar == .croppedForeground && rank == 0 {
            cropAllowance = random.inRange(0.20...0.45)
        } else {
            cropAllowance = diameter >= 0.38 ? random.inRange(0.15...0.45) : random.inRange(0...0.08)
        }
        let position = position(
            rank: rank,
            diameter: diameter,
            cropAllowance: cropAllowance,
            grammar: grammar,
            viewport: viewport,
            daySeed: daySeed,
            random: &random
        )
        let localBlur: Double
        if depth >= 0.68 {
            localBlur = 0.028 + 0.035 * random.unit
        } else if depth >= 0.28 {
            localBlur = 0.002 + 0.010 * random.unit
        } else {
            localBlur = 0.012 + 0.016 * random.unit
        }
        return Candidate(
            eventID: eventID,
            position: position,
            diameter: diameter,
            depth: depth,
            localBlur: localBlur,
            cropAllowance: cropAllowance,
            quality: random.unit
        )
    }

    private static func diameter(
        rank: Int,
        grammar: EditorialGrammar,
        random: inout SplitMix64
    ) -> Double {
        if grammar == .equalScaleStudy {
            return random.inRange(0.22...0.34)
        }
        let ranges: [ClosedRange<Double>] = [
            grammar == .croppedForeground ? 0.54...0.70 : 0.42...0.58,
            0.06...0.12,
            0.19...0.34,
            0.10...0.16,
            0.38...0.52,
            0.25...0.38,
            0.06...0.105,
            0.46...0.68,
            0.16...0.29,
            0.115...0.16,
        ]
        return random.inRange(ranges[rank % ranges.count])
    }

    private static func depth(
        rank: Int,
        grammar: EditorialGrammar,
        random: inout SplitMix64
    ) -> Double {
        if grammar == .equalScaleStudy {
            return random.inRange(0.38...0.62)
        }
        let ranges: [ClosedRange<Double>] = [
            0.74...0.94,
            0.05...0.24,
            0.34...0.62,
            0.10...0.30,
            0.55...0.80,
            0.30...0.60,
            0.04...0.22,
            0.70...0.95,
            0.32...0.64,
            0.08...0.28,
        ]
        return random.inRange(ranges[rank % ranges.count])
    }

    private static func position(
        rank: Int,
        diameter: Double,
        cropAllowance: Double,
        grammar: EditorialGrammar,
        viewport: EditorialViewport,
        daySeed: UInt64,
        random: inout SplitMix64
    ) -> CompositionPoint {
        let radiusX = diameter * 0.5 * viewport.shortSide / viewport.width
        let radiusY = diameter * 0.5 * viewport.shortSide / viewport.height

        if grammar == .croppedForeground && rank == 0 {
            let crop = random.inRange(0.17...cropAllowance)
            let edgeDistanceX = radiusX * (1 - crop)
            let edgeDistanceY = radiusY * (1 - crop)
            let orthogonalMinX = radiusX * (1 - cropAllowance)
            let orthogonalMaxX = 1 - orthogonalMinX
            switch daySeed % 4 {
            case 0:
                return CompositionPoint(x: edgeDistanceX, y: random.inRange(0.16...0.46))
            case 1:
                return CompositionPoint(x: 1 - edgeDistanceX, y: random.inRange(0.54...0.84))
            case 2:
                return CompositionPoint(
                    x: random.inRange(max(0.10, orthogonalMinX)...min(0.42, orthogonalMaxX)),
                    y: edgeDistanceY
                )
            default:
                return CompositionPoint(
                    x: random.inRange(max(0.58, orthogonalMinX)...min(0.90, orthogonalMaxX)),
                    y: 1 - edgeDistanceY
                )
            }
        }

        let x: Double
        let y: Double
        switch grammar {
        case .openField, .depthScatter:
            let third = rank % 3
            y = (Double(third) + random.inRange(0.14...0.86)) / 3
            if rank.isMultiple(of: 2) {
                x = random.inRange(0.06...0.46)
            } else {
                x = random.inRange(0.54...0.94)
            }
        case .layeredOverlap, .transparentPrint:
            let anchorX = 0.34 + 0.30 * unit(from: daySeed &+ 0xA11CE)
            let anchorY = 0.30 + 0.40 * unit(from: daySeed &+ 0xB4A1A)
            let spread = grammar == .layeredOverlap ? 0.50 : 0.42
            x = anchorX + (random.unit - 0.5) * spread + (rank.isMultiple(of: 2) ? -0.08 : 0.08)
            y = anchorY + (random.unit - 0.5) * spread * 1.35 + Double((rank % 3) - 1) * 0.09
        case .croppedForeground:
            if rank == 2 {
                x = random.inRange(0.55...0.86)
                y = random.inRange(0.30...0.70)
            } else {
                x = rank.isMultiple(of: 2) ? random.inRange(0.10...0.48) : random.inRange(0.52...0.90)
                y = (Double(rank % 3) + random.inRange(0.18...0.82)) / 3
            }
        case .equalScaleStudy:
            x = rank.isMultiple(of: 2) ? random.inRange(0.08...0.47) : random.inRange(0.53...0.92)
            y = (Double(rank % 3) + random.inRange(0.12...0.88)) / 3
        }

        let crop = diameter >= 0.38 && rank == 7 ? min(cropAllowance, 0.22) : 0.06
        let minX = radiusX * (1 - crop)
        let maxX = 1 - minX
        let minY = radiusY * (1 - crop)
        let maxY = 1 - minY
        return CompositionPoint(
            x: min(maxX, max(minX, x)),
            y: min(maxY, max(minY, y))
        )
    }

    private static func score(
        _ candidate: Candidate,
        rank: Int,
        admitted: [Candidate],
        grammar: EditorialGrammar,
        daySeed: UInt64
    ) -> Double {
        guard !admitted.isEmpty else {
            return candidate.quality + edgeIntent(candidate, grammar: grammar, rank: rank) * 2
        }

        let distances = admitted.map { distance(candidate, $0) }
        let nearest = distances.min() ?? 1
        let overlaps = admitted.map { overlapProxy(candidate, $0) }
        let averageOverlap = overlaps.reduce(0, +) / Double(overlaps.count)
        let existingThirds = Set(admitted.map { min(2, max(0, Int($0.position.y * 3))) })
        let candidateThird = min(2, max(0, Int(candidate.position.y * 3)))

        let targetX = 0.32 + 0.36 * unit(from: daySeed &+ 0xC0FFEE)
        let targetY = 0.32 + 0.36 * unit(from: daySeed &+ 0xDEC0DE)
        let totalWeight = admitted.reduce(candidate.diameter) { $0 + $1.diameter }
        let centerX = (admitted.reduce(candidate.position.x * candidate.diameter) {
            $0 + $1.position.x * $1.diameter
        }) / totalWeight
        let centerY = (admitted.reduce(candidate.position.y * candidate.diameter) {
            $0 + $1.position.y * $1.diameter
        }) / totalWeight
        let balance = -hypot(centerX - targetX, centerY - targetY)

        var result = candidate.quality * 0.12
        result += existingThirds.contains(candidateThird) ? 0 : 1.35
        result += balance * 1.8
        result -= abs(averageOverlap - grammar.overlapTarget) * 2.2
        result += min(nearest, 0.55) * (grammar == .openField ? 2.0 : 0.65)
        result += admitted.reduce(0) {
            $0 + min(abs($1.depth - candidate.depth), 0.4) * 0.18
                + min(abs($1.diameter - candidate.diameter), 0.35) * 0.12
        }
        result += edgeIntent(candidate, grammar: grammar, rank: rank) * 0.9

        let rowMatches = admitted.filter { abs($0.position.y - candidate.position.y) < 0.032 }.count
        let columnMatches = admitted.filter { abs($0.position.x - candidate.position.x) < 0.032 }.count
        result -= Double(rowMatches) * 0.48
        result -= Double(columnMatches) * 0.34
        result -= Double(rowMatches * columnMatches) * 0.22
        if admitted.count >= 2 {
            let meanDistance = distances.reduce(0, +) / Double(distances.count)
            let equalDistanceMatches = distances.filter { abs($0 - meanDistance) < 0.025 }.count
            result -= Double(equalDistanceMatches) * 0.14

            let minX = min(candidate.position.x, admitted.map(\.position.x).min()!)
            let maxX = max(candidate.position.x, admitted.map(\.position.x).max()!)
            let minY = min(candidate.position.y, admitted.map(\.position.y).min()!)
            let maxY = max(candidate.position.y, admitted.map(\.position.y).max()!)
            let span = max(maxX - minX, maxY - minY)
            if span < 0.38 { result -= (0.38 - span) * 5 }
        }
        if admitted.count >= 3 {
            result -= angularRingRegularity(candidate: candidate, admitted: admitted) * 0.42
        }
        let commonPointCount = admitted.filter {
            distance(candidate, $0) < min(candidate.diameter, $0.diameter) * 0.32
        }.count
        result -= Double(commonPointCount) * 0.55
        return result
    }

    private static func angularRingRegularity(candidate: Candidate, admitted: [Candidate]) -> Double {
        let points = admitted.map(\.position) + [candidate.position]
        let centerX = points.map(\.x).reduce(0, +) / Double(points.count)
        let centerY = points.map(\.y).reduce(0, +) / Double(points.count)
        let radii = points.map { hypot($0.x - centerX, $0.y - centerY) }
        let radiusMean = radii.reduce(0, +) / Double(radii.count)
        guard radiusMean > 0 else { return 1 }
        let radialVariance = radii.map { ($0 - radiusMean) * ($0 - radiusMean) }.reduce(0, +)
            / Double(radii.count)
        let radialRegularity = exp(-sqrt(radialVariance) / radiusMean * 5)

        let angles = points.map { atan2($0.y - centerY, $0.x - centerX) }.sorted()
        let gaps = angles.indices.map { index -> Double in
            let next = index == angles.index(before: angles.endIndex)
                ? angles[0] + 2 * Double.pi
                : angles[index + 1]
            return next - angles[index]
        }
        let gapMean = 2 * Double.pi / Double(gaps.count)
        let gapVariance = gaps.map { ($0 - gapMean) * ($0 - gapMean) }.reduce(0, +)
            / Double(gaps.count)
        let angularRegularity = exp(-sqrt(gapVariance) / gapMean * 4)
        return radialRegularity * angularRegularity
    }

    private static func edgeIntent(_ candidate: Candidate, grammar: EditorialGrammar, rank: Int) -> Double {
        let edgeDistance = min(
            candidate.position.x,
            1 - candidate.position.x,
            candidate.position.y,
            1 - candidate.position.y
        )
        if grammar == .croppedForeground && rank == 0 {
            return max(0, 0.25 - edgeDistance)
        }
        return max(0, 0.10 - edgeDistance) * 0.25
    }

    private static func distance(_ lhs: Candidate, _ rhs: Candidate) -> Double {
        hypot(lhs.position.x - rhs.position.x, lhs.position.y - rhs.position.y)
    }

    private static func overlapProxy(_ lhs: Candidate, _ rhs: Candidate) -> Double {
        let radiusSum = (lhs.diameter + rhs.diameter) * 0.5
        guard radiusSum > 0 else { return 0 }
        return max(0, min(1, (radiusSum - distance(lhs, rhs)) / radiusSum))
    }

    private static func actorSeed(daySeed: UInt64, eventID: String, candidateIndex: Int) -> UInt64 {
        daySeed
            ^ stableHash(eventID)
            ^ (UInt64(candidateIndex) &* 0x9E3779B97F4A7C15)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xCBF29CE484222325) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001B3
        }
    }

    private static func unit(from value: UInt64) -> Double {
        var random = SplitMix64(seed: value)
        return random.unit
    }
}

private struct Candidate {
    let eventID: String
    let position: CompositionPoint
    let diameter: Double
    let depth: Double
    let localBlur: Double
    let cropAllowance: Double
    let quality: Double

    init(
        eventID: String,
        position: CompositionPoint,
        diameter: Double,
        depth: Double,
        localBlur: Double,
        cropAllowance: Double,
        quality: Double
    ) {
        self.eventID = eventID
        self.position = position
        self.diameter = diameter
        self.depth = depth
        self.localBlur = localBlur
        self.cropAllowance = cropAllowance
        self.quality = quality
    }

    init(_ recipe: ActorCompositionRecipe) {
        self.init(
            eventID: recipe.eventID,
            position: recipe.position,
            diameter: recipe.diameter,
            depth: recipe.depth,
            localBlur: recipe.localBlur,
            cropAllowance: recipe.cropAllowance,
            quality: 0
        )
    }

    func recipe(drawOrder: Int) -> ActorCompositionRecipe {
        ActorCompositionRecipe(
            eventID: eventID,
            position: position,
            diameter: diameter,
            depth: depth,
            localBlur: localBlur,
            cropAllowance: cropAllowance,
            drawOrder: drawOrder
        )
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    var unit: Double {
        mutating get {
            Double(next() >> 11) / Double(UInt64(1) << 53)
        }
    }

    mutating func inRange(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
