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

    private static let processedSHA256ByResourceName: [String: String] = [
        "Happenings/01/A5.wav": "174b5124eafa5bcac0a9ae2adf31e6f361078aa3ceaeb4788b946c8057bcada4",
        "Happenings/01/C5.wav": "d7e5b13dba0d79dea7837884798cb18222079d03e438b462fe1b2c900e244aa8",
        "Happenings/01/DSharp5.wav": "db8aeb122531d9bd7b90fb3aa1195709fc2ad1fe8ae00ad719019134afc80d59",
        "Happenings/01/FSharp5.wav": "f67d7d399aad4225807cbf3f2e7c4a5290fd0e011e71afa5dbcdad26d17d0bf0",
        "Happenings/02/A5.wav": "83e3b1b91e153deaa0a5bb9fda1e42fd85895dda2551d2efa5ffa25d57d14227",
        "Happenings/02/C5.wav": "46a957524c254e171a7bfa38a80cf336a3a19c6077140c516447ada675fd49f8",
        "Happenings/02/DSharp5.wav": "4f85fed1eea7c4fca19776f3f7f97c0d9ab4851ddda5c31573c6d68cfa8df8a6",
        "Happenings/02/FSharp5.wav": "878a8bfea8600964bf70ff22e09509d5115bf02de14d549299f6aa6e983684d5",
        "Happenings/03/A5.wav": "187b761bd3b8fdd09f58c7cd19c2e15c5f417a73439f77f5a97cd5d160d1f37c",
        "Happenings/03/C5.wav": "05a33dc77539f8944c75a8c32fb2d99695d52ecc8638c2664773798de0ce2e48",
        "Happenings/03/DSharp5.wav": "848694d2b14a7c76fa90a3c65b82b2dac91c62dc72ed611157c5415433c5f220",
        "Happenings/03/FSharp5.wav": "9f774994b53105e8849bd4c6f8396fb96d75b72de664d9632da6049ac16df126",
        "Happenings/04/A5.wav": "b324a9b1549e409931ab2868922f5063e9a1a8a4e16c012331cda935fde66f00",
        "Happenings/04/C5.wav": "68aa6bbf02b6724f06f2844481347151a1423d3de2053accb19b1b40f199033d",
        "Happenings/04/DSharp5.wav": "2fb4ad19b0f2cda20837773fa2ec125f8c483a2aaa3fd27543fcb36be1332a58",
        "Happenings/04/FSharp5.wav": "cf729ca627cbbcc6f61d78aa7c4bc51bbf85eae6b123b0aca7d4f479d2204602",
        "Happenings/05/A5.wav": "468cb8bb89f0c42bb9535893c9f041e97f2ead24eaef0fecab48ff4bc67d534c",
        "Happenings/05/C5.wav": "2a3edc0bbaf0c7f7d20aeadc28eebe13d2d2cea1373e2d1fd3fb49e3a052316d",
        "Happenings/05/DSharp5.wav": "795cf8165ed91816faf72f80c6959b4b355f26010efe46752fabec3808426a27",
        "Happenings/05/FSharp5.wav": "95ffcec88e2504c1df805a61887e063b8c9e14fee296bb0c08f027791587104e",
        "Happenings/06/A5.wav": "52387ca3fd8b9be9fe703ff53fdcd734ac2d33615c227c77416416c0dbf8d87f",
        "Happenings/06/C5.wav": "1d3887b5670d9ff55efa27a748e7bcae024051fb11f0680b512b252fe9b8d059",
        "Happenings/06/DSharp5.wav": "4a536adb6752047b7e7af020b196346a17088d541c7215c7c11ca92e263e4d7b",
        "Happenings/06/FSharp5.wav": "20062c95ad274a3e59a99a1f27dcd5ee5c4dd260ca4a6b67890135f168d4cb73",
        "Happenings/07/A4.wav": "8be9a4d37253fa1f8c14454509ac51d8567ff7b6e06acd84b7c9cc0925f6eccf",
        "Happenings/07/C4.wav": "c18112a5ae032763698bb61372e26b423ac54af509a9457222d118184be7b12d",
        "Happenings/07/DSharp4.wav": "feb0bf5d1cd23be63696f309dcb8b8cc5365219b6af02ecc4a0eb7d85b3a017b",
        "Happenings/07/FSharp4.wav": "d9420d19e904f2bc16a87f4156e68a444bc1359576c8700899f15152ffc1a5c0",
        "Happenings/08/A4.wav": "e4a4d8879d4fde49c195c7fcdcc51586edf8a9cf1bbcd838e2e34b4998f2cee7",
        "Happenings/08/C4.wav": "164a18e344c2550523a3c5ffe21701930459304f81ef22233c45b5805833319c",
        "Happenings/08/DSharp4.wav": "01a141766c9adde31924dfb019bae1e451bc858d50106bc53d650278afe20f41",
        "Happenings/08/FSharp4.wav": "d22f57513ed40397175e3f92bd4915bea81b40b4320f6e116d9c0464d004dd2c",
        "Happenings/09/A4.wav": "4fb2ed57affae3f16b36fc84e5288b546cd83cd995b0e7b8ac6aea4620f70adf",
        "Happenings/09/C4.wav": "1445a27ec44ecdd198bf905f38c1d045970d69ed79e621e497bfdbce021c15d7",
        "Happenings/09/DSharp4.wav": "6ae2481b4a0f06377e2391bdfdeafdb46dd4f11a5663973f89c4797fd57e8b8a",
        "Happenings/09/FSharp4.wav": "acde56d256046c52f4425ad178c669289f25294e1fe7e81578b69d6e369f45f7",
        "Happenings/10/A4.wav": "57a00d2777c97ec35adbbb78536e24a363e665aac69f187f5047adac2208ec13",
        "Happenings/10/C4.wav": "4f552bf937a5abcda571ffe17fdddb7f4f4c61bc640dc96d266561b1b2cb8aba",
        "Happenings/10/DSharp4.wav": "6c16d9632ff9e52a08031ef8d18d44f4e9adcf9801b340face135cdef2f03e77",
        "Happenings/10/FSharp4.wav": "f2500638027409579d748239925207f609a70f393466fdc672d53a1909af83d3",
        "Happenings/11/A4.wav": "04a5f666dc5178d70ef6584fa1ca4de42c93925fbebacb9251cf412266e77942",
        "Happenings/11/C4.wav": "306ca3c86b68408b1094756b149a6aabd9b38aff19f62ab953ecd5edb4f2b05e",
        "Happenings/11/DSharp4.wav": "02cd9194bbb2335f95f0ac23fb98c246516aa1732c8bd14947b29432f619479a",
        "Happenings/11/FSharp4.wav": "e68b10d2eb2a93130bf230774f151b7cd84615670d1a9fb4d7d7727518493931",
        "Happenings/12/A4.wav": "5b29574ad2ca3fd72ae6f2d9284524897c4be3dc1495e615962bde1047c0154c",
        "Happenings/12/C4.wav": "694367737514b84d09e41d7987938ddf8829a48f3381eae5b18e9c3ca9dadcfc",
        "Happenings/12/DSharp4.wav": "e6538f8be5545d90666563aa2f0c14866a609831da5318289a7d6bdd11b0600d",
        "Happenings/12/FSharp4.wav": "bd24493781879f3df7c4e30c8325a5db233e09acad3717164e24fab6b89fae33",
        "Happenings/13/A5.wav": "459e084dcf6ad29e3ddd6c57a5a9d7f4930c9884f29eafab87f09fee93517903",
        "Happenings/13/C5.wav": "04c5224adc78f21b404d3351e0ceba43f2a51f40ef6568d11d336674db9de89f",
        "Happenings/13/DSharp5.wav": "582c9b49446307646ab0369660c41701e7609eb6f943bf179c50185b90696e61",
        "Happenings/13/FSharp5.wav": "0f47fe753ddef1cf152242781f99b92eb57154c467d35e916a63d5ffc9cca632",
        "Happenings/14/A5.wav": "e2ab9368a3835848ef82553851ea971b738b989753ea5d2b8da9b3b2439941b3",
        "Happenings/14/C5.wav": "d97af1305d4e3eeb9b8b24cc06f03e6257ef2061333911b8e83761a706109606",
        "Happenings/14/DSharp5.wav": "7ab940c0b0d4145a170c3dca9a312e3d482d7f45f4f9a5665ece9c7340dcbef5",
        "Happenings/14/FSharp5.wav": "203a4db56fd7c4a5c94c12301fc6a88ec1f834df1d4567e46745b9dd3a3b659d",
        "Happenings/15/A5.wav": "a48c7776ba09ffe7b85bcf008f8cee9ae581ea0d06bb81b55d5da819027d1b4c",
        "Happenings/15/C5.wav": "e5b5faf72329044a329d76e87f31bd8998a579e7340bde2be0f63429f65612d5",
        "Happenings/15/DSharp5.wav": "d3ed490b3c14cd6b19cdf48cad0bf409263b4f9ffe63741d71a6f308853a675f",
        "Happenings/15/FSharp5.wav": "bca22214d16a40a652b11a1205da2d1fc1b741db2cf217c3d0df8711ad82093e",
        "Happenings/16/A5.wav": "8a1831575f3aaf486d0c9b181205a22da4fdf24ca7a6ce892b1cdcfa540966b1",
        "Happenings/16/C5.wav": "18a39ae171623566f59bf29b1632919ae773c4f61bceef79cbf216e916b137b9",
        "Happenings/16/DSharp5.wav": "8e4ff81c7b0c30a2cd43c1490b56d0d5b9a1bf70106cb1ce4f9a9012c5686620",
        "Happenings/16/FSharp5.wav": "82ea486e67cc5177ad61b00f2c2c892f006197947339a0183b04716541cd6f1f",
        "Happenings/17/A5.wav": "7b2ab73d4723b2b8e93c5dfdb1147a7bd1c1d1c152b74008ffb81a1adff1aecf",
        "Happenings/17/C5.wav": "4b080e50d5c7ff98f5273cebc510aac3273a1ef8fa74d591f71ad8500f04cabe",
        "Happenings/17/DSharp5.wav": "436a44640d7ada201c7960137132d51d61a81abd3354ca55da15baef5bff5a22",
        "Happenings/17/FSharp5.wav": "b06ef147a408dec9498058af1790a06ba64b9804468594e6407c0381f076072a",
        "Happenings/18/A5.wav": "a8aeba93584b4f4b99c44027d464c5eb4b5150da6a5f16575ceb2bc74402ce4b",
        "Happenings/18/C5.wav": "4b6af905433ca1f95fc93c471858654040e9888f40241ba244b3517eb00259e7",
        "Happenings/18/DSharp5.wav": "f7a52b55b5421abe9350dc3d0e9d60f9cc94448cbdfe4fdd3de399ccc30ba22c",
        "Happenings/18/FSharp5.wav": "eade9917e4d75d87d4828c573fcb84fe58b7fa2d349e40a123730ba1eee63707",
        "Happenings/19/A3.wav": "58194f97ec963e8f16c5c431a4e0e64e8aa569af1070f053f4febff2bcb1b52f",
        "Happenings/19/C3.wav": "a49a9095b5f7cc6bd42c3b36d7c84315f3fa7df5220a73c959d2152399c62da7",
        "Happenings/19/DSharp3.wav": "bfce8d699612a8d0b62aa0373406e97dc95b13daa7994f0de9d05eeb5f15d3f0",
        "Happenings/19/FSharp3.wav": "5913da2e4c65a8038a8c8d9ce8c527a438f6afd85cedc472331b4b312cf6aa68",
        "Happenings/20/A3.wav": "cd9e65d54b5172a0642aa48c64d806ee50eb5d26ae35b2f31b8dd1e85213a122",
        "Happenings/20/C3.wav": "f360dae3fdd9da63a09fca9dac05a3ec0216dda189cd3833b3d90d1bcca8c29f",
        "Happenings/20/DSharp3.wav": "e748251b720b18df7e913a22d23b1e0520d3f2b0eeecd9e9d9d87d9dca13d53e",
        "Happenings/20/FSharp3.wav": "1a76717f7e101a4e90534899c0159f570adc7b602ee5a38891a5bfa24735da28",
        "Happenings/21/A3.wav": "06825a8fe60f96772bf42b54788932b2eaf3096c523319c2c0524ef94052f568",
        "Happenings/21/C3.wav": "c40f0474ba2dce6559033599fe0368f9fe5aa316c57da8aa428faf236569741d",
        "Happenings/21/DSharp3.wav": "aa5264ea7a835b295e5388272c234d3d380a510d8a3ee69832a6a4ff0d152bdf",
        "Happenings/21/FSharp3.wav": "469a9b3152648dca04e5dd394872bf3a0e88ebea8135d205eb15f09ca5736487",
        "Happenings/22/A3.wav": "c0e71d10cc29519fd3b623d4b5c374350682e1ce494062c9dff799e764a11150",
        "Happenings/22/C3.wav": "e361ea76a6a75ae3199540a3c706f8ba9109e33d89809a8c2e9b761b9b3e7dcb",
        "Happenings/22/DSharp3.wav": "f5dd5678fd8f0b0d366a37e06df6820bd2e5b832f250cd4bed65248442a52a18",
        "Happenings/22/FSharp3.wav": "3a180f93744034d4e4a9b2b34e4cbbe74250e3439d1c9a6e3d3693cf33a9fc0f",
        "Happenings/23/A3.wav": "fd61eb802fe7f411dbb8277a4ea31c49ae54705ae05118b63c706bad76cded33",
        "Happenings/23/C3.wav": "23319b25c31890a92a37a6f20c2121996098c63ecd78e4e2ddd50b61b1bd43cb",
        "Happenings/23/DSharp3.wav": "14b97827e2891f3bbe1f94a39f9c8b0b5fcb39f775d3b23278e6b433f59eb35c",
        "Happenings/23/FSharp3.wav": "51d476b1de59a0c3822e31c60a4afa4a90d0e47bff10b4ec0241d96657361541",
        "Happenings/24/A3.wav": "85118cae110c91c65e34695293cc14c7c34b52e0b16f84fad7fea34e6fd1112e",
        "Happenings/24/C3.wav": "15417638f18723ff3f4f072e148fb0189f1747a998a1a5b445eb7b86d0a2fc52",
        "Happenings/24/DSharp3.wav": "fa7ea8dcc522e28ca9efe0e727a878b6574f9fd7d122a71c1df23736ccf45692",
        "Happenings/24/FSharp3.wav": "853902719bb3cb018428b67ce84a8b6a922e9a9a3d2b1c26170ff8036ee06381",
        "Happenings/25/noise.wav": "0fc557bf3a059f5149a9d90383f58ac3b00ee79fb69982debcacb629c25bc452",
        "Happenings/26/noise.wav": "6fbd8b9a7d17066f7401890ba4030a9cc4fc665f4210d03b5962b6802006aadb",
        "Happenings/27/noise.wav": "58208747318397d292f651e5d3e4819a597551fd8d015c42667fb439bcc8065a",
        "Happenings/28/texture.wav": "465804c3eb626e6d340229a4371c5f70af2755871a4a3474588c530a5717299a",
        "Happenings/29/texture.wav": "ca594fb30379aba4de78602acde4439946083b2d39a2257c8df91d55538446c8",
        "Happenings/30/texture.wav": "7abfe1120132697ea62a39d74aac95355161903f273ca5d8700383fbdb128e1a",
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
