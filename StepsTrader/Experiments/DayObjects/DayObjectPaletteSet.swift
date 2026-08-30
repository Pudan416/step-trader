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
        categories: Set<ModernPaletteCategory>,
        dayKey: String? = nil,
        identity: String = "local"
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
        let background = backgroundPalette(
            rootSeed: rootSeed,
            categories: normalizedCategories,
            dayKey: dayKey,
            identity: identity,
            candidates: candidates
        )
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

    static func backgroundPalette(
        rootSeed: UInt64,
        categories: Set<ModernPaletteCategory>,
        dayKey: String?,
        identity: String
    ) -> ModernPalette {
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
        return backgroundPalette(
            rootSeed: rootSeed,
            categories: normalizedCategories,
            dayKey: dayKey,
            identity: identity,
            candidates: candidates
        )
    }

    private static func backgroundPalette(
        rootSeed: UInt64,
        categories: Set<ModernPaletteCategory>,
        dayKey: String?,
        identity: String,
        candidates: [ModernPalette]
    ) -> ModernPalette {
        if let dayKey,
           let dayOrdinal = calendarDayOrdinal(dayKey),
           candidates.count >= 2 {
            return candidates[calendarBackgroundIndex(
                dayOrdinal: dayOrdinal,
                identity: identity,
                categories: categories,
                candidateCount: candidates.count
            )]
        }
        var backgroundRNG = SeededRNG.derived(
            from: rootSeed,
            domain: "backgroundPalette"
        )
        return candidates[backgroundRNG.nextInt(in: 0...(candidates.count - 1))]
    }

    private static func calendarDayOrdinal(_ dayKey: String) -> Int? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(parts[0]), year > 0,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]) else {
            return nil
        }

        let monthLengths = [
            31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30,
            31, 31, 30, 31, 30, 31,
        ]
        guard (1...monthLengths[month - 1]).contains(day) else { return nil }

        let completedYears = year - 1
        let daysBeforeYear = completedYears * 365
            + completedYears / 4
            - completedYears / 100
            + completedYears / 400
        return daysBeforeYear + monthLengths.prefix(month - 1).reduce(0, +) + day - 1
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 400)
            || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
    }

    private static func calendarBackgroundIndex(
        dayOrdinal: Int,
        identity: String,
        categories: Set<ModernPaletteCategory>,
        candidateCount: Int
    ) -> Int {
        precondition(candidateCount >= 2)
        let hash = stableCalendarContextHash(identity: identity, categories: categories)
        let offset = Int(hash % UInt64(candidateCount))
        var stride = Int((hash >> 32) % UInt64(candidateCount - 1)) + 1
        while greatestCommonDivisor(stride, candidateCount) != 1 {
            stride = stride == candidateCount - 1 ? 1 : stride + 1
        }
        return (offset + (dayOrdinal % candidateCount) * stride) % candidateCount
    }

    private static func stableCalendarContextHash(
        identity: String,
        categories: Set<ModernPaletteCategory>
    ) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func append(_ string: String) {
            for byte in string.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
            }
            hash = (hash ^ 0xFF) &* 0x1000_0000_01B3
        }
        append(identity.isEmpty ? "anonymous" : identity)
        for category in ModernPaletteCategory.allCases where categories.contains(category) {
            append(category.rawValue)
        }
        hash ^= hash >> 33
        hash &*= 0xFF51_AFD7_ED55_8CCD
        hash ^= hash >> 33
        return hash
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
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

    private static let restrainedSubsets: [[Int]] = [
        [0], [1], [2], [3],
        [0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3],
        [0, 1, 2], [0, 1, 3], [0, 2, 3], [1, 2, 3],
    ]

    private static let chromaticSubsets: [[Int]] = [
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
        let sourceSubsets = isChromaticDay(rootSeed: rootSeed)
            ? chromaticSubsets
            : restrainedSubsets
        let primarySubsets = shuffledSubsets(
            sourceSubsets, rootSeed: rootSeed, primary: true
        )
        let secondarySubsets = shuffledSubsets(
            sourceSubsets, rootSeed: rootSeed, primary: false
        )
        let renderedBackground = DayObjectPalette.make(modernPalette: paletteSet.background)
        let brightestBackground = ([renderedBackground.backgroundBase]
            + renderedBackground.backgroundFields).max {
                relativeLuminance($0) < relativeLuminance($1)
            } ?? renderedBackground.backgroundBase
        let primaryColors = paletteSet.primaryObjects.hexes
            .map(DayObjectRGB.init(hex:))
            .map { $0.lightened(toMinimumContrast: 1.55, against: brightestBackground) }
        let secondaryColors = paletteSet.secondaryObjects.hexes
            .map(DayObjectRGB.init(hex:))
            .map { $0.lightened(toMinimumContrast: 1.55, against: brightestBackground) }
        var result = [String: DayObjectColorAssignment]()

        for eventID in uniqueIDs {
            let stable = stableAssignmentIndex(eventID: eventID, rootSeed: rootSeed)
            let slot = palettePattern[stable.patternIndex % palettePattern.count]
            let subset: [Int]
            let paletteColors: [DayObjectRGB]
            switch slot {
            case .primary:
                subset = primarySubsets[stable.subsetIndex % primarySubsets.count]
                paletteColors = primaryColors
            case .secondary:
                subset = secondarySubsets[stable.subsetIndex % secondarySubsets.count]
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
            Int((hash / UInt64(palettePattern.count)) % UInt64(restrainedSubsets.count))
        )
    }

    private static func shuffledSubsets(
        _ sourceSubsets: [[Int]],
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

    private static func isChromaticDay(rootSeed: UInt64) -> Bool {
        rootSeed % 5 != 0
    }
}
