import Foundation

public enum CompositionPlanner {
    public static let candidateCount = 64

    /// Actor recipes are immutable functions of day, identity, and viewport.
    /// Global 3:1 scale and all-thirds guarantees apply to canonical admission
    /// prefixes. They cannot hold for every arbitrary subset without rerolling:
    /// any four-of-ten scale guarantee would require a 27:1 total range, beyond
    /// the schema's 12.5:1 range, and every six-of-ten thirds guarantee would
    /// require at least five actors in each of three thirds.
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
            let admittedPoints = admitted.map {
                CompositionGeometry.shortSidePoint($0.position, viewport: viewport)
            }
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
            let ranked = candidates.map {
                (
                    $0,
                    score(
                        $0,
                        rank: rank,
                        admitted: admitted,
                        grammar: grammar,
                        daySeed: daySeed,
                        viewport: viewport
                    )
                )
            }.sorted { $0.1 > $1.1 }
            let selected = ranked.first {
                !createsCatastrophicSubset(
                    byAdding: $0.0,
                    to: admitted,
                    admittedPoints: admittedPoints,
                    viewport: viewport
                )
            }?.0 ?? ranked[0].0
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
            identityAnchoredCandidate(
                daySeed: daySeed,
                eventID: eventID,
                rank: rank,
                candidateIndex: $0,
                grammar: grammar,
                viewport: viewport
            )
        }
        let selected = candidates.map {
            (
                $0,
                score(
                    $0,
                    rank: rank,
                    admitted: references,
                    grammar: grammar,
                    daySeed: daySeed,
                    viewport: viewport
                )
            )
        }.max { $0.1 < $1.1 }!.0
        return selected.recipe(drawOrder: Int(stableHash(eventID) % 10_000) + 10)
    }

    /// External identities do not inherit a ten-slot geometry role. Their broad
    /// anchor is a full-width, actor-local hash stream; candidate variation stays
    /// near that anchor, so unrelated IDs cannot collapse merely because their
    /// hashes share `mod 10`. No active-set value participates in this function.
    private static func identityAnchoredCandidate(
        daySeed: UInt64,
        eventID: String,
        rank: Int,
        candidateIndex: Int,
        grammar: EditorialGrammar,
        viewport: EditorialViewport
    ) -> Candidate {
        let base = candidate(
            daySeed: daySeed,
            eventID: eventID,
            rank: rank,
            candidateIndex: candidateIndex,
            grammar: grammar,
            viewport: viewport
        )
        let anchorX = 0.08 + 0.84 * actorUnit(
            daySeed: daySeed,
            eventID: eventID,
            salt: 0xA3C5_9AC3_9D71_4E13
        )
        let anchorY = 0.06 + 0.88 * actorUnit(
            daySeed: daySeed,
            eventID: eventID,
            salt: 0xD1B5_4A32_D192_ED03
        )
        let radiusX = base.diameter * 0.5 * viewport.shortSide / viewport.width
        let radiusY = base.diameter * 0.5 * viewport.shortSide / viewport.height
        let crop = base.diameter >= 0.38 ? min(base.cropAllowance, 0.18) : min(base.cropAllowance, 0.06)
        let minX = radiusX * (1 - crop)
        let maxX = 1 - minX
        let minY = radiusY * (1 - crop)
        let maxY = 1 - minY
        let anchorWeight = 0.78
        let position = CompositionPoint(
            x: min(maxX, max(minX, anchorX * anchorWeight + base.position.x * (1 - anchorWeight))),
            y: min(maxY, max(minY, anchorY * anchorWeight + base.position.y * (1 - anchorWeight)))
        )
        return Candidate(
            eventID: base.eventID,
            position: position,
            diameter: base.diameter,
            depth: base.depth,
            localBlur: base.localBlur,
            cropAllowance: base.cropAllowance,
            quality: base.quality
        )
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
        switch rank {
        case 0 where grammar == .croppedForeground:
            cropAllowance = random.inRange(0.24...0.45)
        case 3:
            cropAllowance = random.inRange(0.14...0.24)
        case 4:
            cropAllowance = random.inRange(0.18...0.34)
        case 6:
            cropAllowance = random.inRange(0.14...0.24)
        case 7:
            cropAllowance = random.inRange(0.20...0.40)
        default:
            cropAllowance = diameter >= 0.38 ? random.inRange(0.15...0.32) : random.inRange(0...0.08)
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
            let relatedMediumRanges: [ClosedRange<Double>] = [
                0.35...0.38,
                0.18...0.21,
                0.26...0.33,
                0.21...0.27,
                0.31...0.37,
                0.23...0.30,
                0.19...0.22,
                0.30...0.36,
                0.22...0.29,
                0.25...0.32,
            ]
            return random.inRange(relatedMediumRanges[rank % relatedMediumRanges.count])
        }
        let ranges: [ClosedRange<Double>] = [
            grammar == .croppedForeground ? 0.56...0.73 : 0.44...0.64,
            0.06...0.105,
            0.20...0.32,
            0.105...0.18,
            0.36...0.56,
            0.22...0.40,
            0.06...0.095,
            0.46...0.72,
            0.16...0.31,
            0.11...0.18,
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

        let anchors: [CompositionPoint]
        switch grammar {
        case .layeredOverlap, .transparentPrint:
            // Three loose masses span the portrait; each has an off-axis small
            // accent instead of collapsing around one shared center.
            anchors = [
                .init(x: 0.26, y: 0.40), .init(x: 0.42, y: 0.47),
                .init(x: 0.31, y: 0.25), .init(x: 0.86, y: 0.08),
                .init(x: 0.18, y: 0.70), .init(x: 0.36, y: 0.62),
                .init(x: 0.24, y: 0.95), .init(x: 0.86, y: 0.78),
                .init(x: 0.70, y: 0.69), .init(x: 0.92, y: 0.48),
            ]
        case .openField, .equalScaleStudy:
            anchors = [
                .init(x: 0.18, y: 0.18), .init(x: 0.80, y: 0.84),
                .init(x: 0.66, y: 0.46), .init(x: 0.88, y: 0.07),
                .init(x: 0.16, y: 0.72), .init(x: 0.72, y: 0.61),
                .init(x: 0.25, y: 0.95), .init(x: 0.86, y: 0.34),
                .init(x: 0.34, y: 0.43), .init(x: 0.91, y: 0.73),
            ]
        case .depthScatter, .croppedForeground:
            anchors = [
                .init(x: 0.18, y: 0.18), .init(x: 0.82, y: 0.84),
                .init(x: 0.30, y: 0.27), .init(x: 0.84, y: 0.07),
                .init(x: 0.16, y: 0.72), .init(x: 0.66, y: 0.56),
                .init(x: 0.23, y: 0.95), .init(x: 0.86, y: 0.76),
                .init(x: 0.58, y: 0.39), .init(x: 0.93, y: 0.48),
            ]
        }

        let anchor = anchors[rank % anchors.count]
        let mirrorX = ((daySeed >> 9) & 1) == 1
        let mirrorY = ((daySeed >> 17) & 1) == 1
        let baseX = mirrorX ? 1 - anchor.x : anchor.x
        let baseY = mirrorY ? 1 - anchor.y : anchor.y
        let jitterX: Double
        if rank == 3 || rank == 6 {
            jitterX = 0.70
        } else {
            jitterX = rank == 2 ? 0.12 : 0.20
        }
        let jitterY = rank == 2 ? 0.07 : 0.12
        var x = baseX + (random.unit - 0.5) * jitterX
        var y = baseY + (random.unit - 0.5) * jitterY

        let crop: Double
        switch rank {
        case 0 where grammar == .croppedForeground:
            crop = random.inRange(0.20...cropAllowance)
            if daySeed.isMultiple(of: 2) {
                x = radiusX * (1 - crop)
            } else {
                x = 1 - radiusX * (1 - crop)
            }
        case 3:
            crop = random.inRange(0.12...cropAllowance)
            y = mirrorY ? 1 - radiusY * (1 - crop) : radiusY * (1 - crop)
        case 4:
            crop = random.inRange(0.15...cropAllowance)
            x = mirrorX ? 1 - radiusX * (1 - crop) : radiusX * (1 - crop)
        case 6:
            crop = random.inRange(0.12...cropAllowance)
            y = mirrorY ? radiusY * (1 - crop) : 1 - radiusY * (1 - crop)
        case 7:
            crop = random.inRange(0.18...cropAllowance)
            x = mirrorX ? radiusX * (1 - crop) : 1 - radiusX * (1 - crop)
        default:
            crop = 0.04
        }

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
        daySeed: UInt64,
        viewport: EditorialViewport
    ) -> Double {
        guard !admitted.isEmpty else {
            return candidate.quality
                + edgeIntent(candidate, grammar: grammar, rank: rank, viewport: viewport) * 2
        }

        let candidatePoint = CompositionGeometry.shortSidePoint(candidate.position, viewport: viewport)
        let admittedPoints = admitted.map {
            CompositionGeometry.shortSidePoint($0.position, viewport: viewport)
        }
        let distances = admitted.map { distance(candidate, $0, viewport: viewport) }
        let nearest = distances.min() ?? 1
        let overlaps = admitted.map { overlapProxy(candidate, $0, viewport: viewport) }
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
        if grammar.isDistributed {
            result += existingThirds.contains(candidateThird) ? 0 : 1.35
        } else if grammar == .croppedForeground {
            result += existingThirds.contains(candidateThird) ? 0 : 0.30
        }
        result += balance * 1.8
        result -= abs(averageOverlap - grammar.overlapTarget) * 2.2
        result += min(nearest, 0.55) * (grammar == .openField ? 2.0 : 0.65)
        result += admitted.reduce(0) {
            $0 + min(abs($1.depth - candidate.depth), 0.4) * 0.18
                + min(abs($1.diameter - candidate.diameter), 0.35) * 0.12
        }
        result += edgeIntent(candidate, grammar: grammar, rank: rank, viewport: viewport) * 0.9

        let rowMatches = admittedPoints.filter { abs($0.y - candidatePoint.y) < 0.035 }.count
        let columnMatches = admittedPoints.filter { abs($0.x - candidatePoint.x) < 0.035 }.count
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
            result -= angularRingRegularity(
                candidate: candidate,
                admitted: admitted,
                viewport: viewport
            ) * 0.42
        }
        let commonPointCount = admitted.filter {
            distance(candidate, $0, viewport: viewport)
                < min(candidate.diameter, $0.diameter) * 0.32
        }.count
        result -= Double(commonPointCount) * 0.55
        return result
    }

    private static func angularRingRegularity(
        candidate: Candidate,
        admitted: [Candidate],
        viewport: EditorialViewport
    ) -> Double {
        let points = (admitted.map(\.position) + [candidate.position]).map {
            CompositionGeometry.shortSidePoint($0, viewport: viewport)
        }
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

    /// Every subset is completed exactly once during canonical admission. By
    /// rejecting a candidate when any newly completed four-actor subset crosses
    /// a catastrophic regularity threshold, arbitrary later removals inherit the
    /// protection without changing any retained actor.
    private static func createsCatastrophicSubset(
        byAdding candidate: Candidate,
        to admitted: [Candidate],
        admittedPoints: [CompositionPoint],
        viewport: EditorialViewport
    ) -> Bool {
        guard admitted.count >= 3 else { return false }
        let candidatePoint = CompositionGeometry.shortSidePoint(
            candidate.position,
            viewport: viewport
        )
        for first in 0..<(admitted.count - 2) {
            for second in (first + 1)..<(admitted.count - 1) {
                for third in (second + 1)..<admitted.count {
                    if catastrophicRegularity(
                        admitted[first], at: admittedPoints[first],
                        admitted[second], at: admittedPoints[second],
                        admitted[third], at: admittedPoints[third],
                        candidate, at: candidatePoint
                    ) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func catastrophicRegularity(
        _ first: Candidate,
        at firstPoint: CompositionPoint,
        _ second: Candidate,
        at secondPoint: CompositionPoint,
        _ third: Candidate,
        at thirdPoint: CompositionPoint,
        _ fourth: Candidate,
        at fourthPoint: CompositionPoint
    ) -> Bool {
        // For four actors `row >= .95` means every actor belongs to a
        // multi-actor y cluster. `grid >= .95` implies that same condition, so
        // this exact row predicate covers both catastrophic outcomes.
        let sortedY = [firstPoint.y, secondPoint.y, thirdPoint.y, fourthPoint.y].sorted()
        let firstPair = sortedY[1] - sortedY[0] <= 0.035
        let lastPair = sortedY[3] - sortedY[2] <= 0.035
        if firstPair && lastPair {
            return true
        }

        let center = CompositionPoint(
            x: (firstPoint.x + secondPoint.x + thirdPoint.x + fourthPoint.x) * 0.25,
            y: (firstPoint.y + secondPoint.y + thirdPoint.y + fourthPoint.y) * 0.25
        )
        let actors = [first, second, third, fourth]
        let points = [firstPoint, secondPoint, thirdPoint, fourthPoint]
        for probe in [firstPoint, secondPoint, thirdPoint, fourthPoint, center] {
            var allContain = true
            for index in 0..<4 where allContain {
                allContain = hypot(points[index].x - probe.x, points[index].y - probe.y)
                    <= actors[index].diameter * 0.5
            }
            if allContain { return true }
        }

        let distance01 = hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
        let distance02 = hypot(firstPoint.x - thirdPoint.x, firstPoint.y - thirdPoint.y)
        let distance03 = hypot(firstPoint.x - fourthPoint.x, firstPoint.y - fourthPoint.y)
        let distance12 = hypot(secondPoint.x - thirdPoint.x, secondPoint.y - thirdPoint.y)
        let distance13 = hypot(secondPoint.x - fourthPoint.x, secondPoint.y - fourthPoint.y)
        let distance23 = hypot(thirdPoint.x - fourthPoint.x, thirdPoint.y - fourthPoint.y)
        let nearest0 = min(distance01, distance02, distance03)
        let nearest1 = min(distance01, distance12, distance13)
        let nearest2 = min(distance02, distance12, distance23)
        let nearest3 = min(distance03, distance13, distance23)
        let mean = (nearest0 + nearest1 + nearest2 + nearest3) * 0.25
        guard mean > 0 else { return true }
        let variance = (
            (nearest0 - mean) * (nearest0 - mean)
                + (nearest1 - mean) * (nearest1 - mean)
                + (nearest2 - mean) * (nearest2 - mean)
                + (nearest3 - mean) * (nearest3 - mean)
        ) * 0.25
        return exp(-sqrt(variance) / mean * 7) >= 0.95
    }

    private static func edgeIntent(
        _ candidate: Candidate,
        grammar: EditorialGrammar,
        rank: Int,
        viewport: EditorialViewport
    ) -> Double {
        let point = CompositionGeometry.shortSidePoint(candidate.position, viewport: viewport)
        let width = viewport.width / viewport.shortSide
        let height = viewport.height / viewport.shortSide
        let edgeDistance = min(
            point.x,
            width - point.x,
            point.y,
            height - point.y
        )
        if grammar == .croppedForeground && rank == 0 {
            let radius = candidate.diameter * 0.5
            return radius > 0 ? max(0, radius - edgeDistance) / radius : 0
        }
        return max(0, 0.10 - edgeDistance) * 0.25
    }

    private static func distance(
        _ lhs: Candidate,
        _ rhs: Candidate,
        viewport: EditorialViewport
    ) -> Double {
        CompositionGeometry.distance(from: lhs.position, to: rhs.position, viewport: viewport)
    }

    private static func overlapProxy(
        _ lhs: Candidate,
        _ rhs: Candidate,
        viewport: EditorialViewport
    ) -> Double {
        let radiusSum = (lhs.diameter + rhs.diameter) * 0.5
        guard radiusSum > 0 else { return 0 }
        return max(
            0,
            min(1, (radiusSum - distance(lhs, rhs, viewport: viewport)) / radiusSum)
        )
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

    private static func actorUnit(daySeed: UInt64, eventID: String, salt: UInt64) -> Double {
        unit(from: daySeed ^ stableHash(eventID) ^ salt)
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
