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
    let actorLightnessShift: Float?

    init(
        background: ModernPalette,
        primaryObjects: ModernPalette,
        secondaryObjects: ModernPalette,
        actorLightnessShift: Float? = nil
    ) {
        self.background = background
        self.primaryObjects = primaryObjects
        self.secondaryObjects = secondaryObjects
        self.actorLightnessShift = actorLightnessShift
    }

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
        let profiles = catalogProfiles
        let backgroundContrastField = DayObjectBackgroundContrastField(
            colors: profiles[background.code]!.colors
        )
        let objectCandidates = boundedObjectCandidates(
            candidates.filter { $0.code != background.code },
            profiles: profiles,
            backgroundContrastField: backgroundContrastField,
            rootSeed: rootSeed
        )
        var bestPair: (
            primary: ModernPalette,
            secondary: ModernPalette,
            evaluation: PairEvaluation
        )?
        for primaryIndex in objectCandidates.indices {
            for secondaryIndex in objectCandidates.indices where secondaryIndex > primaryIndex {
                let primary = objectCandidates[primaryIndex]
                let secondary = objectCandidates[secondaryIndex]
                let readableEvaluation = DayObjectReadablePairEvaluation.make(
                    primaryColors: profiles[primary.code]!.colors,
                    secondaryColors: profiles[secondary.code]!.colors,
                    backgroundField: backgroundContrastField
                )
                let aestheticScore = compatibilityScore(
                    primary: profiles[primary.code]!,
                    secondary: profiles[secondary.code]!,
                    background: profiles[background.code]!,
                    backgroundContrastField: backgroundContrastField,
                    contrastAdjustment: readableEvaluation.adjustment
                ) + stablePairJitter(
                    rootSeed: rootSeed,
                    primaryCode: primary.code,
                    secondaryCode: secondary.code
                )
                let evaluation = PairEvaluation(
                    readable: readableEvaluation,
                    aestheticScore: aestheticScore
                )
                if bestPair == nil
                    || evaluation.isPreferred(over: bestPair!.evaluation)
                    || (evaluation == bestPair!.evaluation
                        && (primary.code, secondary.code)
                            < (bestPair!.primary.code, bestPair!.secondary.code))
                {
                    bestPair = (primary, secondary, evaluation)
                }
            }
        }

        let primary = bestPair?.primary ?? candidates[candidates.count > 1 ? 1 : 0]
        let secondary = bestPair?.secondary ?? candidates[candidates.count > 2 ? 2 : 0]
        return DayObjectPaletteSet(
            background: background,
            primaryObjects: primary,
            secondaryObjects: secondary,
            actorLightnessShift: bestPair.map {
                let adjustment = $0.evaluation.readable.adjustment
                return adjustment.direction.sign * adjustment.amount
            }
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
        profiles: [String: PaletteProfile],
        backgroundContrastField: DayObjectBackgroundContrastField,
        rootSeed: UInt64
    ) -> [ModernPalette] {
        let limit = min(candidates.count, 8)
        guard candidates.count > limit else { return candidates }

        let rawContrasts = Dictionary(uniqueKeysWithValues: candidates.map { palette in
            (
                palette.code,
                profiles[palette.code]!.colors.map {
                    backgroundContrastField.lowPercentileContrast(color: $0)
                }.min() ?? 1
            )
        })

        return Array(candidates.sorted { lhs, rhs in
            let lhsContrast = rawContrasts[lhs.code]!
            let rhsContrast = rawContrasts[rhs.code]!
            let lhsAlreadyVisible = lhsContrast >= DayObjectActorContrastAdjustment.minimumContrast
            let rhsAlreadyVisible = rhsContrast >= DayObjectActorContrastAdjustment.minimumContrast
            if lhsAlreadyVisible != rhsAlreadyVisible {
                return lhsAlreadyVisible
            }
            if abs(lhsContrast - rhsContrast) > 0.000_001 {
                return lhsContrast > rhsContrast
            }
            let lhsJitter = stableCandidateJitter(rootSeed: rootSeed, code: lhs.code)
            let rhsJitter = stableCandidateJitter(rootSeed: rootSeed, code: rhs.code)
            return lhsJitter == rhsJitter ? lhs.code < rhs.code : lhsJitter > rhsJitter
        }.prefix(limit))
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
        background: PaletteProfile,
        backgroundContrastField: DayObjectBackgroundContrastField? = nil,
        contrastAdjustment suppliedAdjustment: DayObjectActorContrastAdjustment? = nil
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
        let contrastAdjustment = suppliedAdjustment ?? DayObjectActorContrastAdjustment.make(
            colors: objectColors,
            backgroundField: backgroundContrastField
                ?? DayObjectBackgroundContrastField(colors: backgroundColors)
        )
        let adjustedColors = objectColors.map(contrastAdjustment.apply)
        let contrastField = backgroundContrastField
            ?? DayObjectBackgroundContrastField(colors: backgroundColors)
        let backgroundContrast = adjustedColors.map { color in
            contrastAdjustment.centralFieldContrast(
                color: color,
                backgroundField: contrastField
            )
        }.reduce(0, +) / Double(max(objectColors.count, 1))
        let centroidDistance = colorCentroidDistance(primaryColors, secondaryColors)
        let nearDuplicatePenalty = centroidDistance < 0.08 ? 2.0 : 0

        return 1.8 * min(hueSpread / 120, 1)
            + 1.3 * min(luminanceRange / 0.55, 1)
            + 1.1 * (1 - min(linkingHueDistance / 60, 1))
            + 1.4 * min(backgroundContrast / 3, 1)
            - 1.4 * Double(contrastAdjustment.amount)
            - nearDuplicatePenalty
    }

    private struct PairEvaluation: Equatable {
        let readable: DayObjectReadablePairEvaluation
        let aestheticScore: Double

        func isPreferred(over other: PairEvaluation) -> Bool {
            if readable.qualifies != other.readable.qualifies {
                return readable.qualifies
            }
            if readable.readableColorCount != other.readable.readableColorCount {
                return readable.readableColorCount > other.readable.readableColorCount
            }
            if readable.distinctColorCount != other.readable.distinctColorCount {
                return readable.distinctColorCount > other.readable.distinctColorCount
            }
            if abs(readable.perceptualDiversity - other.readable.perceptualDiversity) > 0.005 {
                return readable.perceptualDiversity > other.readable.perceptualDiversity
            }
            if abs(readable.adjustment.amount - other.readable.adjustment.amount) > 0.005 {
                return readable.adjustment.amount < other.readable.adjustment.amount
            }
            if abs(readable.adjustment.milkyRisk - other.readable.adjustment.milkyRisk) > 0.01 {
                return readable.adjustment.milkyRisk < other.readable.adjustment.milkyRisk
            }
            if abs(readable.adjustment.achievedContrast
                - other.readable.adjustment.achievedContrast) > 0.001 {
                return readable.adjustment.achievedContrast
                    > other.readable.adjustment.achievedContrast
            }
            return aestheticScore > other.aestheticScore
        }
    }

    private struct PaletteProfile {
        let colors: [DayObjectRGB]

        init(palette: ModernPalette) {
            colors = palette.hexes.map(DayObjectRGB.init(hex:))
        }
    }

    private static let catalogProfiles = Dictionary(
        uniqueKeysWithValues: ModernPaletteCatalog.all.map {
            ($0.code, PaletteProfile(palette: $0))
        }
    )

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

    private static func stableCandidateJitter(rootSeed: UInt64, code: String) -> Double {
        var hash = rootSeed ^ 0x243F_6A88_85A3_08D3
        for byte in code.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        hash ^= hash >> 31
        return Double(hash & 0xFFFF) / Double(0xFFFF)
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
        let rawPrimaryColors = paletteSet.primaryObjects.hexes.map(DayObjectRGB.init(hex:))
        let rawSecondaryColors = paletteSet.secondaryObjects.hexes.map(DayObjectRGB.init(hex:))
        let backgroundColors = paletteSet.background.hexes.map(DayObjectRGB.init(hex:))
        let backgroundField = DayObjectBackgroundContrastField(colors: backgroundColors)
        let readableEvaluation: DayObjectReadablePairEvaluation
        if let shift = paletteSet.actorLightnessShift {
            readableEvaluation = DayObjectReadablePairEvaluation.make(
                primaryColors: rawPrimaryColors,
                secondaryColors: rawSecondaryColors,
                backgroundField: backgroundField,
                fixedShift: shift
            )
        } else {
            readableEvaluation = DayObjectReadablePairEvaluation.make(
                primaryColors: rawPrimaryColors,
                secondaryColors: rawSecondaryColors,
                backgroundField: backgroundField
            )
        }
        let contrastAdjustment = readableEvaluation.adjustment
        let primaryReadableIndices = readableEvaluation.primaryReadableIndices
        let secondaryReadableIndices = readableEvaluation.secondaryReadableIndices
        let readablePrimarySubsets = readableSubsets(
            sourceSubsets,
            readableIndices: primaryReadableIndices,
            fallbackIndex: bestContrastIndex(
                colors: rawPrimaryColors.map(contrastAdjustment.apply),
                backgroundField: backgroundField
            )
        )
        let readableSecondarySubsets = readableSubsets(
            sourceSubsets,
            readableIndices: secondaryReadableIndices,
            fallbackIndex: bestContrastIndex(
                colors: rawSecondaryColors.map(contrastAdjustment.apply),
                backgroundField: backgroundField
            )
        )
        let primarySubsets = shuffledSubsets(
            readablePrimarySubsets, rootSeed: rootSeed, primary: true
        )
        let secondarySubsets = shuffledSubsets(
            readableSecondarySubsets, rootSeed: rootSeed, primary: false
        )
        let primaryColors = rawPrimaryColors.map(contrastAdjustment.apply)
        let secondaryColors = rawSecondaryColors.map(contrastAdjustment.apply)
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

    private static func readableSubsets(
        _ sourceSubsets: [[Int]],
        readableIndices: [Int],
        fallbackIndex: Int
    ) -> [[Int]] {
        let readable = Set(readableIndices)
        var seen = Set<[Int]>()
        let filtered = sourceSubsets.compactMap { subset -> [Int]? in
            let result = subset.filter(readable.contains)
            guard !result.isEmpty, seen.insert(result).inserted else { return nil }
            return result
        }
        if !filtered.isEmpty { return filtered }
        return [[fallbackIndex]]
    }

    private static func bestContrastIndex(
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> Int {
        colors.indices.max {
            backgroundField.lowPercentileContrast(color: colors[$0])
                < backgroundField.lowPercentileContrast(color: colors[$1])
        } ?? 0
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

/// One daily transform keeps both object palettes in the same light universe
/// while separating them from the colors the Metal mesh actually blends.
/// The central 70% luminance interval deliberately ignores the small moving
/// tails around isolated nodes, but protects the broad field where actors
/// spend most of their time.
private struct DayObjectActorContrastAdjustment: Equatable {
    static let minimumContrast = 1.35
    private static let maximumLightnessShift: Float = 0.25

    enum Direction: Equatable {
        case darker
        case lighter

        var sign: Float { self == .lighter ? 1 : -1 }
    }

    let direction: Direction
    let amount: Float
    let achievedContrast: Double
    let meetsMinimum: Bool
    let milkyRisk: Double
    let preservationMargin: Double

    struct DirectionalCandidates {
        let darker: DayObjectActorContrastAdjustment
        let lighter: DayObjectActorContrastAdjustment

        var preferred: DayObjectActorContrastAdjustment {
            DayObjectActorContrastAdjustment.isPreferred(darker, over: lighter)
                ? darker
                : lighter
        }
    }

    static func make(
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectActorContrastAdjustment {
        guard !colors.isEmpty, !backgroundField.samples.isEmpty else {
            return candidate(
                direction: .darker,
                amount: 0,
                colors: colors,
                backgroundField: backgroundField
            )
        }
        let darker = candidateForDirection(
            .darker,
            colors: colors,
            backgroundField: backgroundField
        )
        let lighter = candidateForDirection(
            .lighter,
            colors: colors,
            backgroundField: backgroundField
        )
        return isPreferred(darker, over: lighter) ? darker : lighter
    }

    static func fixed(
        direction: Direction,
        amount: Float,
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectActorContrastAdjustment {
        let boundedAmount = min(max(amount, 0), maximumLightnessShift)
        let draft = DayObjectActorContrastAdjustment(
            direction: direction,
            amount: boundedAmount,
            achievedContrast: 0,
            meetsMinimum: false,
            milkyRisk: 0,
            preservationMargin: 0
        )
        let luminances = colors.map(draft.apply).map {
            relativeLuminance($0.linearRGB)
        }
        let brightShare = Double(luminances.filter { $0 > 0.72 }.count)
            / Double(max(luminances.count, 1))
        let meanLuminance = luminances.reduce(0, +) / Double(max(luminances.count, 1))
        return DayObjectActorContrastAdjustment(
            direction: direction,
            amount: boundedAmount,
            achievedContrast: 0,
            meetsMinimum: false,
            milkyRisk: direction == .lighter
                ? brightShare + max(meanLuminance - 0.60, 0) * 2
                : 0,
            preservationMargin: 0
        )
    }

    static func directionalCandidates(
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DirectionalCandidates {
        DirectionalCandidates(
            darker: candidateForDirection(
                .darker,
                colors: colors,
                backgroundField: backgroundField
            ),
            lighter: candidateForDirection(
                .lighter,
                colors: colors,
                backgroundField: backgroundField
            )
        )
    }

    static func combining(
        colors: [DayObjectRGB],
        primary: DirectionalCandidates,
        secondary: DirectionalCandidates,
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectActorContrastAdjustment {
        let darker = combinedCandidate(
            direction: .darker,
            primary: primary.darker,
            secondary: secondary.darker,
            colors: colors,
            backgroundField: backgroundField
        )
        let lighter = combinedCandidate(
            direction: .lighter,
            primary: primary.lighter,
            secondary: secondary.lighter,
            colors: colors,
            backgroundField: backgroundField
        )
        return isPreferred(darker, over: lighter) ? darker : lighter
    }

    func apply(_ color: DayObjectRGB) -> DayObjectRGB {
        color.shiftingPerceptualLightness(by: direction.sign * amount)
    }

    func centralFieldContrast(
        color: DayObjectRGB,
        backgroundField: DayObjectBackgroundContrastField
    ) -> Double {
        backgroundField.lowPercentileContrast(color: color)
    }

    private static func candidateForDirection(
        _ direction: Direction,
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectActorContrastAdjustment {
        let zero = candidate(
            direction: direction,
            amount: 0,
            colors: colors,
            backgroundField: backgroundField
        )
        if zero.meetsMinimum { return zero }

        let maximum = candidate(
            direction: direction,
            amount: maximumLightnessShift,
            colors: colors,
            backgroundField: backgroundField
        )
        guard maximum.meetsMinimum else {
            // A middle-gray actor can first approach the field before crossing
            // it, so retain the best bounded sample rather than assuming the
            // endpoint is always monotonic.
            return stride(from: Float(0.05), through: maximumLightnessShift, by: 0.05)
                .map {
                    candidate(
                        direction: direction,
                        amount: $0,
                        colors: colors,
                        backgroundField: backgroundField
                    )
                }
                .reduce(zero) { bestEffort, current in
                    isPreferredBestEffort(current, over: bestEffort) ? current : bestEffort
                }
        }

        var lower: Float = 0
        var upper = maximumLightnessShift
        for _ in 0..<12 {
            let midpoint = (lower + upper) * 0.5
            let current = candidate(
                direction: direction,
                amount: midpoint,
                colors: colors,
                backgroundField: backgroundField
            )
            if current.meetsMinimum {
                upper = midpoint
            } else {
                lower = midpoint
            }
        }
        return candidate(
            direction: direction,
            amount: upper,
            colors: colors,
            backgroundField: backgroundField
        )
    }

    private static func combinedCandidate(
        direction: Direction,
        primary: DayObjectActorContrastAdjustment,
        secondary: DayObjectActorContrastAdjustment,
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectActorContrastAdjustment {
        if primary.meetsMinimum, secondary.meetsMinimum {
            return candidate(
                direction: direction,
                amount: max(primary.amount, secondary.amount),
                colors: colors,
                backgroundField: backgroundField
            )
        }
        return stride(from: Float(0), through: maximumLightnessShift, by: 0.05)
            .map {
                candidate(
                    direction: direction,
                    amount: $0,
                    colors: colors,
                    backgroundField: backgroundField
                )
            }
            .reduce(
                candidate(
                    direction: direction,
                    amount: 0,
                    colors: colors,
                    backgroundField: backgroundField
                )
            ) { bestEffort, current in
                isPreferredBestEffort(current, over: bestEffort) ? current : bestEffort
            }
    }

    private static func candidate(
        direction: Direction,
        amount: Float,
        colors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectActorContrastAdjustment {
        let boundedAmount = min(max(amount, 0), maximumLightnessShift)
        let adjusted = colors.map {
            $0.shiftingPerceptualLightness(by: direction.sign * boundedAmount)
        }
        let achieved = adjusted.map {
            backgroundField.lowPercentileContrast(color: $0)
        }.min() ?? 1
        let preservationMargin = zip(colors, adjusted).map { source, output in
            let sourceContrast = backgroundField.lowPercentileContrast(color: source)
            let outputContrast = backgroundField.lowPercentileContrast(color: output)
            return outputContrast - min(minimumContrast, sourceContrast)
        }.min() ?? 0
        let luminances = adjusted.map { relativeLuminance($0.linearRGB) }
        let brightShare = Double(luminances.filter { $0 > 0.72 }.count)
            / Double(max(luminances.count, 1))
        let meanLuminance = luminances.reduce(0, +) / Double(max(luminances.count, 1))
        let milkyRisk = direction == .lighter
            ? brightShare + max(meanLuminance - 0.60, 0) * 2
            : 0
        return DayObjectActorContrastAdjustment(
            direction: direction,
            amount: boundedAmount,
            achievedContrast: achieved,
            meetsMinimum: achieved >= minimumContrast - 0.000_001,
            milkyRisk: milkyRisk,
            preservationMargin: preservationMargin
        )
    }

    private static func isPreferred(
        _ lhs: DayObjectActorContrastAdjustment,
        over rhs: DayObjectActorContrastAdjustment
    ) -> Bool {
        if lhs.meetsMinimum != rhs.meetsMinimum { return lhs.meetsMinimum }
        if lhs.meetsMinimum {
            if abs(lhs.amount - rhs.amount) > 0.005 { return lhs.amount < rhs.amount }
            if abs(lhs.milkyRisk - rhs.milkyRisk) > 0.01 { return lhs.milkyRisk < rhs.milkyRisk }
            if abs(lhs.achievedContrast - rhs.achievedContrast) > 0.001 {
                return lhs.achievedContrast > rhs.achievedContrast
            }
            return lhs.direction == .darker
        }
        if (lhs.preservationMargin >= -0.000_001)
            != (rhs.preservationMargin >= -0.000_001) {
            return lhs.preservationMargin >= -0.000_001
        }
        if abs(lhs.achievedContrast - rhs.achievedContrast) > 0.001 {
            return lhs.achievedContrast > rhs.achievedContrast
        }
        if abs(lhs.milkyRisk - rhs.milkyRisk) > 0.01 { return lhs.milkyRisk < rhs.milkyRisk }
        if abs(lhs.amount - rhs.amount) > 0.005 { return lhs.amount < rhs.amount }
        return lhs.direction == .darker
    }

    private static func isPreferredBestEffort(
        _ lhs: DayObjectActorContrastAdjustment,
        over rhs: DayObjectActorContrastAdjustment
    ) -> Bool {
        if (lhs.preservationMargin >= -0.000_001)
            != (rhs.preservationMargin >= -0.000_001) {
            return lhs.preservationMargin >= -0.000_001
        }
        if abs(lhs.achievedContrast - rhs.achievedContrast) > 0.001 {
            return lhs.achievedContrast > rhs.achievedContrast
        }
        if abs(lhs.milkyRisk - rhs.milkyRisk) > 0.01 { return lhs.milkyRisk < rhs.milkyRisk }
        return lhs.amount < rhs.amount
    }
}

private struct DayObjectReadablePairEvaluation: Equatable {
    let adjustment: DayObjectActorContrastAdjustment
    let primaryReadableIndices: [Int]
    let secondaryReadableIndices: [Int]
    let readableColorCount: Int
    let distinctColorCount: Int
    let perceptualDiversity: Double
    let qualifies: Bool

    static func make(
        primaryColors: [DayObjectRGB],
        secondaryColors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectReadablePairEvaluation {
        let allColors = primaryColors + secondaryColors
        var candidates = [DayObjectReadablePairEvaluation]()
        for direction in [
            DayObjectActorContrastAdjustment.Direction.darker,
            .lighter,
        ] {
            for step in 0...5 {
                if step == 0, direction == .lighter { continue }
                let adjustment = DayObjectActorContrastAdjustment.fixed(
                    direction: direction,
                    amount: Float(step) * 0.05,
                    colors: allColors,
                    backgroundField: backgroundField
                )
                candidates.append(
                    evaluate(
                        adjustment: adjustment,
                        primaryColors: primaryColors,
                        secondaryColors: secondaryColors,
                        backgroundField: backgroundField
                    )
                )
            }
        }
        return candidates.dropFirst().reduce(candidates[0]) { best, current in
            current.isPreferred(over: best) ? current : best
        }
    }

    static func make(
        primaryColors: [DayObjectRGB],
        secondaryColors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField,
        fixedShift: Float
    ) -> DayObjectReadablePairEvaluation {
        let direction: DayObjectActorContrastAdjustment.Direction = fixedShift > 0
            ? .lighter
            : .darker
        let adjustment = DayObjectActorContrastAdjustment.fixed(
            direction: direction,
            amount: min(abs(fixedShift), 0.25),
            colors: primaryColors + secondaryColors,
            backgroundField: backgroundField
        )
        return evaluate(
            adjustment: adjustment,
            primaryColors: primaryColors,
            secondaryColors: secondaryColors,
            backgroundField: backgroundField
        )
    }

    private static func evaluate(
        adjustment: DayObjectActorContrastAdjustment,
        primaryColors: [DayObjectRGB],
        secondaryColors: [DayObjectRGB],
        backgroundField: DayObjectBackgroundContrastField
    ) -> DayObjectReadablePairEvaluation {
        let adjustedPrimary = primaryColors.map(adjustment.apply)
        let adjustedSecondary = secondaryColors.map(adjustment.apply)
        let primaryReadable = adjustedPrimary.indices.filter {
            backgroundField.lowPercentileContrast(color: adjustedPrimary[$0])
                >= DayObjectActorContrastAdjustment.minimumContrast - 0.000_001
                && movesCoherently(
                    source: primaryColors[$0],
                    adjusted: adjustedPrimary[$0],
                    direction: adjustment.direction
                )
        }
        let secondaryReadable = adjustedSecondary.indices.filter {
            backgroundField.lowPercentileContrast(color: adjustedSecondary[$0])
                >= DayObjectActorContrastAdjustment.minimumContrast - 0.000_001
                && movesCoherently(
                    source: secondaryColors[$0],
                    adjusted: adjustedSecondary[$0],
                    direction: adjustment.direction
                )
        }
        let readableColors = primaryReadable.map { adjustedPrimary[$0] }
            + secondaryReadable.map { adjustedSecondary[$0] }
        let distinct = perceptuallyDistinctColors(readableColors)
        let diversity = perceptualDiversity(colors: distinct)
        return DayObjectReadablePairEvaluation(
            adjustment: adjustment,
            primaryReadableIndices: primaryReadable,
            secondaryReadableIndices: secondaryReadable,
            readableColorCount: readableColors.count,
            distinctColorCount: distinct.count,
            perceptualDiversity: diversity,
            qualifies: !primaryReadable.isEmpty
                && !secondaryReadable.isEmpty
                && distinct.count >= 3
        )
    }

    private func isPreferred(over other: DayObjectReadablePairEvaluation) -> Bool {
        if qualifies != other.qualifies { return qualifies }
        if readableColorCount != other.readableColorCount {
            return readableColorCount > other.readableColorCount
        }
        if distinctColorCount != other.distinctColorCount {
            return distinctColorCount > other.distinctColorCount
        }
        if abs(perceptualDiversity - other.perceptualDiversity) > 0.005 {
            return perceptualDiversity > other.perceptualDiversity
        }
        if abs(adjustment.amount - other.adjustment.amount) > 0.005 {
            return adjustment.amount < other.adjustment.amount
        }
        if abs(adjustment.milkyRisk - other.adjustment.milkyRisk) > 0.01 {
            return adjustment.milkyRisk < other.adjustment.milkyRisk
        }
        if abs(adjustment.achievedContrast - other.adjustment.achievedContrast) > 0.001 {
            return adjustment.achievedContrast > other.adjustment.achievedContrast
        }
        return adjustment.direction == .darker
    }

    private static func perceptuallyDistinctColors(
        _ colors: [DayObjectRGB]
    ) -> [DayObjectRGB] {
        var result = [DayObjectRGB]()
        for color in colors where result.allSatisfy({
            simd_distance($0.perceptualOKLab, color.perceptualOKLab) >= 0.055
        }) {
            result.append(color)
        }
        return result
    }

    private static func movesCoherently(
        source: DayObjectRGB,
        adjusted: DayObjectRGB,
        direction: DayObjectActorContrastAdjustment.Direction
    ) -> Bool {
        let delta = relativeLuminance(adjusted.linearRGB)
            - relativeLuminance(source.linearRGB)
        return abs(delta) <= 0.000_001
            || delta * Double(direction.sign) > 0
    }

    private static func perceptualDiversity(colors: [DayObjectRGB]) -> Double {
        guard colors.count > 1 else { return 0 }
        let distances = colors.indices.flatMap { lhs in
            colors.indices.compactMap { rhs -> Float? in
                guard rhs > lhs else { return nil }
                return simd_distance(
                    colors[lhs].perceptualOKLab,
                    colors[rhs].perceptualOKLab
                )
            }
        }
        let chroma = colors.map {
            simd_length(SIMD2($0.perceptualOKLab.y, $0.perceptualOKLab.z))
        }.reduce(0, +) / Float(colors.count)
        return Double((distances.min() ?? 0) + chroma * 0.35)
    }
}

private struct DayObjectBackgroundContrastField {
    let samples: [SIMD3<Float>]
    let lowerLuminance: Double
    let upperLuminance: Double

    init(colors: [DayObjectRGB]) {
        guard !colors.isEmpty else {
            samples = []
            lowerLuminance = 0
            upperLuminance = 1
            return
        }
        let linearColors = colors.map(\.linearRGB)
        var samples = linearColors
        for lhs in linearColors.indices {
            for rhs in linearColors.indices where lhs < rhs {
                for amount: Float in [0.25, 0.5, 0.75] {
                    samples.append(
                        linearColors[lhs]
                            + (linearColors[rhs] - linearColors[lhs]) * amount
                    )
                }
            }
        }
        samples.append(
            linearColors.reduce(into: SIMD3<Float>.zero, +=)
                / Float(linearColors.count)
        )
        self.samples = samples

        let luminances = samples.map { relativeLuminance($0) }.sorted()
        let tail = Int(floor(Double(luminances.count - 1) * 0.15))
        lowerLuminance = luminances[min(tail, luminances.count - 1)]
        upperLuminance = luminances[max(luminances.count - 1 - tail, 0)]
    }

    func lowPercentileContrast(color: DayObjectRGB) -> Double {
        guard !samples.isEmpty else { return 1 }
        let index = Int(floor(Double(samples.count - 1) * 0.15))
        var lowest = Array(repeating: Double.infinity, count: index + 1)
        for sample in samples {
            let value = contrastRatio(color.linearRGB, sample)
            guard value < lowest[index] else { continue }
            var insertion = index
            while insertion > 0, value < lowest[insertion - 1] {
                lowest[insertion] = lowest[insertion - 1]
                insertion -= 1
            }
            lowest[insertion] = value
        }
        return lowest[index]
    }
}
