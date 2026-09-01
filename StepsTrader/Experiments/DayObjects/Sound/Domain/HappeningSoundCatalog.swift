#if DEBUG || INTERNAL_BUILD
import Foundation

enum HappeningSoundCatalog {
    static let recipes: [HappeningSoundRecipe] = [
        tonal(1, family: .synthPluck, range: 72...83, gainDB: -12.0, attack: 0.010, release: 1.20, delayMix: 0.18, feedback: 0.22, reverbMix: 0.30, filterStart: 2_400, filterEnd: 9_400),
        tonal(2, family: .synthPluck, range: 72...83, gainDB: -11.5, attack: 0.012, release: 1.35, delayMix: 0.20, feedback: 0.25, reverbMix: 0.34, filterStart: 2_100, filterEnd: 8_800),
        tonal(3, family: .synthPluck, range: 72...83, gainDB: -12.5, attack: 0.008, release: 1.05, delayMix: 0.16, feedback: 0.20, reverbMix: 0.28, filterStart: 2_800, filterEnd: 10_200),
        tonal(4, family: .synthPluck, range: 72...83, gainDB: -11.8, attack: 0.015, release: 1.50, delayMix: 0.24, feedback: 0.28, reverbMix: 0.36, filterStart: 1_900, filterEnd: 7_600),
        tonal(5, family: .synthPluck, range: 72...83, gainDB: -12.2, attack: 0.010, release: 1.25, delayMix: 0.19, feedback: 0.24, reverbMix: 0.32, filterStart: 2_300, filterEnd: 9_000),
        tonal(6, family: .synthPluck, range: 72...83, gainDB: -11.9, attack: 0.014, release: 1.45, delayMix: 0.22, feedback: 0.26, reverbMix: 0.35, filterStart: 2_000, filterEnd: 8_300),

        tonal(7, family: .acousticMallet, range: 60...71, gainDB: -10.8, attack: 0.004, release: 1.65, delayMix: 0.14, feedback: 0.18, reverbMix: 0.42, filterStart: 1_600, filterEnd: 11_000),
        tonal(8, family: .acousticMallet, range: 60...71, gainDB: -11.1, attack: 0.006, release: 1.80, delayMix: 0.16, feedback: 0.20, reverbMix: 0.45, filterStart: 1_400, filterEnd: 10_400),
        tonal(9, family: .acousticMallet, range: 60...71, gainDB: -10.6, attack: 0.005, release: 1.55, delayMix: 0.12, feedback: 0.16, reverbMix: 0.38, filterStart: 1_800, filterEnd: 11_800),
        tonal(10, family: .acousticMallet, range: 60...71, gainDB: -11.4, attack: 0.008, release: 2.05, delayMix: 0.18, feedback: 0.22, reverbMix: 0.48, filterStart: 1_300, filterEnd: 9_600),
        tonal(11, family: .acousticMallet, range: 60...71, gainDB: -10.9, attack: 0.005, release: 1.75, delayMix: 0.15, feedback: 0.19, reverbMix: 0.43, filterStart: 1_500, filterEnd: 10_800),
        tonal(12, family: .acousticMallet, range: 60...71, gainDB: -11.2, attack: 0.007, release: 1.95, delayMix: 0.17, feedback: 0.21, reverbMix: 0.46, filterStart: 1_350, filterEnd: 10_000),

        tonal(13, family: .acousticBell, range: 72...83, gainDB: -13.5, attack: 0.003, release: 3.20, delayMix: 0.26, feedback: 0.30, reverbMix: 0.58, filterStart: 1_100, filterEnd: 12_800),
        tonal(14, family: .acousticBell, range: 72...83, gainDB: -13.2, attack: 0.004, release: 3.45, delayMix: 0.28, feedback: 0.32, reverbMix: 0.62, filterStart: 1_000, filterEnd: 12_200),
        tonal(15, family: .acousticBell, range: 72...83, gainDB: -12.9, attack: 0.003, release: 2.85, delayMix: 0.24, feedback: 0.28, reverbMix: 0.54, filterStart: 1_250, filterEnd: 13_400),
        tonal(16, family: .acousticBell, range: 72...83, gainDB: -13.8, attack: 0.006, release: 3.70, delayMix: 0.30, feedback: 0.34, reverbMix: 0.66, filterStart: 900, filterEnd: 11_600),
        tonal(17, family: .acousticBell, range: 72...83, gainDB: -13.1, attack: 0.004, release: 3.05, delayMix: 0.25, feedback: 0.29, reverbMix: 0.56, filterStart: 1_150, filterEnd: 12_600),
        tonal(18, family: .acousticBell, range: 72...83, gainDB: -13.6, attack: 0.005, release: 3.55, delayMix: 0.29, feedback: 0.33, reverbMix: 0.64, filterStart: 950, filterEnd: 11_900),

        tonal(19, family: .softOneShot, range: 48...59, gainDB: -11.5, attack: 0.006, release: 1.10, delayMix: 0.11, feedback: 0.16, reverbMix: 0.36, filterStart: 700, filterEnd: 6_200),
        tonal(20, family: .softOneShot, range: 48...59, gainDB: -11.8, attack: 0.008, release: 1.35, delayMix: 0.13, feedback: 0.18, reverbMix: 0.40, filterStart: 600, filterEnd: 5_600),
        tonal(21, family: .softOneShot, range: 48...59, gainDB: -12.1, attack: 0.010, release: 1.55, delayMix: 0.16, feedback: 0.20, reverbMix: 0.44, filterStart: 520, filterEnd: 5_000),
        tonal(22, family: .softOneShot, range: 48...59, gainDB: -11.3, attack: 0.005, release: 0.95, delayMix: 0.10, feedback: 0.14, reverbMix: 0.32, filterStart: 760, filterEnd: 6_800),
        tonal(23, family: .softOneShot, range: 48...59, gainDB: -11.9, attack: 0.009, release: 1.40, delayMix: 0.14, feedback: 0.19, reverbMix: 0.42, filterStart: 560, filterEnd: 5_300),
        tonal(24, family: .softOneShot, range: 48...59, gainDB: -12.3, attack: 0.012, release: 1.70, delayMix: 0.17, feedback: 0.22, reverbMix: 0.46, filterStart: 480, filterEnd: 4_800),

        resonant(25, referenceMIDI: 60, range: 60...71, resonatorTargetPitchClasses: [0, 3, 6, 9], gainDB: -15.0, attack: 0.080, release: 4.20, delayMix: 0.30, feedback: 0.36, reverbMix: 0.68, filterStart: 260, filterEnd: 6_800),
        resonant(26, referenceMIDI: 60, range: 60...71, resonatorTargetPitchClasses: [0, 3, 6, 9], gainDB: -14.5, attack: 0.120, release: 4.80, delayMix: 0.34, feedback: 0.40, reverbMix: 0.72, filterStart: 220, filterEnd: 5_900),
        resonant(27, referenceMIDI: 60, range: 60...71, resonatorTargetPitchClasses: [0, 3, 6, 9], gainDB: -15.5, attack: 0.150, release: 5.20, delayMix: 0.38, feedback: 0.44, reverbMix: 0.76, filterStart: 180, filterEnd: 5_200),
        unpitched(28, gainDB: -14.0, attack: 0.050, release: 2.40, delayMix: 0.22, feedback: 0.28, reverbMix: 0.60, filterStart: 400, filterEnd: 7_200),
        unpitched(29, gainDB: -14.8, attack: 0.090, release: 3.10, delayMix: 0.28, feedback: 0.34, reverbMix: 0.68, filterStart: 300, filterEnd: 6_000),
        unpitched(30, gainDB: -15.2, attack: 0.110, release: 3.60, delayMix: 0.32, feedback: 0.38, reverbMix: 0.72, filterStart: 240, filterEnd: 5_400),
    ]

    static func recipe(for id: HappeningSoundRecipeID) -> HappeningSoundRecipe? {
        recipes.first { $0.id == id }
    }

    private static func tonal(
        _ rawID: Int,
        family: HappeningRecipeFamily,
        range: ClosedRange<UInt8>,
        gainDB: Double,
        attack: Double,
        release: Double,
        delayMix: Double,
        feedback: Double,
        reverbMix: Double,
        filterStart: Double,
        filterEnd: Double
    ) -> HappeningSoundRecipe {
        let id = makeID(rawID)
        let roots: [(midi: UInt8, name: String)] = [
            (range.lowerBound, "C"),
            (range.lowerBound + 3, "DSharp"),
            (range.lowerBound + 6, "FSharp"),
            (range.lowerBound + 9, "A"),
        ]
        let sources = roots.enumerated().map { index, root in
            source(id: rawID, index: index, name: "\(label(for: rawID))/\(root.name)\(Int(root.midi / 12) - 1).wav", rootMIDI: root.midi)
        }
        return HappeningSoundRecipe(
            id: id,
            label: label(for: rawID),
            family: family,
            sources: sources,
            pitch: .tonal(preferredRange: range),
            gainDB: gainDB,
            attackSeconds: attack,
            releaseSeconds: release,
            delayMix: delayMix,
            delayFeedback: feedback,
            reverbMix: reverbMix,
            filterStartHz: filterStart,
            filterEndHz: filterEnd
        )
    }

    private static func resonant(
        _ rawID: Int,
        referenceMIDI: UInt8,
        range: ClosedRange<UInt8>,
        resonatorTargetPitchClasses: [UInt8],
        gainDB: Double,
        attack: Double,
        release: Double,
        delayMix: Double,
        feedback: Double,
        reverbMix: Double,
        filterStart: Double,
        filterEnd: Double
    ) -> HappeningSoundRecipe {
        HappeningSoundRecipe(
            id: makeID(rawID),
            label: label(for: rawID),
            family: .texture,
            sources: [source(id: rawID, index: 0, name: "\(label(for: rawID))/noise.wav", rootMIDI: referenceMIDI)],
            pitch: .resonantNoise(
                referenceMIDI: referenceMIDI,
                preferredRange: range,
                resonatorTargetPitchClasses: resonatorTargetPitchClasses
            ),
            gainDB: gainDB,
            attackSeconds: attack,
            releaseSeconds: release,
            delayMix: delayMix,
            delayFeedback: feedback,
            reverbMix: reverbMix,
            filterStartHz: filterStart,
            filterEndHz: filterEnd
        )
    }

    private static func unpitched(
        _ rawID: Int,
        gainDB: Double,
        attack: Double,
        release: Double,
        delayMix: Double,
        feedback: Double,
        reverbMix: Double,
        filterStart: Double,
        filterEnd: Double
    ) -> HappeningSoundRecipe {
        HappeningSoundRecipe(
            id: makeID(rawID),
            label: label(for: rawID),
            family: .texture,
            sources: [source(id: rawID, index: 0, name: "\(label(for: rawID))/texture.wav", rootMIDI: 60)],
            pitch: .unpitched,
            gainDB: gainDB,
            attackSeconds: attack,
            releaseSeconds: release,
            delayMix: delayMix,
            delayFeedback: feedback,
            reverbMix: reverbMix,
            filterStartHz: filterStart,
            filterEndHz: filterEnd
        )
    }

    private static func source(id: Int, index: Int, name: String, rootMIDI: UInt8) -> HappeningSampleSource {
        HappeningSampleSource(
            resourceName: "Happenings/\(name)",
            rootMIDI: rootMIDI,
            sha256: String(format: "%064llx", UInt64(id * 10 + index))
        )
    }

    private static func makeID(_ rawValue: Int) -> HappeningSoundRecipeID {
        guard let id = HappeningSoundRecipeID(rawValue: rawValue) else {
            preconditionFailure("Catalog recipe IDs must stay in 1...30")
        }
        return id
    }

    private static func label(for rawID: Int) -> String {
        String(format: "%02d", rawID)
    }
}
#endif
