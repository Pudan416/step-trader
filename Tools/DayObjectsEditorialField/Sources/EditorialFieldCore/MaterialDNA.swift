import Foundation

public enum MaterialFamily: String, CaseIterable, Codable, Hashable, Sendable {
    case gradient
    case solid
    case sphere
    case glass
    case mist
    case halo
    case luminous
    case outline
    case counterform
}

public enum RadialBlend: String, CaseIterable, Codable, Hashable, Sendable {
    case normal
    case screen
    case softLight
    case multiply
}

public enum MaterialMutation: String, CaseIterable, Codable, Hashable, Sendable {
    case softGradient
    case richSolid
    case luminousSphere
    case frostedGlass
    case diffuseMist
    case expandedHalo
    case intenseLuminous
    case multiOutline
    case wideCounterform

    public func isCompatible(with family: MaterialFamily) -> Bool {
        switch (self, family) {
        case (.softGradient, .gradient),
             (.richSolid, .solid),
             (.luminousSphere, .sphere),
             (.frostedGlass, .glass),
             (.diffuseMist, .mist),
             (.expandedHalo, .halo),
             (.intenseLuminous, .luminous),
             (.multiOutline, .outline),
             (.wideCounterform, .counterform):
            true
        default:
            false
        }
    }
}

public struct MaterialColor: Codable, Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }
}

public struct RadialField: Codable, Equatable, Sendable {
    public let focus: CompositionPoint
    public let radius: Double
    public let softness: Double
    public let opacity: Double
    public let colorIndex: Int
    public let blend: RadialBlend

    public init(
        focus: CompositionPoint,
        radius: Double,
        softness: Double,
        opacity: Double,
        colorIndex: Int,
        blend: RadialBlend
    ) {
        self.focus = focus
        self.radius = radius
        self.softness = softness
        self.opacity = opacity
        self.colorIndex = colorIndex
        self.blend = blend
    }
}

public struct ActorMaterialRecipe: Codable, Equatable, Sendable {
    public let eventID: String
    public let family: MaterialFamily
    public let mutation: MaterialMutation?
    public let colors: [MaterialColor]
    public let fields: [RadialField]
    public let baseOpacity: Double
    public let edgeSoftness: Double
    public let contourWidth: Double
    public let contourCount: Int
    public let counterformRadius: Double?
    public let counterformSoftness: Double

    public init(
        eventID: String,
        family: MaterialFamily,
        mutation: MaterialMutation?,
        colors: [MaterialColor],
        fields: [RadialField],
        baseOpacity: Double,
        edgeSoftness: Double,
        contourWidth: Double,
        contourCount: Int,
        counterformRadius: Double?,
        counterformSoftness: Double
    ) {
        self.eventID = eventID
        self.family = family
        self.mutation = mutation
        self.colors = colors
        self.fields = fields
        self.baseOpacity = baseOpacity
        self.edgeSoftness = edgeSoftness
        self.contourWidth = contourWidth
        self.contourCount = contourCount
        self.counterformRadius = counterformRadius
        self.counterformSoftness = counterformSoftness
    }
}

public struct DailyMaterialDNA: Codable, Equatable, Sendable {
    public let daySeed: UInt64
    public let family: MaterialFamily
    public let accentMutation: MaterialMutation?
    public let requestedColorCount: Int
    public let actors: [ActorMaterialRecipe]

    public init(
        daySeed: UInt64,
        family: MaterialFamily,
        accentMutation: MaterialMutation?,
        requestedColorCount: Int,
        actors: [ActorMaterialRecipe]
    ) {
        self.daySeed = daySeed
        self.family = family
        self.accentMutation = accentMutation
        self.requestedColorCount = requestedColorCount
        self.actors = actors
    }

    public func actor(_ eventID: String) -> ActorMaterialRecipe? {
        actors.first { $0.eventID == eventID }
    }
}

/// Deterministic HTML-derived material semantics. This type deliberately accepts
/// only the day seed and stable identities: composition positions, diameters,
/// depth, draw order, motion, and encoded recipe bytes cannot influence it.
public enum MaterialDNA {
    public static func make<EventIDs: Sequence>(
        daySeed: UInt64,
        eventIDs: EventIDs
    ) -> DailyMaterialDNA where EventIDs.Element == String {
        let family = MaterialFamily.allCases[Int(daySeed % UInt64(MaterialFamily.allCases.count))]
        let count = family == .solid ? 1 : Int(unit(daySeed ^ 0xC01A_5EED) * 3) + 1
        return build(
            daySeed: daySeed,
            eventIDs: Array(eventIDs),
            family: family,
            requestedColorCount: count
        )
    }

    /// Explicit family/count construction is a review-fixture API used by the
    /// complete material atlas. Production daily selection remains `make`.
    public static func fixture<EventIDs: Sequence>(
        daySeed: UInt64,
        eventIDs: EventIDs,
        family: MaterialFamily,
        requestedColorCount: Int
    ) -> DailyMaterialDNA where EventIDs.Element == String {
        build(
            daySeed: daySeed,
            eventIDs: Array(eventIDs),
            family: family,
            requestedColorCount: min(max(requestedColorCount, 1), 3)
        )
    }

    private static func build(
        daySeed: UInt64,
        eventIDs: [String],
        family: MaterialFamily,
        requestedColorCount: Int
    ) -> DailyMaterialDNA {
        let actualColorCount = family == .solid ? 1 : min(max(requestedColorCount, 1), 3)
        let accent = daySeed.isMultiple(of: 4) ? nil : accentMutation(for: family)
        let actors = eventIDs.map { eventID in
            let actorSeed = daySeed ^ stableHash(eventID)
            let mutation = accent.flatMap { actorUnit(actorSeed, salt: 0xACC3_1700) > 0.46 ? $0 : nil }
            let colors = makeColors(
                daySeed: daySeed,
                actorSeed: actorSeed,
                count: actualColorCount,
                family: family
            )
            let fields = makeFields(
                actorSeed: actorSeed,
                colorCount: actualColorCount,
                family: family,
                mutation: mutation
            )
            let construction = construction(
                family: family,
                mutation: mutation,
                actorSeed: actorSeed
            )
            return ActorMaterialRecipe(
                eventID: eventID,
                family: family,
                mutation: mutation,
                colors: colors,
                fields: fields,
                baseOpacity: construction.opacity,
                edgeSoftness: construction.edgeSoftness,
                contourWidth: construction.contourWidth,
                contourCount: construction.contourCount,
                counterformRadius: construction.counterformRadius,
                counterformSoftness: construction.counterformSoftness
            )
        }
        return DailyMaterialDNA(
            daySeed: daySeed,
            family: family,
            accentMutation: accent,
            requestedColorCount: requestedColorCount,
            actors: actors
        )
    }

    private static func accentMutation(for family: MaterialFamily) -> MaterialMutation {
        switch family {
        case .gradient: .softGradient
        case .solid: .richSolid
        case .sphere: .luminousSphere
        case .glass: .frostedGlass
        case .mist: .diffuseMist
        case .halo: .expandedHalo
        case .luminous: .intenseLuminous
        case .outline: .multiOutline
        case .counterform: .wideCounterform
        }
    }

    private static func makeColors(
        daySeed: UInt64,
        actorSeed: UInt64,
        count: Int,
        family: MaterialFamily
    ) -> [MaterialColor] {
        let baseHue = unit(daySeed ^ 0xB453_C010) * 360
        let actorHueShift = (actorUnit(actorSeed, salt: 0x48E) - 0.5) * 18
        let hueOffsets = [0.0, 52.0, 146.0]
        return (0..<count).map { index in
            let hue = baseHue + actorHueShift + hueOffsets[index]
                + (actorUnit(actorSeed, salt: UInt64(0xC01 + index)) - 0.5) * 16
            let saturationBase = family == .glass ? 0.70 : 0.80
            let saturation = saturationBase
                + actorUnit(actorSeed, salt: UInt64(0x5A7 + index)) * (0.96 - saturationBase)
            let lightness: Double
            if family == .glass {
                lightness = 0.54 + actorUnit(actorSeed, salt: UInt64(0x119 + index)) * 0.18
            } else {
                lightness = 0.43 + actorUnit(actorSeed, salt: UInt64(0x119 + index)) * 0.23
            }
            return hsl(hue: hue, saturation: saturation, lightness: lightness)
        }
    }

    private static func makeFields(
        actorSeed: UInt64,
        colorCount: Int,
        family: MaterialFamily,
        mutation: MaterialMutation?
    ) -> [RadialField] {
        guard family != .solid else { return [] }
        return (0..<colorCount).map { index in
            let x = 0.12 + actorUnit(actorSeed, salt: UInt64(0x100 + index * 7)) * 0.76
            let y = 0.12 + actorUnit(actorSeed, salt: UInt64(0x101 + index * 7)) * 0.76
            let radius: Double
            if index == 0 {
                radius = 0.90 + actorUnit(actorSeed, salt: UInt64(0x102 + index * 7)) * 0.25
            } else {
                radius = 0.55 + actorUnit(actorSeed, salt: UInt64(0x102 + index * 7)) * 0.33
            }
            var softness = 0.52 + actorUnit(actorSeed, salt: UInt64(0x103 + index * 7)) * 0.26
            if mutation == .softGradient || mutation == .frostedGlass || mutation == .diffuseMist {
                softness = min(0.80, softness + 0.05)
            }
            let opacity = index == 0
                ? 1
                : 0.74 + actorUnit(actorSeed, salt: UInt64(0x104 + index * 7)) * 0.22
            let blend: RadialBlend
            if index == 0 {
                blend = .normal
            } else {
                let choices: [RadialBlend] = [.normal, .screen, .softLight, .multiply]
                let selector = Int((actorSeed >> UInt64(index * 9)) % UInt64(choices.count))
                blend = choices[selector]
            }
            return RadialField(
                focus: CompositionPoint(x: x, y: y),
                radius: radius,
                softness: softness,
                opacity: opacity,
                colorIndex: index,
                blend: blend
            )
        }
    }

    private static func construction(
        family: MaterialFamily,
        mutation: MaterialMutation?,
        actorSeed: UInt64
    ) -> (
        opacity: Double,
        edgeSoftness: Double,
        contourWidth: Double,
        contourCount: Int,
        counterformRadius: Double?,
        counterformSoftness: Double
    ) {
        switch family {
        case .gradient:
            return (0.96, mutation == .softGradient ? 0.035 : 0.018, 0, 0, nil, 0)
        case .solid:
            return (1, 0.008, 0, 0, nil, 0)
        case .sphere:
            return (0.98, 0.02, 0, 0, nil, 0)
        case .glass:
            return (mutation == .frostedGlass ? 0.72 : 0.64, 0.026, 0, 0, nil, 0)
        case .mist:
            return (0.70, mutation == .diffuseMist ? 0.095 : 0.075, 0, 0, nil, 0)
        case .halo:
            return (mutation == .expandedHalo ? 0.78 : 0.70, 0.072, 0, 0, nil, 0)
        case .luminous:
            return (mutation == .intenseLuminous ? 0.94 : 0.87, 0.046, 0, 0, nil, 0)
        case .outline:
            let count = mutation == .multiOutline
                ? 2 + Int(actorUnit(actorSeed, salt: 0x0A71) * 2)
                : 1
            let width = 0.026 + actorUnit(actorSeed, salt: 0x0A72) * 0.026
            return (0.92, 0.016, width, count, nil, 0)
        case .counterform:
            let base = 0.30 + actorUnit(actorSeed, salt: 0xC017) * 0.10
            let radius = mutation == .wideCounterform ? min(0.44, base + 0.045) : base
            return (0.93, 0.024, 0, 0, radius, 0.018)
        }
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> MaterialColor {
        let normalizedHue = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = chroma * (1 - abs(normalizedHue.truncatingRemainder(dividingBy: 2) - 1))
        let channels: (Double, Double, Double)
        switch normalizedHue {
        case 0..<1: channels = (chroma, x, 0)
        case 1..<2: channels = (x, chroma, 0)
        case 2..<3: channels = (0, chroma, x)
        case 3..<4: channels = (0, x, chroma)
        case 4..<5: channels = (x, 0, chroma)
        default: channels = (chroma, 0, x)
        }
        let match = lightness - chroma * 0.5
        return MaterialColor(
            red: channels.0 + match,
            green: channels.1 + match,
            blue: channels.2 + match
        )
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xCBF29CE484222325) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001B3
        }
    }

    private static func actorUnit(_ actorSeed: UInt64, salt: UInt64) -> Double {
        unit(actorSeed ^ (salt &* 0x9E3779B97F4A7C15))
    }

    private static func unit(_ seed: UInt64) -> Double {
        var state = seed &+ 0x9E3779B97F4A7C15
        state = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
        state = (state ^ (state >> 27)) &* 0x94D049BB133111EB
        state ^= state >> 31
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
