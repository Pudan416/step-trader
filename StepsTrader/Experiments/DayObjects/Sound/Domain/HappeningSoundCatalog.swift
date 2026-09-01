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
        "Happenings/01/A5.wav": "e415c236f349f2a270ff9acc796e606e5b9c1f807b4287fe135845d49d44886f",
        "Happenings/01/C5.wav": "f52494e8eae4966d4dd6f909a92c74342b34d93e39d678c7522107e0ca51f8a6",
        "Happenings/01/DSharp5.wav": "da33d2781b31c2b1a7dfec14b8a162f942cc29809c3292af538c22abd8dba5e5",
        "Happenings/01/FSharp5.wav": "8a0f4f34fc91f6c07a4475086a1fa4ffbf353b61cc8afcb77dc172c2c5679170",
        "Happenings/02/A5.wav": "2423d88d5c727ca9641ba82e694d271f78e603380c87f1eeed82c3065ef71687",
        "Happenings/02/C5.wav": "87fffd74592ced99ff4761bc2a590d2e891e26bf239ba4087fa3fec8581ddd1e",
        "Happenings/02/DSharp5.wav": "90d18c52f5afe9bf10a5bedd4d55c0021c7f9211f12b40fc1f87b3b393ebc022",
        "Happenings/02/FSharp5.wav": "fffa09456ea34e00ab0dca40748d70b1d5912a09faaeafd0962c35736da3d136",
        "Happenings/03/A5.wav": "aa0410d0df3eb9a4dd6b2251a0bdce1abc1f7d1f268c7653d98c3a113ec03404",
        "Happenings/03/C5.wav": "0e43c3129781ea3ff2255be56d2a867e466b3aca2af189f6cb94c19223800faf",
        "Happenings/03/DSharp5.wav": "7f748c35e62437fa381a5662723f0f41c50f6843871fc9567e40ac5a12b94757",
        "Happenings/03/FSharp5.wav": "4021a6464051818a0ec0e05245e933654dffd830d5a3f694e26e4a84f64f167d",
        "Happenings/04/A5.wav": "b3a930e2eaa00073c1ab828bbcef524ed3f5970dfbbb2e6fd4d95cd7407c071d",
        "Happenings/04/C5.wav": "75ccc8149ddfc8c94b6bcfa171904d23a333f736f73d30fba7a34bf9464744c4",
        "Happenings/04/DSharp5.wav": "4e5a37ffa9acd75df9d2460e2bb0c0b4c86e8f50c7f148c55303ae8a2e75f93a",
        "Happenings/04/FSharp5.wav": "e1fd6adfc5afc6a77fddb2707874ccb67c7c3531934a6cd8e703c0403ae00b21",
        "Happenings/05/A5.wav": "de8102d86cf51a225092b8a8d5a9708448d2683ba76dbbba3bf0c9b32035b228",
        "Happenings/05/C5.wav": "7872cb1d146730226ab2da324d87f5fab1e0cc8208dcfc41b61f9980a47f207d",
        "Happenings/05/DSharp5.wav": "b391cc5a32e84e9001dff3eb0dfad2682819a7d69201cceaf63914d2ffd16096",
        "Happenings/05/FSharp5.wav": "608fa28c6336355257b06c427de03fad37f8d5f05c960bc5be3d9b18ea5fca1a",
        "Happenings/06/A5.wav": "17183a06bc4d426c7914e12b9633337829c379ddda07f8f854ff6adc2b691871",
        "Happenings/06/C5.wav": "7f8cca8bda9b78269dc6f314e53da979c73cf88cc5bfb07625d6ef39ed886a83",
        "Happenings/06/DSharp5.wav": "e7197095385d9e1fae2a13f818e3acf20ae1c916a40517d924b768cb63b60c4c",
        "Happenings/06/FSharp5.wav": "7c7ba862b1c89b8f7f92bb63290bfbdfcce8b6ed633e5f5ddc0759699c1db7a3",
        "Happenings/07/A4.wav": "1614db380aaab2950406553095f2a464d8bfd271101ac0095b3b78a2214ce00f",
        "Happenings/07/C4.wav": "37107532ec3ca1f21ed3650c5baf0efd1d356e1a2781ff037634e7bf169beb3c",
        "Happenings/07/DSharp4.wav": "d7ba9a5865cc7feb5d97e74bb2749753f9b5cb266a8c566a1022ae0ad4c02083",
        "Happenings/07/FSharp4.wav": "24bdccb137cb1613c49a47f5f7cff92f7f92c4149cab54fe7855a8b745d4b2fc",
        "Happenings/08/A4.wav": "b560f2b5b82e041e2deafc343dd02dc92f7caa7f183316c20d7b435773737d92",
        "Happenings/08/C4.wav": "bb683d3722b2af87c3b6dbf0a394b113af7948354103cdccd73c7b9fbef268f6",
        "Happenings/08/DSharp4.wav": "4c6e7a1f6463a59e17bc64d4a660058d0b391d7ae020cab30664538dbbe751d9",
        "Happenings/08/FSharp4.wav": "6024a7860f96a6abd3bbb125d8a4eb5bdf054e9989c693a589f6a422d36ef003",
        "Happenings/09/A4.wav": "2969e9748b02a279523840f35c440c606b80b080b7d5fcada23bcf46b9dc952a",
        "Happenings/09/C4.wav": "42b5097430908ed9c1d30c7604d864854e1bf2b2aa56c356b3a2aa55000499b5",
        "Happenings/09/DSharp4.wav": "e8acc6081dd7407d87fd17bc7d6b8851645a584d1041f5e3b7fac0c6a9acc74a",
        "Happenings/09/FSharp4.wav": "d3a0936cae86b2f486401b7f73fd9735c7945e0fa2db6cc6588cd93d796e1b36",
        "Happenings/10/A4.wav": "541ad3fd4f5a42201c70eba5698cf22e2fb114ef5cfa00cb8a573af939a3796e",
        "Happenings/10/C4.wav": "0ad4365515cccec3e27eb181dd634b6471d7ed070f0f5b1c892068e477a4ed88",
        "Happenings/10/DSharp4.wav": "87f3525d10e84ce9ab5946de476d505e4fbdf8319d5462ced20c06b90906bdc7",
        "Happenings/10/FSharp4.wav": "907b5a3054bdb017c1876d1d9eb73a7b3d1648e1746779c985473a44d8959101",
        "Happenings/11/A4.wav": "891c6c6a475e45a1c7202b3d931733bcbd6c1e95a958303e24bd0fe0e4bb1cc3",
        "Happenings/11/C4.wav": "2b7523fcabe601bcc318d7133b508cbd9e7c7a2eeaad2f85914c396aeb28f9da",
        "Happenings/11/DSharp4.wav": "eeb16fe86c593fbf52ad49e417c350fe352db77667161ca5a72334a09d1d5d72",
        "Happenings/11/FSharp4.wav": "a2f27895a7c7a1efb4ad55d181d1bf8e41bd87c4bc61b1b7543fbcc3f9f1e6eb",
        "Happenings/12/A4.wav": "7e5fac39ddfd26b55ef1467a90567251fb9b11635bc27f2ccb84e88cacc41749",
        "Happenings/12/C4.wav": "e13c68338532a7455d11b46979722a36dfffc85456bb770ddd3e626f57112e8f",
        "Happenings/12/DSharp4.wav": "906f0aaa15055070e09757e6c9d1005900a8a8894bcc625d3c563846daa90eca",
        "Happenings/12/FSharp4.wav": "c7ad3f93cde09a4144eba70849f6a213acd0d1a78ee3d3dc8378cb220fdd134b",
        "Happenings/13/A5.wav": "25a7ae41524cde41230b94857d01903dde4fff746c650052f931d0e37735fe19",
        "Happenings/13/C5.wav": "ed1397c59a253763475e8aac65df4e5ca1209223ee1c49e95066f32d62a2af11",
        "Happenings/13/DSharp5.wav": "eb90d7c0698ac20a22096b0653c704f2f9038a8aecca5090fc0ac33fdbaf55a7",
        "Happenings/13/FSharp5.wav": "2d16cb12332a2a0b484174cc1299f92da426913cbce4d182be666f337e81b2d9",
        "Happenings/14/A5.wav": "1a6090724d50d5b0288c70ddb1f5ba998b3eb59743e54e2d5c70c772f298cf88",
        "Happenings/14/C5.wav": "f4fe0449d2704b83c015b9862a7a3d8bd24537b69e2b5fed91be60368292e52d",
        "Happenings/14/DSharp5.wav": "9acd5da625e6b0993c1a043655eebfed740174db28adee392ff962c1f8cd54c0",
        "Happenings/14/FSharp5.wav": "57e85430d81b6e090b70d3f3a7f9a04b303ebb6683b8b1aa7c841cc5b51692c4",
        "Happenings/15/A5.wav": "c5f5f48ebedc9ea8180527bf7128c218955dc62158ad4ad3d48f27ffbb88b29e",
        "Happenings/15/C5.wav": "2e4d12a3e66cc98015e397b5e5a37cdaf9367ceeb9b31dc741426389f17d8634",
        "Happenings/15/DSharp5.wav": "c501168fe83e09773efa91a8c6fe7134c90f6de962b33e3d2a37b34d475dcb0e",
        "Happenings/15/FSharp5.wav": "82a8a3f0460d1735557acb5675ab767893771aeb7c024f089d0939097af29df9",
        "Happenings/16/A5.wav": "279051da460bfdefd6729bcb4b05616cb33d851a891d03d21ecb114b869034da",
        "Happenings/16/C5.wav": "66845036314d1adcba8b83763b620a159e6b3e2d2acfa4c02edb50c18cb700f9",
        "Happenings/16/DSharp5.wav": "dbd881f780e41661204b176af4da76cf96981a8272094f710c73576dda6fcccd",
        "Happenings/16/FSharp5.wav": "25b6c2b54ecd7d6dd12f0d35aaa102bb1d664f572226a81392902e9f0107be9e",
        "Happenings/17/A5.wav": "20b06bed09a814a4f0c24f612e7b697083d1e234475a037ab15113b740d1d1c0",
        "Happenings/17/C5.wav": "f62a4355b79cc6eb7b31f0667e58343dce4debfb0b3e659ab4940338616833c3",
        "Happenings/17/DSharp5.wav": "7d167513b1c7c90c54aa28af5d341151f7c2061415c8758a6ec677665158d8df",
        "Happenings/17/FSharp5.wav": "31524df467ffbf6eddaebbd36ee96a380f224bd8e3548ab775d4cdb4d12c474c",
        "Happenings/18/A5.wav": "2fb728d016555c6e9b3d53f8df6263e62396563f0d2b46b356a25bb63ea3db98",
        "Happenings/18/C5.wav": "215d620653b6439989bd768e66309d59e29099b2eb4274702155fa38bad59251",
        "Happenings/18/DSharp5.wav": "bcf18636e049b4259d704cc620b57fc9c942a0369c035d29524fb5e8a2559cb4",
        "Happenings/18/FSharp5.wav": "6f6d423f990d82433f1d3e2215da38aa5e4e0d9213bfdff72038014021106867",
        "Happenings/19/A3.wav": "c706d14a2276ab237fe845a9e560342859d97003146279aa39a710e46a3e1ce3",
        "Happenings/19/C3.wav": "d4bb57dd096909491a5243bbadbffbcb732f5106aa1f98f62daec7712645c0c4",
        "Happenings/19/DSharp3.wav": "accea647e7969881e5bf47aa80ab61a668b88e5595fb4adc595b2b78b0139ed6",
        "Happenings/19/FSharp3.wav": "2e7f95098e798a63b5419b3fc441ee7773b8836c5b0403b67749f537cbc6fe6d",
        "Happenings/20/A3.wav": "60c578290240aa28bcd002b422a50d4970581c873a4bfa095dfea0e156dfcd98",
        "Happenings/20/C3.wav": "361aabafe699be473384866cbf51d2c67237d094502b69f28c45526f1f89b165",
        "Happenings/20/DSharp3.wav": "3c3b4013eb759cbcdc721ffb6a028c57e0ebde49a68dd9c312174bfcb9406133",
        "Happenings/20/FSharp3.wav": "ff1c70f1eccde05b75c99d171b9ccf0f03263f8d049306d653a4c2742016a29d",
        "Happenings/21/A3.wav": "2238fa76d387e4bfc8b6ac187af0a15c7b62ece5d9f84ada62b3fb2de35045de",
        "Happenings/21/C3.wav": "97f411fcefe9897e7ed7b2a6b4a277e57aeef587bd566182a5d8e8626d1c5d74",
        "Happenings/21/DSharp3.wav": "ab442bc1b54904cf5f1e0ffb610547c8271ee2d1abb361cd4461857c7bb78a23",
        "Happenings/21/FSharp3.wav": "f589e53eae1d35cfbe6daaa17deb74a1bacb6bfb92654f733260cfa3884bc879",
        "Happenings/22/A3.wav": "917ade1e222d9728889aa5b237a8fe32a9ee892a5a95171e7b581171034dafcc",
        "Happenings/22/C3.wav": "accdfd406256fe8b0452528c6a6d35e32d161474da813f922fc287c45e432264",
        "Happenings/22/DSharp3.wav": "ff63e58889d06d74a6ceaeba7087bdb3e4d012a9ba202a76e2982077ffee36c3",
        "Happenings/22/FSharp3.wav": "9aecfd2db7edd9dae98b32475b842867800c363aba9fd3e8cac37b73a0defd5d",
        "Happenings/23/A3.wav": "700d43fdd94806b2605efa81ffbc60f880adfbc31244958a85c1d3447a51dc02",
        "Happenings/23/C3.wav": "acfb5053036b15809f5f685f6cfce6618ca833e7e292b5e084d8e9547c4c1206",
        "Happenings/23/DSharp3.wav": "e91071ab900f5d416e1e6b50e05e3b8f4c76ff7a7ef2fb4028231e49e4fc4dae",
        "Happenings/23/FSharp3.wav": "8a5df42e946df8d49cf082c380c8ee795cc516a0ee9127a3812418e696ecdad8",
        "Happenings/24/A3.wav": "ec54de20cb9ec7b33cf098b3fdc62a2c905adf1fe9fda01ce3d11bc7f2eac31f",
        "Happenings/24/C3.wav": "3d9d7545883aa3a00270fe3f9c28cf7f467e440f3a3aef01fa724ed7af72dd0f",
        "Happenings/24/DSharp3.wav": "873dfc196a5fab0b525f26b8dee1c322cc953ab576ca03729b93bbdc7ba0ffc6",
        "Happenings/24/FSharp3.wav": "daf16052dd690a9d76bda864dabeed8655dae3406695d75ecacf5de90eb56110",
        "Happenings/25/noise.wav": "6155c0a2c5d57d6a5dc6a92bc80626b82670644d99540d0e8c138046cda00fdc",
        "Happenings/26/noise.wav": "5fffcd44afbee21b2db6362a0555762789f44139be7aaf74e16a4815219c379f",
        "Happenings/27/noise.wav": "513c0c32b4e269553f482d812bdac8af78a4842569cabe9a10fc17a281a93d53",
        "Happenings/28/texture.wav": "3f8f053c824af12a53991ac7798e92013d7fa2fff8d53aba3172b9ce6935699e",
        "Happenings/29/texture.wav": "7f24b2eb5a0dcc1736837db5c11e870ab151a38aa020ae91f1e48630037ce916",
        "Happenings/30/texture.wav": "d2a32a7beeb08f4ad86a7d9d937b8f4f39d8ceef305e19189b819b4ec92908f6",
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
