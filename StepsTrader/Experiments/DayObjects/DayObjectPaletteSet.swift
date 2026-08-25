import Foundation
import simd

enum DayObjectObjectPaletteSlot: UInt32, Equatable {
    case primary
    case secondary
}

struct DayObjectPaletteSet: Equatable {
    let background: ModernPalette
    let primaryObjects: ModernPalette
    let secondaryObjects: ModernPalette

    static func make(
        rootSeed: UInt64,
        categories: Set<ModernPaletteCategory>
    ) -> DayObjectPaletteSet {
        let normalizedCategories = categories.isEmpty
            ? ModernPaletteSelection.all
            : categories
        var candidates = ModernPaletteCatalog.palettes(matching: normalizedCategories)
        if candidates.count < 3 {
            for palette in ModernPaletteCatalog.all where
                !candidates.contains(where: { $0.code == palette.code })
            {
                candidates.append(palette)
                if candidates.count == 3 { break }
            }
        }

        precondition(!candidates.isEmpty, "Modern palette catalog must not be empty")
        var backgroundRNG = SeededRNG.derived(
            from: rootSeed,
            domain: "backgroundPalette"
        )
        let background = candidates[
            backgroundRNG.nextInt(in: 0...(candidates.count - 1))
        ]
        let objectCandidates = boundedObjectCandidates(
            candidates.filter { $0.code != background.code },
            rootSeed: rootSeed
        )
        let profiles = Dictionary(
            uniqueKeysWithValues: ([background] + objectCandidates).map {
                ($0.code, PaletteProfile(palette: $0))
            }
        )

        var bestPair: (primary: ModernPalette, secondary: ModernPalette, score: Double)?
        for primary in objectCandidates {
            for secondary in objectCandidates where secondary.code != primary.code {
                let score = compatibilityScore(
                    primary: profiles[primary.code]!,
                    secondary: profiles[secondary.code]!,
                    background: profiles[background.code]!
                ) + stablePairJitter(
                    rootSeed: rootSeed,
                    primaryCode: primary.code,
                    secondaryCode: secondary.code
                )
                if bestPair == nil
                    || score > bestPair!.score
                    || (score == bestPair!.score
                        && (primary.code, secondary.code)
                            < (bestPair!.primary.code, bestPair!.secondary.code))
                {
                    bestPair = (primary, secondary, score)
                }
            }
        }

        let primary = bestPair?.primary ?? candidates[candidates.count > 1 ? 1 : 0]
        let secondary = bestPair?.secondary ?? candidates[candidates.count > 2 ? 2 : 0]
        return DayObjectPaletteSet(
            background: background,
            primaryObjects: primary,
            secondaryObjects: secondary
        )
    }

    private static func boundedObjectCandidates(
        _ candidates: [ModernPalette],
        rootSeed: UInt64
    ) -> [ModernPalette] {
        let limit = min(candidates.count, 24)
        guard candidates.count > limit else { return candidates }

        var pool = candidates
        var rng = SeededRNG.derived(
            from: rootSeed,
            domain: "objectPaletteCandidates"
        )
        for index in 0..<limit {
            let selected = rng.nextInt(in: index...(pool.count - 1))
            pool.swapAt(index, selected)
        }
        return Array(pool.prefix(limit))
    }

    private static func compatibilityScore(
        primary: ModernPalette,
        secondary: ModernPalette,
        background: ModernPalette
    ) -> Double {
        compatibilityScore(
            primary: PaletteProfile(palette: primary),
            secondary: PaletteProfile(palette: secondary),
            background: PaletteProfile(palette: background)
        )
    }

    private static func compatibilityScore(
        primary: PaletteProfile,
        secondary: PaletteProfile,
        background: PaletteProfile
    ) -> Double {
        let primaryColors = primary.colors
        let secondaryColors = secondary.colors
        let backgroundColors = background.colors
        let objectColors = primaryColors + secondaryColors
        let objectHues = objectColors.map { hueDegrees($0.sRGB) }
        let linkingHueDistance = primaryColors.flatMap { lhs in
            secondaryColors.map { rhs in
                circularHueDistance(hueDegrees(lhs.sRGB), hueDegrees(rhs.sRGB))
            }
        }.min() ?? 180
        let hueSpread = objectHues.flatMap { lhs in
            objectHues.map { circularHueDistance(lhs, $0) }
        }.max() ?? 0
        let luminances = objectColors.map { relativeLuminance($0.linearRGB) }
        let luminanceRange = (luminances.max() ?? 0) - (luminances.min() ?? 0)
        let backgroundContrast = objectColors.map { color in
            backgroundColors.map {
                contrastRatio(color.linearRGB, $0.linearRGB)
            }.max() ?? 1
        }.reduce(0, +) / Double(max(objectColors.count, 1))
        let centroidDistance = colorCentroidDistance(primaryColors, secondaryColors)
        let nearDuplicatePenalty = centroidDistance < 0.08 ? 2.0 : 0

        return 1.8 * min(hueSpread / 120, 1)
            + 1.3 * min(luminanceRange / 0.55, 1)
            + 1.1 * (1 - min(linkingHueDistance / 60, 1))
            + 1.4 * min(backgroundContrast / 3, 1)
            - nearDuplicatePenalty
    }

    private struct PaletteProfile {
        let colors: [DayObjectRGB]

        init(palette: ModernPalette) {
            colors = palette.hexes.map(DayObjectRGB.init(hex:))
        }
    }

    private static func colorCentroidDistance(
        _ lhs: [DayObjectRGB],
        _ rhs: [DayObjectRGB]
    ) -> Double {
        func centroid(_ colors: [DayObjectRGB]) -> SIMD3<Double> {
            colors.reduce(into: SIMD3<Double>.zero) { result, color in
                result += SIMD3(
                    Double(color.linearRGB.x),
                    Double(color.linearRGB.y),
                    Double(color.linearRGB.z)
                )
            } / Double(max(colors.count, 1))
        }
        return simd_distance(centroid(lhs), centroid(rhs))
    }

    private static func hueDegrees(_ color: SIMD3<Float>) -> Double {
        let red = Double(color.x)
        let green = Double(color.y)
        let blue = Double(color.z)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard delta > 0.000_001 else { return 0 }
        let sector: Double
        if maximum == red {
            sector = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        return (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func circularHueDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let distance = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(distance, 360 - distance)
    }

    private static func stablePairJitter(
        rootSeed: UInt64,
        primaryCode: String,
        secondaryCode: String
    ) -> Double {
        var hash = rootSeed ^ 0xA409_3822_299F_31D0
        for byte in (primaryCode + secondaryCode).utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        hash ^= hash >> 33
        return Double(hash & 0xFFFF) / Double(0xFFFF) * 0.01
    }
}

struct DayObjectColorAssignment: Equatable {
    let paletteSlot: DayObjectObjectPaletteSlot
    let sourceIndices: [Int]
    let colors: [DayObjectRGB]
}

enum DayObjectColorAllocator {
    private static let palettePattern: [DayObjectObjectPaletteSlot] = [
        .primary, .secondary, .primary, .secondary, .primary,
        .primary, .secondary, .primary, .secondary, .primary,
    ]

    private static let sourceSubsets: [[Int]] = [
        [0], [1], [2], [3],
        [0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3],
        [0, 1, 2], [0, 1, 3], [0, 2, 3], [1, 2, 3],
    ]

    static func assignments(
        eventIDs: [String],
        rootSeed: UInt64,
        paletteSet: DayObjectPaletteSet
    ) -> [String: DayObjectColorAssignment] {
        var seen = Set<String>()
        let uniqueIDs = Array(eventIDs.filter { seen.insert($0).inserted }.prefix(10))
        let primarySubsets = shuffledSubsets(rootSeed: rootSeed, primary: true)
        let secondarySubsets = shuffledSubsets(rootSeed: rootSeed, primary: false)
        let renderedBackground = DayObjectPalette.make(modernPalette: paletteSet.background)
        let brightestBackground = ([renderedBackground.backgroundBase]
            + renderedBackground.backgroundFields).max {
                relativeLuminance($0) < relativeLuminance($1)
            } ?? renderedBackground.backgroundBase
        let primaryColors = paletteSet.primaryObjects.hexes
            .map(DayObjectRGB.init(hex:))
            .map { $0.lightened(toMinimumContrast: 1.35, against: brightestBackground) }
        let secondaryColors = paletteSet.secondaryObjects.hexes
            .map(DayObjectRGB.init(hex:))
            .map { $0.lightened(toMinimumContrast: 1.35, against: brightestBackground) }
        var result = [String: DayObjectColorAssignment]()

        let records = uniqueIDs.map { eventID in
            (eventID: eventID, stable: stableAssignmentIndex(eventID: eventID, rootSeed: rootSeed))
        }
        let targetPrimaryCount = palettePattern.prefix(uniqueIDs.count).filter {
            $0 == .primary
        }.count
        let preferredPrimary = records.filter {
            palettePattern[$0.stable.patternIndex % palettePattern.count] == .primary
        }
        var primaryIDs = Set(preferredPrimary
            .sorted { stablePriority($0.eventID, rootSeed: rootSeed) < stablePriority($1.eventID, rootSeed: rootSeed) }
            .prefix(targetPrimaryCount)
            .map(\.eventID))
        if primaryIDs.count < targetPrimaryCount {
            let promoted = records
                .filter { !primaryIDs.contains($0.eventID) }
                .sorted { stablePriority($0.eventID, rootSeed: rootSeed) < stablePriority($1.eventID, rootSeed: rootSeed) }
                .prefix(targetPrimaryCount - primaryIDs.count)
            primaryIDs.formUnion(promoted.map(\.eventID))
        }

        let primarySubsetByID = uniqueSubsetIndices(
            for: records.filter { primaryIDs.contains($0.eventID) },
            subsetCount: primarySubsets.count,
            rootSeed: rootSeed
        )
        let secondarySubsetByID = uniqueSubsetIndices(
            for: records.filter { !primaryIDs.contains($0.eventID) },
            subsetCount: secondarySubsets.count,
            rootSeed: rootSeed
        )

        for eventID in uniqueIDs {
            let slot: DayObjectObjectPaletteSlot = primaryIDs.contains(eventID)
                ? .primary
                : .secondary
            let subset: [Int]
            let paletteColors: [DayObjectRGB]
            switch slot {
            case .primary:
                subset = primarySubsets[primarySubsetByID[eventID] ?? 0]
                paletteColors = primaryColors
            case .secondary:
                subset = secondarySubsets[secondarySubsetByID[eventID] ?? 0]
                paletteColors = secondaryColors
            }
            result[eventID] = DayObjectColorAssignment(
                paletteSlot: slot,
                sourceIndices: subset,
                colors: subset.map { paletteColors[$0] }
            )
        }
        return result
    }

    private static func uniqueSubsetIndices(
        for records: [(eventID: String, stable: (patternIndex: Int, subsetIndex: Int))],
        subsetCount: Int,
        rootSeed: UInt64
    ) -> [String: Int] {
        guard subsetCount > 0 else { return [:] }
        let preferredCounts = Dictionary(grouping: records) {
            $0.stable.subsetIndex % subsetCount
        }.mapValues(\.count)
        let ordered = records.sorted { lhs, rhs in
            let lhsPreferred = lhs.stable.subsetIndex % subsetCount
            let rhsPreferred = rhs.stable.subsetIndex % subsetCount
            let lhsCount = preferredCounts[lhsPreferred, default: 0]
            let rhsCount = preferredCounts[rhsPreferred, default: 0]
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            return stablePriority(lhs.eventID, rootSeed: rootSeed)
                < stablePriority(rhs.eventID, rootSeed: rootSeed)
        }
        var used = Set<Int>()
        var result = [String: Int]()
        for record in ordered {
            let preferred = record.stable.subsetIndex % subsetCount
            let selected = (0..<subsetCount).lazy
                .map { (preferred + $0) % subsetCount }
                .first { !used.contains($0) } ?? preferred
            used.insert(selected)
            result[record.eventID] = selected
        }
        return result
    }

    private static func stablePriority(_ eventID: String, rootSeed: UInt64) -> UInt64 {
        var hash = rootSeed ^ 0xD6E8_FEB8_6659_FD93
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        hash ^= hash >> 32
        hash &*= 0xD6E8_FEB8_6659_FD93
        return hash ^ (hash >> 32)
    }

    private static func stableAssignmentIndex(
        eventID: String,
        rootSeed: UInt64
    ) -> (patternIndex: Int, subsetIndex: Int) {
        let trailingDigits = eventID.reversed().prefix { $0.isNumber }.reversed()
        if !trailingDigits.isEmpty, let ordinal = Int(String(trailingDigits)) {
            let patternIndex = ordinal % palettePattern.count
            let slot = palettePattern[patternIndex]
            let subsetIndex = palettePattern.prefix(patternIndex).filter { $0 == slot }.count
            return (patternIndex, subsetIndex)
        }

        var hash = rootSeed ^ 0x082E_FA98_EC4E_6C89
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        hash ^= hash >> 29
        return (
            Int(hash % UInt64(palettePattern.count)),
            Int((hash / UInt64(palettePattern.count)) % UInt64(sourceSubsets.count))
        )
    }

    private static func shuffledSubsets(
        rootSeed: UInt64,
        primary: Bool
    ) -> [[Int]] {
        var result = sourceSubsets
        var rng = SeededRNG.derived(
            from: rootSeed,
            domain: primary ? "primaryObjectSubsets" : "secondaryObjectSubsets"
        )
        if result.count > 1 {
            for index in stride(from: result.count - 1, through: 1, by: -1) {
                result.swapAt(index, rng.nextInt(in: 0...index))
            }
        }
        return result
    }
}
