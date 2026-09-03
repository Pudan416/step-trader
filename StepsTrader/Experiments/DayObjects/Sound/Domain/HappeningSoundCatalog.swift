#if DEBUG || INTERNAL_BUILD
import Foundation

enum HappeningSoundCatalog {
    private struct Identity {
        let workingName: String
        let paletteKind: HappeningPaletteKind
        let topology: String
        let attackTopology: String
        let tailTopology: String
    }

    static let recipes: [HappeningSoundRecipe] = [
        tonal(1, identity: .init(workingName: "Warm analog ping", paletteKind: .synth, topology: "analog-ping", attackTopology: "triangle-sine-closing-filter", tailTopology: "tape-echo"), family: .synthPluck, range: 72...83, gainDB: -12.0, attack: 0.010, release: 1.20, delayMix: 0.04, feedback: 0.10, reverbMix: 0.06, filterStart: 2_400, filterEnd: 9_400),
        tonal(2, identity: .init(workingName: "Glass FM droplet", paletteKind: .synth, topology: "fm-droplet", attackTopology: "fm-falling-index", tailTopology: "dark-diffusion"), family: .synthPluck, range: 72...83, gainDB: -11.5, attack: 0.012, release: 1.35, delayMix: 0.06, feedback: 0.13, reverbMix: 0.08, filterStart: 2_100, filterEnd: 8_800),
        tonal(3, identity: .init(workingName: "Muted pulse pluck", paletteKind: .synth, topology: "pulse-pluck", attackTopology: "lowpass-impulse", tailTopology: "short-room"), family: .synthPluck, range: 72...83, gainDB: -12.5, attack: 0.008, release: 1.05, delayMix: 0.03, feedback: 0.08, reverbMix: 0.05, filterStart: 2_800, filterEnd: 10_200),
        tonal(4, identity: .init(workingName: "Hollow string", paletteKind: .synth, topology: "waveguide-string", attackTopology: "waveguide-noise-excitation", tailTopology: "dry-damping"), family: .synthPluck, range: 72...83, gainDB: -11.8, attack: 0.015, release: 1.50, delayMix: 0.08, feedback: 0.15, reverbMix: 0.10, filterStart: 1_900, filterEnd: 7_600),
        tonal(5, identity: .init(workingName: "Air reed blip", paletteKind: .synth, topology: "reed-blip", attackTopology: "bandpassed-breath-settle", tailTopology: "filtered-breath"), family: .synthPluck, range: 72...83, gainDB: -12.2, attack: 0.010, release: 1.25, delayMix: 0.05, feedback: 0.11, reverbMix: 0.07, filterStart: 2_300, filterEnd: 9_000),
        tonal(6, identity: .init(workingName: "Reverse pluck bloom", paletteKind: .hybrid, topology: "reverse-pluck", attackTopology: "reverse-triangle-swell", tailTopology: "reverse-bloom"), family: .synthPluck, range: 72...83, gainDB: -11.9, attack: 0.014, release: 1.45, delayMix: 0.07, feedback: 0.14, reverbMix: 0.09, filterStart: 2_000, filterEnd: 8_300),

        tonal(7, identity: .init(workingName: "Wooden kalimba", paletteKind: .organic, topology: "kalimba-modal", attackTopology: "damped-thumb-wood", tailTopology: "dry-damping"), family: .acousticMallet, range: 60...71, gainDB: -10.8, attack: 0.004, release: 1.65, delayMix: 0.02, feedback: 0.06, reverbMix: 0.04, filterStart: 1_600, filterEnd: 11_000),
        tonal(8, identity: .init(workingName: "Ceramic knock", paletteKind: .synth, topology: "ceramic-modal", attackTopology: "ceramic-damped-impulse", tailTopology: "modal-decay"), family: .acousticMallet, range: 60...71, gainDB: -11.1, attack: 0.006, release: 1.80, delayMix: 0.03, feedback: 0.07, reverbMix: 0.05, filterStart: 1_400, filterEnd: 10_400),
        tonal(9, identity: .init(workingName: "Soft marimba", paletteKind: .organic, topology: "vcsl-marimba-dark", attackTopology: "soft-marimba-mallet", tailTopology: "dark-diffusion"), family: .acousticMallet, range: 60...71, gainDB: -10.6, attack: 0.005, release: 1.55, delayMix: 0.01, feedback: 0.04, reverbMix: 0.03, filterStart: 1_800, filterEnd: 11_800),
        tonal(10, identity: .init(workingName: "Balafon brush", paletteKind: .organic, topology: "vcsl-balafon-dry", attackTopology: "balafon-brush", tailTopology: "dry-damping"), family: .acousticMallet, range: 60...71, gainDB: -11.4, attack: 0.008, release: 2.05, delayMix: 0.025, feedback: 0.06, reverbMix: 0.04, filterStart: 1_300, filterEnd: 9_600),
        tonal(11, identity: .init(workingName: "Muted vibraphone", paletteKind: .hybrid, topology: "vcsl-vibe-chorus", attackTopology: "muted-vibe-strike", tailTopology: "chorus-decay"), family: .acousticMallet, range: 60...71, gainDB: -10.9, attack: 0.005, release: 1.75, delayMix: 0.05, feedback: 0.10, reverbMix: 0.07, filterStart: 1_500, filterEnd: 10_800),
        tonal(12, identity: .init(workingName: "Felt key", paletteKind: .organic, topology: "felt-key", attackTopology: "felt-hammer", tailTopology: "short-room"), family: .acousticMallet, range: 60...71, gainDB: -11.2, attack: 0.007, release: 1.95, delayMix: 0.035, feedback: 0.08, reverbMix: 0.05, filterStart: 1_350, filterEnd: 10_000),

        tonal(13, identity: .init(workingName: "Soft metal bowl", paletteKind: .hybrid, topology: "metal-bowl-modal", attackTopology: "damped-metal-impulse", tailTopology: "modal-decay"), family: .acousticBell, range: 72...83, gainDB: -13.5, attack: 0.003, release: 3.20, delayMix: 0.03, feedback: 0.07, reverbMix: 0.05, filterStart: 1_100, filterEnd: 12_800),
        tonal(14, identity: .init(workingName: "Glass tap bloom", paletteKind: .hybrid, topology: "glass-reverse", attackTopology: "tiny-glass-tap", tailTopology: "reverse-bloom"), family: .acousticBell, range: 72...83, gainDB: -13.2, attack: 0.004, release: 3.45, delayMix: 0.06, feedback: 0.12, reverbMix: 0.09, filterStart: 1_000, filterEnd: 12_200),
        tonal(15, identity: .init(workingName: "Chorus kalimba", paletteKind: .hybrid, topology: "chorus-kalimba", attackTopology: "plucked-tine", tailTopology: "chorus-decay"), family: .acousticBell, range: 72...83, gainDB: -12.9, attack: 0.003, release: 2.85, delayMix: 0.05, feedback: 0.10, reverbMix: 0.08, filterStart: 1_250, filterEnd: 13_400),
        tonal(16, identity: .init(workingName: "Nylon pizzicato", paletteKind: .organic, topology: "nylon-waveguide", attackTopology: "nylon-string-excitation", tailTopology: "dark-diffusion"), family: .acousticBell, range: 72...83, gainDB: -13.8, attack: 0.006, release: 3.70, delayMix: 0.04, feedback: 0.09, reverbMix: 0.07, filterStart: 900, filterEnd: 11_600),
        tonal(17, identity: .init(workingName: "Dark tubular bell", paletteKind: .organic, topology: "vcsl-tubular-dark", attackTopology: "softened-tubular-strike", tailTopology: "modal-decay"), family: .acousticBell, range: 72...83, gainDB: -13.1, attack: 0.004, release: 3.05, delayMix: 0.02, feedback: 0.05, reverbMix: 0.04, filterStart: 1_150, filterEnd: 7_000),
        tonal(18, identity: .init(workingName: "Distant chime", paletteKind: .organic, topology: "vcsl-chime-dark", attackTopology: "slow-chime-strike", tailTopology: "dark-diffusion"), family: .acousticBell, range: 72...83, gainDB: -13.6, attack: 0.005, release: 3.55, delayMix: 0.07, feedback: 0.14, reverbMix: 0.10, filterStart: 950, filterEnd: 6_500),

        tonal(19, identity: .init(workingName: "Sub bloom", paletteKind: .synth, topology: "sub-bloom", attackTopology: "sub-sine-slow-open", tailTopology: "dark-diffusion"), family: .softOneShot, range: 48...59, gainDB: -11.5, attack: 0.006, release: 1.10, delayMix: 0.03, feedback: 0.08, reverbMix: 0.05, filterStart: 700, filterEnd: 6_200),
        tonal(20, identity: .init(workingName: "Analog filter ping", paletteKind: .synth, topology: "filter-ping", attackTopology: "resonant-filter-impulse", tailTopology: "tape-echo"), family: .softOneShot, range: 48...59, gainDB: -11.8, attack: 0.008, release: 1.35, delayMix: 0.06, feedback: 0.12, reverbMix: 0.07, filterStart: 600, filterEnd: 5_600),
        tonal(21, identity: .init(workingName: "Vocal droplet", paletteKind: .synth, topology: "formant-droplet", attackTopology: "two-formant-sine-excitation", tailTopology: "short-room"), family: .softOneShot, range: 48...59, gainDB: -12.1, attack: 0.010, release: 1.55, delayMix: 0.04, feedback: 0.10, reverbMix: 0.06, filterStart: 520, filterEnd: 5_000),
        tonal(22, identity: .init(workingName: "Phase-distortion bead", paletteKind: .synth, topology: "phase-distortion", attackTopology: "phase-index-decay", tailTopology: "dry-damping"), family: .softOneShot, range: 48...59, gainDB: -11.3, attack: 0.005, release: 0.95, delayMix: 0.02, feedback: 0.06, reverbMix: 0.04, filterStart: 760, filterEnd: 6_800),
        tonal(23, identity: .init(workingName: "Rubber FM bubble", paletteKind: .hybrid, topology: "rubber-fm", attackTopology: "downward-fm-pitch-settle", tailTopology: "chorus-decay"), family: .softOneShot, range: 48...59, gainDB: -11.9, attack: 0.009, release: 1.40, delayMix: 0.07, feedback: 0.14, reverbMix: 0.08, filterStart: 560, filterEnd: 5_300),
        tonal(24, identity: .init(workingName: "Bowed harmonic stab", paletteKind: .hybrid, topology: "harmonic-stab", attackTopology: "slow-bowed-harmonic-onset", tailTopology: "dry-damping"), family: .softOneShot, range: 48...59, gainDB: -12.3, attack: 0.012, release: 1.70, delayMix: 0.08, feedback: 0.15, reverbMix: 0.09, filterStart: 480, filterEnd: 4_800),

        resonant(25, identity: .init(workingName: "Breath resonator", paletteKind: .hybrid, topology: "breath-resonator", attackTopology: "filtered-breath-resonator", tailTopology: "filtered-breath"), referenceMIDI: 60, range: 60...71, resonatorTargetPitchClasses: [0, 3, 6, 9], gainDB: -15.0, attack: 0.080, release: 4.20, delayMix: 0.03, feedback: 0.07, reverbMix: 0.05, filterStart: 260, filterEnd: 6_800),
        resonant(26, identity: .init(workingName: "Bowed glass cloud", paletteKind: .hybrid, topology: "modal-glass-cloud", attackTopology: "bowed-modal-partials", tailTopology: "modal-decay"), referenceMIDI: 60, range: 60...71, resonatorTargetPitchClasses: [0, 3, 6, 9], gainDB: -14.5, attack: 0.120, release: 4.80, delayMix: 0.05, feedback: 0.10, reverbMix: 0.07, filterStart: 220, filterEnd: 5_900),
        resonant(27, identity: .init(workingName: "Granular shimmer", paletteKind: .hybrid, topology: "granular-shimmer", attackTopology: "windowed-pitched-micrograins", tailTopology: "dark-diffusion"), referenceMIDI: 60, range: 60...71, resonatorTargetPitchClasses: [0, 3, 6, 9], gainDB: -15.5, attack: 0.150, release: 5.20, delayMix: 0.06, feedback: 0.12, reverbMix: 0.08, filterStart: 180, filterEnd: 5_200),
        unpitched(28, identity: .init(workingName: "Reverse glass gesture", paletteKind: .organic, topology: "reverse-glass-unpitched", attackTopology: "reversed-filtered-glass-partials", tailTopology: "reverse-bloom"), gainDB: -14.0, attack: 0.050, release: 2.40, delayMix: 0.04, feedback: 0.08, reverbMix: 0.06, filterStart: 400, filterEnd: 7_200),
        unpitched(29, identity: .init(workingName: "Soft dust impact", paletteKind: .organic, topology: "dust-impact", attackTopology: "particulate-under-120ms", tailTopology: "filtered-breath"), gainDB: -14.8, attack: 0.090, release: 3.10, delayMix: 0.01, feedback: 0.04, reverbMix: 0.03, filterStart: 300, filterEnd: 6_000),
        unpitched(30, identity: .init(workingName: "Airy exhale", paletteKind: .organic, topology: "breath-exhale", attackTopology: "breath-formant-crossfade", tailTopology: "filtered-breath"), gainDB: -15.2, attack: 0.110, release: 3.60, delayMix: 0.02, feedback: 0.06, reverbMix: 0.04, filterStart: 240, filterEnd: 5_400),
    ]

    static func recipe(for id: HappeningSoundRecipeID) -> HappeningSoundRecipe? {
        recipes.first { $0.id == id }
    }

    private static func tonal(
        _ rawID: Int,
        identity: Identity,
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
            workingName: identity.workingName,
            paletteKind: identity.paletteKind,
            topology: identity.topology,
            attackTopology: identity.attackTopology,
            tailTopology: identity.tailTopology,
            family: family,
            sources: sources,
            pitch: .tonal(preferredRange: range),
            gainDB: gainDB,
            attackSeconds: attack,
            releaseSeconds: release,
            delayMix: delayMix,
            delayFeedback: feedback,
            reverbMix: spatialReverbMix(reverbMix),
            filterStartHz: filterStart,
            filterEndHz: filterEnd
        )
    }

    private static func resonant(
        _ rawID: Int,
        identity: Identity,
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
            workingName: identity.workingName,
            paletteKind: identity.paletteKind,
            topology: identity.topology,
            attackTopology: identity.attackTopology,
            tailTopology: identity.tailTopology,
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
            reverbMix: spatialReverbMix(reverbMix),
            filterStartHz: filterStart,
            filterEndHz: filterEnd
        )
    }

    private static func unpitched(
        _ rawID: Int,
        identity: Identity,
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
            workingName: identity.workingName,
            paletteKind: identity.paletteKind,
            topology: identity.topology,
            attackTopology: identity.attackTopology,
            tailTopology: identity.tailTopology,
            family: .texture,
            sources: [source(id: rawID, index: 0, name: "\(label(for: rawID))/texture.wav", rootMIDI: 60)],
            pitch: .unpitched,
            gainDB: gainDB,
            attackSeconds: attack,
            releaseSeconds: release,
            delayMix: delayMix,
            delayFeedback: feedback,
            reverbMix: spatialReverbMix(reverbMix),
            filterStartHz: filterStart,
            filterEndHz: filterEnd
        )
    }

    private static func spatialReverbMix(_ legacyMix: Double) -> Double {
        min(max(0.50 + legacyMix * 2.5, 0.55), 0.78)
    }

    private static let processedSHA256ByResourceName: [String: String] = [
        "Happenings/01/A5.wav": "87343d8bbefb4cf040e12be0fcb177fcf46d6653adbcb6fb89f4723fe6e57589",
        "Happenings/01/C5.wav": "f5cb4da97f30c580022590df1892dfd9f4a6d6523c944843af0313b4fb6466d8",
        "Happenings/01/DSharp5.wav": "956cd698c210a5004f389d4e0c1134790af0e2fc1c864101a8384c4923589e83",
        "Happenings/01/FSharp5.wav": "91b615a0c13d79151b4b503dfa6420467d913777ec791fe8991b5015a98b3398",
        "Happenings/02/A5.wav": "8f91c0e8082ea817b48c5140cd3a25e32cbac68f5a1f0a6176aa42b5e2539949",
        "Happenings/02/C5.wav": "5748af97d6a92342104473d80bd18b20640c296edcfb18fd947ca1f837a56553",
        "Happenings/02/DSharp5.wav": "29cf6b4fed50584f722ebd9dad450388d69ac365deb0833c974ff2c78551615a",
        "Happenings/02/FSharp5.wav": "4e3817f30c5055e90e9b5804bc4a9898da74b7ef18d8569be1691f00fd81bfd6",
        "Happenings/03/A5.wav": "3933dc5fb8d971abea06f456d2896e913386966a37f25eb3626d5d2e37af1918",
        "Happenings/03/C5.wav": "8afadb95e566c29ee30e402f3b317cedb6b5214e88cbd7ac7e5c112f7a0a1f35",
        "Happenings/03/DSharp5.wav": "a2e93701aeb80f094695ed1c70ad624381385af1a988ab33dd455e7c61d8566d",
        "Happenings/03/FSharp5.wav": "55590e2190bb5dfb705ed38ac3f665dbc1634c1784641a66eb1de4e3f2c692fd",
        "Happenings/04/A5.wav": "1bee35a0c18dd9e5cc50543476a2bd2630fc6c4c70bba5aa2d9b5e9f1d01f0cd",
        "Happenings/04/C5.wav": "ee428f0d5a41a53f6ec4e86b0e655c02010638c477292826d16fb295b1b4933c",
        "Happenings/04/DSharp5.wav": "25345206aaec7da6fae6151907d077132c808512b0475c19ae3100b0a3d65266",
        "Happenings/04/FSharp5.wav": "56b1631dcfffd508ceefaafa28e284b73618e75a0eb3b54e36c6a6358b99e0a1",
        "Happenings/05/A5.wav": "09099e53b2caaf5820901e7e2e576725115ab6084724dcf012a38aa47595f376",
        "Happenings/05/C5.wav": "7ca3c04833bb35d2fc55b619283665df7fdabbc36bd06481a259ce7b7cc1f618",
        "Happenings/05/DSharp5.wav": "94edcf41393a22388a20ee907838915b34d156598241d52259fea9f22a3577f8",
        "Happenings/05/FSharp5.wav": "96f09bce498dfdce33b2b292ed7c153d0a7fc23caa1f791e587c4efd3c3fb4ed",
        "Happenings/06/A5.wav": "8490fcb642cb0258eecd23334acaa5bd9545f32637a437cf0e20a1a1c318776b",
        "Happenings/06/C5.wav": "3fb73e5f287a797c24f58e5d13229022c74fe03962c4be3b52daf55b95832cfe",
        "Happenings/06/DSharp5.wav": "7763896ed0738f5a7e71fa4912a6ca72e928f6d8bbbaa24129c68debee63c81a",
        "Happenings/06/FSharp5.wav": "279196004b5d5f869f9d724b0ff27d6a1b348d31fc0f871d63fdb336ed126bc4",
        "Happenings/07/A4.wav": "567d856850d90c03e05d3d36240a7df1b7b6e0f15d30e37e93688a404c692f70",
        "Happenings/07/C4.wav": "70069f80ea812fca32ad09bcc91d9d9225e26307b31b104d88acd5c3bc63da7d",
        "Happenings/07/DSharp4.wav": "aa6659a437dc6df3d6718fe836705e1c5dd28a95bada2ac3a9b61fe493c71bb6",
        "Happenings/07/FSharp4.wav": "28931f645d526b9f6a6fdc02a4fea64ce8750eca04c737a530f7c1cdf99f6095",
        "Happenings/08/A4.wav": "24cecc5f99a2b10d52c66d73e785ffca268f0759b373e5a82332f16ec2e448ca",
        "Happenings/08/C4.wav": "197bafccbafe27728a89651d3daff5ce22f8943d5e86f17a3e6f6da0eb4f6ba1",
        "Happenings/08/DSharp4.wav": "dca7243d9dfcd67b92b1913fc464c90a14843f8ac7cc3bd087c717333b4b8f4b",
        "Happenings/08/FSharp4.wav": "604d9d4a7a73c0173f6cee054730cd783ca833c1af358aa331c5ed0e699ee31a",
        "Happenings/09/A4.wav": "1e81dca2a5ae01abb060ca13b2c3771351da7968e16f3639373afffc0552d55f",
        "Happenings/09/C4.wav": "f747b8d21e906bde55795e5574872c2cb2d75e0a600ef09db8ece33b39016767",
        "Happenings/09/DSharp4.wav": "568d0707d90f753a56a5f3dbeabea7fb8e9d5817fab467b74c41e141cf468981",
        "Happenings/09/FSharp4.wav": "dcfae028d4265899e06ca6afd20e986eb014b81bbb15572f2b7c1a93b1e46f00",
        "Happenings/10/A4.wav": "5713d897df1dc7f2caa132f9530efea4a1c70a22cf9e87fa8997d823fba6aadb",
        "Happenings/10/C4.wav": "9ad8ed4c39a2aa201cabd8374d22e0f83fc66d23dd4c30d6c95758821af5047e",
        "Happenings/10/DSharp4.wav": "b088a663c1994ac211bea4f096e1277d1a2b1918517582d6054bdd401169aaa5",
        "Happenings/10/FSharp4.wav": "04114c9db5ef88766f5abe6d9d95fc6059b7bcc8f9b5c796d6b6a4ac4a5c27a4",
        "Happenings/11/A4.wav": "327d159891076b6b767841387419c2373295c05acf22e56ae2ad9b6955bbc4fb",
        "Happenings/11/C4.wav": "408e25dac90c6959fac5612726a14296d3766eb238216b709123b61f7e8da484",
        "Happenings/11/DSharp4.wav": "81e010e9dc95f463ead49d47f5805f6e0a04db6bcd8e21359b761d6c3de442eb",
        "Happenings/11/FSharp4.wav": "d852ca6a2e567e93f8c55e3761dab2b1865af771a4215696e4a0fc4c92d88868",
        "Happenings/12/A4.wav": "02a6f8bd65bff04455c65369702e4d8055b360a7ce8436cacbe692482e3daf25",
        "Happenings/12/C4.wav": "5e2b7e0e4aadf6a8f2819b2950f42f0a675cf454eb9155c759bc897be3fdff46",
        "Happenings/12/DSharp4.wav": "ed041f0cb0934d49ca9ac95d8381f357c82146582f13e00da8960854bda19dff",
        "Happenings/12/FSharp4.wav": "072054284b79bcbb5e1eba6d4ab1b2f709b14f921646650cffc76a01ce224eb7",
        "Happenings/13/A5.wav": "dec945386883c4c09f400a4ab9d73aed7b9f4d25dac30a90d48efe422008474d",
        "Happenings/13/C5.wav": "08d409db4bbe22c9aae3c106193a9de00e17033a99ed96f1cc21dfa1106abc57",
        "Happenings/13/DSharp5.wav": "6c83f6ec13721aab5debe4b5e0da4d9f5f4a5bc3a06ca0c9333fe719f7794693",
        "Happenings/13/FSharp5.wav": "b9cb2f1c6239db2e0e0974c5df97946f7494f129ae5ef3b38084a5a89fc66079",
        "Happenings/14/A5.wav": "27c7da24cb06a09c1d40161baf1ba576b0580b0776b940acbb5d415cfc0793bf",
        "Happenings/14/C5.wav": "5da8dcf1a20525cd2ae0c1ee2bd43915327a50370ed1465d1e9ad4d007655b11",
        "Happenings/14/DSharp5.wav": "cb18ab7e57b3b796c5d413556c4a24a7f6ab04a1f9ed6ae423aa7e7bf4374961",
        "Happenings/14/FSharp5.wav": "84b413d9b3dd1e90f7afd23dffc4b276131b1797661366dbff6b75842c9fd793",
        "Happenings/15/A5.wav": "7872b1464c06ac4f7833d2cd7f1f349795d70441b86d04e06d71994936fc173c",
        "Happenings/15/C5.wav": "824e7ef51af78ee9e000fcf2acf5400cd161cfce522334b92f11895de018b957",
        "Happenings/15/DSharp5.wav": "aa7faefb14c58fc9fb9278acda9edf3f3db50a2776a56c6705919bfe2d0813e1",
        "Happenings/15/FSharp5.wav": "2dc0cb3aeaf4fa247f62572c111e8a699a7a6431a5cda5c268271f185f1db5db",
        "Happenings/16/A5.wav": "8b6f98d45043d6af4689c795d06e9f934dfd1c5dc9f3f66860c0d03529e79ab9",
        "Happenings/16/C5.wav": "eeeb6be15318293531a0f1d7c54fc469d3c12845600aff4ba6fcfe959a3b0eb0",
        "Happenings/16/DSharp5.wav": "61f51190e15e4e6c1b61ff2bf83585bee8c9978354b1c16fce878ef63fd65be9",
        "Happenings/16/FSharp5.wav": "5c70b957075e23924ca996a418c593d8b8ba0124a7f205859ca6fcd981a999f4",
        "Happenings/17/A5.wav": "fc61fec05e7eea75a13fba00af58cc3624688a4dd4894cc6dac8e72c04514d28",
        "Happenings/17/C5.wav": "7fe40146df34e251129ea38de71227266e4542f973a60e587294cc109e30152a",
        "Happenings/17/DSharp5.wav": "a93ffaa176c31665048f9a6d1694dbb0d6111c516042bbac3b05a3ddaa0d48de",
        "Happenings/17/FSharp5.wav": "7fce2d43ed7a61936985358d8b14fba89d8aafcff5779e06d70c9a58688a095d",
        "Happenings/18/A5.wav": "6333221c2893d5a523760619086a7e188e60db904f776428cacd2a28d9494534",
        "Happenings/18/C5.wav": "156a4be966709694ac4e0da2f888182b72192ea14bda859a12845212bcb97179",
        "Happenings/18/DSharp5.wav": "eb394e73dfe01102b94a90814932084b267b443e3118a2a27d7429288a56f0ce",
        "Happenings/18/FSharp5.wav": "4695510508165a4520bc603f44444f643b220041e356675da8869318c9d26ea1",
        "Happenings/19/A3.wav": "476d4f6978b9211f65d17a6d511ec04e9a78a8675f9d7bfa1c924d3919cb0350",
        "Happenings/19/C3.wav": "90e1fd45817376e456d820d017ad4fc218d9aa0635f5f609395f80ad2355ad5c",
        "Happenings/19/DSharp3.wav": "59b2137220c930a1bd4be83c98ddb047e4bf2c44e1a1edf64a5f883cf47bcc96",
        "Happenings/19/FSharp3.wav": "28e19df3768189aa4ffbb078b66760b9d7111b9865dd39c9c8225c7a4a20b172",
        "Happenings/20/A3.wav": "96a0260bdfd24bd8fbd8e5bfa9e273e42e4cacc9bfa7c0ac39a485ea4ec8aaa3",
        "Happenings/20/C3.wav": "519754b2bba831e5d4bf2f83b819c1add864005e0ecb47d59087a266a5713530",
        "Happenings/20/DSharp3.wav": "65e747da861e260d4d8f17ed4fc77a445bf991542f57c367bfca2288044fc6fa",
        "Happenings/20/FSharp3.wav": "e5889cd0a57a5c30f366b7d20eb33f60aa8d3741d43c1c9214d564e3d90c3cfa",
        "Happenings/21/A3.wav": "046664660b9f5a22c72083330a675e050f2587809fc83731efa62183c24930ac",
        "Happenings/21/C3.wav": "37d23a57ce34225fb9ad88cac13f4412503eee48160b2b9a93403895090f27bc",
        "Happenings/21/DSharp3.wav": "99451592f5230089877923047703b5c02101653cd2a0b6c2c53177e5da8342b2",
        "Happenings/21/FSharp3.wav": "4e6188e2b5911b610a1f1798001d39604582658fe6757ce3eeb98a535cecd519",
        "Happenings/22/A3.wav": "1ba4feb6f014926dc7ff24528d8e06d1c7e26df9c650b33e6cc577b7c55c342d",
        "Happenings/22/C3.wav": "4d693a8310f208146a2439fde891e025dc80d5532d26572d6444ed4aa83f0521",
        "Happenings/22/DSharp3.wav": "aea7bbcab1048ee4c69270e95540f67cd5b8bbebe5e4b057ab44492291e0d650",
        "Happenings/22/FSharp3.wav": "6ca071f003e0725fc907792ea8a75d298af249273e0fdc68f7a274782a32d224",
        "Happenings/23/A3.wav": "5423ce3bf79ebf4dd6fabb859c421e5c063b4c97022df0fe4237e4d6b0c4a1a1",
        "Happenings/23/C3.wav": "d6031782c3295e7c9dbd471f8649e7ce8245617a70dfa85a2b0cbcc595f21554",
        "Happenings/23/DSharp3.wav": "b45bc9553d83b869a394d50d29cb7487634719297a9c85eaa912fbb5fc4af9ff",
        "Happenings/23/FSharp3.wav": "f229cf4ebfc3218de18688003fa117cd6573a1b35c36a352c95b55a1ef8c912b",
        "Happenings/24/A3.wav": "4171d5ef687ea1a601ff2925b890fbe0574f27bae970bf2029ec3b3bfef58541",
        "Happenings/24/C3.wav": "334743b972fa144c18bf461ec7ef5ed43f2f4411cd13494ba9f72e19c3f1425a",
        "Happenings/24/DSharp3.wav": "dc4d6010196258af15156176d7fe221665e0c434b2df4ff0399738c2dd332ff2",
        "Happenings/24/FSharp3.wav": "02d0407a39b21cea2a5a7d99c4825686a54a48251aebdb2d170ca1ca8cdcc7eb",
        "Happenings/25/noise.wav": "7e0bf490b0c7a96a80c3ae166020182725888b1a9d2fa277da5fcdfd6b2c5c71",
        "Happenings/26/noise.wav": "6166932886f06b75aadef5a221768c6ed2f37e13f4b93b6517a841c6a1b531f8",
        "Happenings/27/noise.wav": "99dcbcad186ffc48910ffd5f5f0dc78ef9c3571998fabeb3755cb99f21236ff0",
        "Happenings/28/texture.wav": "0858108ee721ac188bfe26d7bb4c022e2311cfd409575642781d850c599c4ddc",
        "Happenings/29/texture.wav": "67a17d1e6d214aabb09d2d2190c8a216a54275a5b8c17481a0b8fbe78def13a4",
        "Happenings/30/texture.wav": "07efd721f1ca0219058641e90a10fd715a3fa3726757be98d28efa84b700e6b2",
    ]

    private static func source(id: Int, index: Int, name: String, rootMIDI: UInt8) -> HappeningSampleSource {
        let resourceName = "Happenings/\(name)"
        guard let sha256 = processedSHA256ByResourceName[resourceName] else {
            preconditionFailure("Missing processed SHA-256 for \(resourceName)")
        }
        return HappeningSampleSource(resourceName: resourceName, rootMIDI: rootMIDI, sha256: sha256)
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
