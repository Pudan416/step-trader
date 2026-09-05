#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsInstrumentManifestError: Error, Equatable {
    case resourceMissing
    case duplicateSourceUID(String)
    case missingSourceUID(String)
    case unexpectedSourceUID(String)
}

enum DayObjectsInstrumentManifest {
    static let defaultDescriptors: [DayObjectsInstrumentDescriptor] = [
        descriptor(
            id: "pad.interstellar", category: .pad, displayName: "Interstellar", bankName: "Bonus",
            sourceUID: "39529417-FBC1-41D5-B1D1-0DED9E38F164", referenceMIDI: 62,
            auditionChord: [50, 57, 64, 69], outputTrimDB: 0
        ),
        descriptor(
            id: "pad.whispering-sands", category: .pad, displayName: "Whispering Sands", bankName: "Bonus",
            sourceUID: "96F9F71C-1D6C-41FC-8192-E4B550562357", referenceMIDI: 62,
            auditionChord: [50, 57, 64, 69], outputTrimDB: 0
        ),
        descriptor(
            id: "pad.forgotten-stories", category: .pad, displayName: "PAD - Forgotten Stories",
            bankName: "Electronisounds", sourceUID: "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9",
            referenceMIDI: 62, auditionChord: [50, 57, 64, 69], outputTrimDB: 0
        ),
        descriptor(
            id: "pluck.play-something-sad", category: .pluck, displayName: "PLK - Play Something Sad",
            bankName: "Electronisounds", sourceUID: "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D",
            referenceMIDI: 74, auditionChord: [62, 69, 76, 81], outputTrimDB: -13.15
        ),
        descriptor(
            id: "pluck.jec-ambient-pizz-2", category: .pluck, displayName: "JEC Ambient Pizz 2", bankName: "JEC",
            sourceUID: "88335303-C675-4D14-907E-2D80823C2BCA", referenceMIDI: 74,
            auditionChord: [62, 69, 76, 81], outputTrimDB: -14.89
        ),
        descriptor(
            id: "pluck.spider-filter-pluck", category: .pluck, displayName: "🕷- Filter Pluck",
            bankName: "Spidericemidas", sourceUID: "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF",
            referenceMIDI: 74, auditionChord: [62, 69, 76, 81], outputTrimDB: -13.15
        ),
        descriptor(
            id: "bass.analog-boom", category: .bass, displayName: "Analog Boom Bass", bankName: "Bonus",
            sourceUID: "C2958050-CDCA-4C64-AF92-3217539CE60A", referenceMIDI: 38,
            auditionChord: [38, 45, 52, 57], outputTrimDB: -15.65
        ),
        descriptor(
            id: "bass.hey-jakob", category: .bass, displayName: "BASS - Hey Jakob!", bankName: "BankA",
            sourceUID: "E2D8B458-C727-4388-A0EA-28802B605796", referenceMIDI: 38,
            auditionChord: [38, 45, 50, 57], outputTrimDB: -9.18
        ),
        descriptor(
            id: "bass.bb-roys-phaser", category: .bass, displayName: "BB Röy’s Phaser Bass", bankName: "Brice Beasley",
            sourceUID: "4131C811-FBB8-4E15-B238-8986645A62D3", referenceMIDI: 38,
            auditionChord: [38, 45, 52, 57], outputTrimDB: -0.75
        ),
        descriptor(
            id: "bass.jec-hollores-2", category: .bass, displayName: "JEC Hollores Bass 2", bankName: "JEC",
            sourceUID: "FA16AF16-3033-485F-A183-4DAAB7025B52", referenceMIDI: 38,
            auditionChord: [38, 45, 52, 57], outputTrimDB: -23.45
        ),
        descriptor(
            id: "lead.verbacious", category: .lead, displayName: "Verbacious Lead", bankName: "Red Sky Lullaby",
            sourceUID: "9BDE3DCB-219D-4D70-A067-C1057B557F19", referenceMIDI: 69,
            auditionChord: [57, 64, 71, 76], outputTrimDB: 0
        ),
        descriptor(
            id: "lead.jec-softwah-2", category: .lead, displayName: "JEC Softwah Lead 2", bankName: "JEC",
            sourceUID: "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F", referenceMIDI: 69,
            auditionChord: [57, 64, 71, 76], outputTrimDB: -14.89
        ),
        descriptor(
            id: "lead.bb-silver-screen", category: .lead, displayName: "BB The Silver Screen Lead",
            bankName: "Brice Beasley", sourceUID: "BB74B6AD-9076-464C-B373-F2E968BBD2BE",
            referenceMIDI: 69, auditionChord: [57, 64, 71, 76], outputTrimDB: -14.89
        ),
        descriptor(
            id: "keys.maschinenmensch", category: .keys, displayName: "Maschinenmensch Keys", bankName: "Bonus",
            sourceUID: "AA903CDB-938B-4FC7-8E01-050DB95EFDE7", referenceMIDI: 60,
            auditionChord: [48, 55, 62, 67], outputTrimDB: 0
        ),
        descriptor(
            id: "keys.bb-slow-poly", category: .keys, displayName: "BB Slow Keys Poly", bankName: "Brice Beasley",
            sourceUID: "6A4C11CA-2CF9-4153-B5D3-A67F28E465A1", referenceMIDI: 60,
            auditionChord: [48, 55, 62, 67], outputTrimDB: 0
        ),
        descriptor(
            id: "keys.jec-polaroids-2", category: .keys, displayName: "JEC Gentlemen Take Polaroids 2", bankName: "JEC",
            sourceUID: "9F2D32B0-ED71-4127-A4C5-F51209656AF7", referenceMIDI: 60,
            auditionChord: [48, 55, 62, 67], outputTrimDB: 0
        ),
    ]

    static func descriptors(in category: DayObjectsInstrumentCategory) -> [DayObjectsInstrumentDescriptor] {
        defaultDescriptors.filter { $0.category == category }
    }

    /// Loads and validates the selected source file as one preparation-time transaction.
    /// The returned array is immutable and ordered by the stable descriptor catalog.
    static func loadSynthOneRecords(from bundle: Bundle) throws -> [SynthOnePresetRecord] {
        guard let url = bundle.url(
            forResource: "selected-presets",
            withExtension: "json",
            subdirectory: "SynthOnePresets"
        ) else {
            throw DayObjectsInstrumentManifestError.resourceMissing
        }

        let decoded = try JSONDecoder().decode([SynthOnePresetRecord].self, from: Data(contentsOf: url))
        let grouped = Dictionary(grouping: decoded, by: \.uid)
        if let duplicate = grouped.first(where: { $0.value.count != 1 })?.key {
            throw DayObjectsInstrumentManifestError.duplicateSourceUID(duplicate)
        }

        let expectedUIDs = Set(defaultDescriptors.compactMap(\.sourceUID))
        if let unexpected = Set(grouped.keys).subtracting(expectedUIDs).sorted().first {
            throw DayObjectsInstrumentManifestError.unexpectedSourceUID(unexpected)
        }

        return try defaultDescriptors.compactMap(\.sourceUID).map { uid in
            guard let record = grouped[uid]?.first else {
                throw DayObjectsInstrumentManifestError.missingSourceUID(uid)
            }
            return record
        }
    }

    private static func descriptor(
        id: String,
        category: DayObjectsInstrumentCategory,
        displayName: String,
        bankName: String,
        sourceUID: String,
        referenceMIDI: UInt8,
        auditionChord: [UInt8],
        outputTrimDB: Double
    ) -> DayObjectsInstrumentDescriptor {
        DayObjectsInstrumentDescriptor(
            id: DayObjectsInstrumentID(rawValue: id),
            category: category,
            displayName: displayName,
            bankName: bankName,
            sourceUID: sourceUID,
            referenceMIDI: referenceMIDI,
            auditionChord: auditionChord,
            outputTrimDB: outputTrimDB
        )
    }
}
#endif
