import Foundation

enum ModernPaletteCategory: String, CaseIterable, Codable, Hashable {
    case pastel
    case vintage
    case retro
    case neon
    case warm
    case cold
    case spring
    case summer
    case fall
    case winter

    var displayName: String {
        switch self {
        case .pastel: "Pastel"
        case .vintage: "Vintage"
        case .retro: "Retro"
        case .neon: "Neon"
        case .warm: "Warm"
        case .cold: "Cold"
        case .spring: "Spring"
        case .summer: "Summer"
        case .fall: "Fall"
        case .winter: "Winter"
        }
    }
}

struct ModernPalette: Equatable {
    let code: String
    let categories: Set<ModernPaletteCategory>

    var hexes: [String] {
        stride(from: 0, to: code.count, by: 6).map { offset in
            let start = code.index(code.startIndex, offsetBy: offset)
            let end = code.index(start, offsetBy: 6)
            return "#" + code[start..<end].uppercased()
        }
    }
}

enum ModernPaletteSelection {
    static let all = Set(ModernPaletteCategory.allCases)

    static func decode(_ rawValue: String) -> Set<ModernPaletteCategory> {
        let decoded = Set(
            rawValue.split(separator: ",").compactMap {
                ModernPaletteCategory(rawValue: String($0))
            }
        )
        return decoded.isEmpty ? all : decoded
    }

    static func encode(_ categories: Set<ModernPaletteCategory>) -> String {
        guard !categories.isEmpty, categories != all else { return "" }
        return ModernPaletteCategory.allCases
            .filter(categories.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func toggling(
        _ category: ModernPaletteCategory,
        in categories: Set<ModernPaletteCategory>
    ) -> Set<ModernPaletteCategory> {
        if categories == all { return [category] }

        var updated = categories
        if updated.contains(category) {
            updated.remove(category)
        } else {
            updated.insert(category)
        }
        return updated.isEmpty ? all : updated
    }
}

enum ModernPaletteCatalog {
    /// Snapshot of Color Hunt's 40 most popular palettes in each supported
    /// category, captured 2026-08-24 from https://colorhunt.co/. Duplicate
    /// color sequences merge tags. The app never accesses Color Hunt at runtime.
    static let all: [ModernPalette] = [
        ModernPalette(code: "000000233d4dfe7f2deaecf0", categories: [.retro]),
        ModernPalette(code: "0000005682b1739ec9ffe8db", categories: [.winter]),
        ModernPalette(code: "0000009929eacc66dafaeb92", categories: [.neon]),
        ModernPalette(code: "0000009929eaff5fcffaeb92", categories: [.neon]),
        ModernPalette(code: "000000cf0f47ff0b55ffdede", categories: [.neon]),
        ModernPalette(code: "000000f72798f57d1febf400", categories: [.neon]),
        ModernPalette(code: "000080ff00009e2a3a3a2525", categories: [.retro]),
        ModernPalette(code: "000957344cb7577bc1ffeb00", categories: [.neon]),
        ModernPalette(code: "001bb70046ffff8040f5f1dc", categories: [.summer]),
        ModernPalette(code: "003049d62828f77f00fcbf49", categories: [.warm]),
        ModernPalette(code: "0046ff73c8d2f5f1dcff9013", categories: [.summer]),
        ModernPalette(code: "00546101879000b7b5f4f4f4", categories: [.cold]),
        ModernPalette(code: "0054610c7779249e943bc1a8", categories: [.cold]),
        ModernPalette(code: "007dccffb900d10056b2054c", categories: [.retro]),
        ModernPalette(code: "007f734ccd99ffc700fff455", categories: [.neon]),
        ModernPalette(code: "00e0ba91008dff3483ffcf00", categories: [.retro, .neon]),
        ModernPalette(code: "00f7ffb0fffaff0087ff7db0", categories: [.neon]),
        ModernPalette(code: "00ff9cb6ffa1feffa7ffe700", categories: [.neon]),
        ModernPalette(code: "016b6170b2b29ecfd4e5e9c5", categories: [.cold]),
        ModernPalette(code: "03aed2f8de22f45b26d12052", categories: [.neon]),
        ModernPalette(code: "05921206d0019bec00f3ff90", categories: [.neon]),
        ModernPalette(code: "061e291d546d5f9598f3f4f4", categories: [.cold]),
        ModernPalette(code: "08cb00253900000000eeeeee", categories: [.neon]),
        ModernPalette(code: "091413285a48408a71b0e4cc", categories: [.cold, .winter]),
        ModernPalette(code: "0915401b2cc17692ffabd2fa", categories: [.winter]),
        ModernPalette(code: "093c5d3b75976fd1d75df8d8", categories: [.cold, .winter]),
        ModernPalette(code: "09637e0883957ab2b2ebf4f6", categories: [.cold]),
        ModernPalette(code: "0a2947f3e4c9d3d4c08b5e3c", categories: [.vintage]),
        ModernPalette(code: "0a7c6ef59e0bff6b35fafafa", categories: [.vintage]),
        ModernPalette(code: "0b09092e4540408175b5b9f0", categories: [.winter]),
        ModernPalette(code: "0b1849124d1ce4b028ebede3", categories: [.retro, .winter]),
        ModernPalette(code: "0b2d720992c20ac4e0f6e7bc", categories: [.cold, .winter]),
        ModernPalette(code: "0c0c0c481e149b3922f2613f", categories: [.fall]),
        ModernPalette(code: "0c2b4e1a3d641d546cf4f4f4", categories: [.cold]),
        ModernPalette(code: "0c2c55296374629fadededce", categories: [.cold, .winter]),
        ModernPalette(code: "0d1a631a2ca32845d6f68048", categories: [.cold]),
        ModernPalette(code: "0e21a04d2fb2b153d7f375c2", categories: [.cold]),
        ModernPalette(code: "0f28541c4d8d4988c4bde8f5", categories: [.cold]),
        ModernPalette(code: "0f3040464858a56f63d99b7f", categories: [.warm]),
        ModernPalette(code: "1118444b56947288aeeae0cf", categories: [.cold]),
        ModernPalette(code: "11224ef87b1bcbd99beeeeee", categories: [.retro]),
        ModernPalette(code: "112e814647ae4382dfaaccd6", categories: [.cold]),
        ModernPalette(code: "113f6734699a58a0c8fdf5aa", categories: [.winter]),
        ModernPalette(code: "121358232f722f578a36ada3", categories: [.cold]),
        ModernPalette(code: "133458838921d99b21faf7bb", categories: [.vintage, .fall]),
        ModernPalette(code: "15173d982598e491c9f1e9e9", categories: [.cold]),
        ModernPalette(code: "16c47fffd65aff9d23f93827", categories: [.neon]),
        ModernPalette(code: "170c79efe3ca56b6c68acbd0", categories: [.vintage]),
        ModernPalette(code: "1a3263547792fab95be8e2db", categories: [.winter]),
        ModernPalette(code: "1b3c53234c6a456882d2c1b6", categories: [.cold]),
        ModernPalette(code: "1b3c53234c6a456882e3e3e3", categories: [.cold]),
        ModernPalette(code: "1b3c53456882d2c1b6f9f3ef", categories: [.winter]),
        ModernPalette(code: "1d4533f7eae0f9d2ba5e3122", categories: [.vintage]),
        ModernPalette(code: "1f6f5f2fa0846fcf97eeeeee", categories: [.cold]),
        ModernPalette(code: "2029404b40389a8678caaa98", categories: [.vintage]),
        ModernPalette(code: "2057814f959d98d2c0f6f8d5", categories: [.winter]),
        ModernPalette(code: "211951836fff15f5baf0f3ff", categories: [.neon]),
        ModernPalette(code: "21344854779294b4c1eae0cf", categories: [.winter]),
        ModernPalette(code: "21344854779294b4c1ecefca", categories: [.winter]),
        ModernPalette(code: "213c516594b1ddaed3eeeeee", categories: [.pastel]),
        ModernPalette(code: "218dae2bbbd7fce59affd758", categories: [.summer]),
        ModernPalette(code: "237227519a66ffaa00ffd786", categories: [.retro]),
        ModernPalette(code: "249d8fe9c46ae76f51fdf0d5", categories: [.pastel]),
        ModernPalette(code: "254f22a03a13f5824aede4c2", categories: [.warm]),
        ModernPalette(code: "26355daf47d2ff8f00ffdb00", categories: [.neon]),
        ModernPalette(code: "280905740a03c3110ce6501b", categories: [.warm]),
        ModernPalette(code: "281c594e8d9c85c79aedf7bd", categories: [.cold, .winter]),
        ModernPalette(code: "2936814274d995ccddd0e7e6", categories: [.cold]),
        ModernPalette(code: "2c2c2c853953612d53f3f4f4", categories: [.vintage]),
        ModernPalette(code: "2c5ead1591dc4bb8fac4e2f5", categories: [.cold]),
        ModernPalette(code: "2d3c5994a378e5ba41d1855c", categories: [.pastel, .winter]),
        ModernPalette(code: "2e29102c5745ebe3a7eb7d00", categories: [.vintage]),
        ModernPalette(code: "2f2fe4162e931a1953080616", categories: [.cold]),
        ModernPalette(code: "30afff92eeffd8ffc5c4f7ca", categories: [.neon, .summer]),
        ModernPalette(code: "321e4843637e65dcd5d9fff4", categories: [.cold]),
        ModernPalette(code: "333d6d723ec3ffcf95fff0d9", categories: [.retro]),
        ModernPalette(code: "3368a066a3bfc8dfdbf2efe7", categories: [.pastel]),
        ModernPalette(code: "34673979ae6f9fcb98f2edc2", categories: [.summer]),
        ModernPalette(code: "3558727aaace9cd5fff7f8f0", categories: [.cold]),
        ModernPalette(code: "35858e7da78cc2d099e6eec9", categories: [.cold]),
        ModernPalette(code: "3601858f0177de1a58f4b342", categories: [.retro]),
        ModernPalette(code: "362f4f5b23ff008bffe4ff30", categories: [.neon]),
        ModernPalette(code: "37353e44444e715a5ad3dad9", categories: [.winter]),
        ModernPalette(code: "3852b45e7ac4f3be7af08d39", categories: [.vintage]),
        ModernPalette(code: "39b1d1d6fb61f6850cde3e3e", categories: [.neon]),
        ModernPalette(code: "3b02706f00ffe9b3fbfff1f1", categories: [.neon]),
        ModernPalette(code: "3c467b50589c636ccb6e8cfb", categories: [.cold]),
        ModernPalette(code: "410445a5158cff2df1f6dc43", categories: [.neon]),
        ModernPalette(code: "41431baeb784e3dbbbf8f3e1", categories: [.summer]),
        ModernPalette(code: "41a67e05339c1055c9e5c95f", categories: [.winter]),
        ModernPalette(code: "427ab5406aaff7dd7dffe8be", categories: [.summer]),
        ModernPalette(code: "4300ff0065f800caff00ffde", categories: [.neon]),
        ModernPalette(code: "434e78607b8ff7e396e97f4a", categories: [.pastel]),
        ModernPalette(code: "43766cf8fae5b1947076453b", categories: [.fall]),
        ModernPalette(code: "443199792ca2c13383e05454", categories: [.retro]),
        ModernPalette(code: "4506938c00ffff3f7fffc400", categories: [.retro, .neon]),
        ModernPalette(code: "45282957595be8d1c5f3e8df", categories: [.winter]),
        ModernPalette(code: "454040605b51d8d365e6f082", categories: [.retro]),
        ModernPalette(code: "462c7d831c91d552a3ff70bf", categories: [.retro]),
        ModernPalette(code: "4635b1b771e5aeea94fffbca", categories: [.neon]),
        ModernPalette(code: "464b71118ab27cd5c7f2f2ed", categories: [.cold]),
        ModernPalette(code: "4684329ad872ffef91ffa02e", categories: [.summer]),
        ModernPalette(code: "47347253629e87bac3d6f4ed", categories: [.cold]),
        ModernPalette(code: "476eae48b3afa7e399f6ff99", categories: [.neon]),
        ModernPalette(code: "4a102a85193cc5172efcf259", categories: [.neon]),
        ModernPalette(code: "4a44666eadbc9fcbadf1f7d4", categories: [.winter]),
        ModernPalette(code: "4b142617433f558467efeabb", categories: [.winter]),
        ModernPalette(code: "4c4b16898121e6c767f87a53", categories: [.fall]),
        ModernPalette(code: "4d2b8c85409deea727ffef5f", categories: [.retro]),
        ModernPalette(code: "4e1f6e3e3e7545a9a998e8de", categories: [.cold, .winter]),
        ModernPalette(code: "4e56c09b5de0d78feefdcffa", categories: [.cold]),
        ModernPalette(code: "52357b5459ac648db3b2d8ce", categories: [.winter]),
        ModernPalette(code: "524646a8a492fcf2e5ec5b38", categories: [.vintage, .warm]),
        ModernPalette(code: "546b4199ad7adcccacfff8ec", categories: [.pastel]),
        ModernPalette(code: "5749649f8383c8aaaaffdab3", categories: [.pastel, .warm]),
        ModernPalette(code: "576a8fb7bdf7fff8deff7444", categories: [.pastel]),
        ModernPalette(code: "59ac773a6f43fdaaaaffd5d5", categories: [.spring]),
        ModernPalette(code: "59b292ffc94dfae7cbfa6781", categories: [.retro]),
        ModernPalette(code: "5a9cb5face68faac68fa6868", categories: [.pastel]),
        ModernPalette(code: "5b7e3ca2cb8be8f5bdc44545", categories: [.retro]),
        ModernPalette(code: "5b7e3cffd65aff9d23ea5252", categories: [.vintage]),
        ModernPalette(code: "5dd3b66e5034cdb885efe1b5", categories: [.warm]),
        ModernPalette(code: "5e00069b0f06d53e0feed9b9", categories: [.warm]),
        ModernPalette(code: "5e244eaa1c41e68457ffe8b4", categories: [.warm]),
        ModernPalette(code: "5eabd6fefbc7ffb4b4e14434", categories: [.spring]),
        ModernPalette(code: "5f6f52a9b388fefae0b99470", categories: [.fall]),
        ModernPalette(code: "5f8b4cffddabff9a9a945034", categories: [.spring]),
        ModernPalette(code: "601d49bd5579ea9d9dffebb8", categories: [.warm]),
        ModernPalette(code: "60241e95271db34a44e77b49", categories: [.warm]),
        ModernPalette(code: "60465273555797866ad29f80", categories: [.winter]),
        ModernPalette(code: "607456eee0ccba6a4c7b2525", categories: [.vintage, .fall]),
        ModernPalette(code: "62109fdc0e0efe6244ffdeb9", categories: [.retro]),
        ModernPalette(code: "622b14995f2f978f66e4d6a9", categories: [.vintage, .warm]),
        ModernPalette(code: "6367ff8494ffc9beffffdbfd", categories: [.cold]),
        ModernPalette(code: "638c6de7fbb4df6d2dc84c05", categories: [.fall]),
        ModernPalette(code: "640d5fd91656ee66a6ffeb55", categories: [.neon]),
        ModernPalette(code: "6420aaff3ea5ff7ed4ffb5da", categories: [.neon]),
        ModernPalette(code: "65928788bda4b1d3b9e6f2dd", categories: [.pastel]),
        ModernPalette(code: "6aece126ccc2fff57effb76c", categories: [.neon, .summer]),
        ModernPalette(code: "6c0345dc6b19f7c566fff8dc", categories: [.fall]),
        ModernPalette(code: "6dc3bb393d7e5459acf2aebb", categories: [.retro, .cold]),
        ModernPalette(code: "6e026fabdadcf1e6c9fa891a", categories: [.retro]),
        ModernPalette(code: "6e1a37ae244872baa9d5e7b5", categories: [.vintage, .winter]),
        ModernPalette(code: "6f4e37a67b5becb176fed8b1", categories: [.fall]),
        ModernPalette(code: "706233b0926ae1c78ffae7c9", categories: [.fall]),
        ModernPalette(code: "706d54a08963c9b194dbdbdb", categories: [.fall]),
        ModernPalette(code: "70ffd2fffc8cffcc4dff9137", categories: [.neon, .summer]),
        ModernPalette(code: "722f99c5c1c1fee7c8ff9292", categories: [.retro]),
        ModernPalette(code: "744577f0e9b6accfa384c5b1", categories: [.pastel, .vintage, .retro]),
        ModernPalette(code: "748873d1a980e5e0d8f8f8f8", categories: [.fall]),
        ModernPalette(code: "760031d51c39ff6060feec41", categories: [.warm, .summer]),
        ModernPalette(code: "767f9edaa464dec384e8ddb4", categories: [.pastel, .vintage]),
        ModernPalette(code: "769826a1cb35ffde4eff9d4d", categories: [.spring]),
        ModernPalette(code: "777c6db7b89fcbcbcbeeeeee", categories: [.winter]),
        ModernPalette(code: "778873a1bc98dccfc0fdf6ed", categories: [.pastel, .vintage]),
        ModernPalette(code: "7b542fb6771dff9d00ffcf71", categories: [.summer]),
        ModernPalette(code: "7c00fef9e400ffaf00f5004f", categories: [.neon]),
        ModernPalette(code: "7c444f9f5255e16a54f39e60", categories: [.fall]),
        ModernPalette(code: "7f2020869b7ec9caacf6f3eb", categories: [.vintage]),
        ModernPalette(code: "810b38f1e2d1dcc3aa541a1a", categories: [.warm]),
        ModernPalette(code: "81a6c6aacddcf3e3d0d2c4b4", categories: [.pastel]),
        ModernPalette(code: "84994fffe797fcb53bb45253", categories: [.summer]),
        ModernPalette(code: "84b179a2cb8bc7eabbe8f5bd", categories: [.pastel, .summer]),
        ModernPalette(code: "86a788fffdecffe2e2ffcfcf", categories: [.spring]),
        ModernPalette(code: "89ac46d3e671f8ed8cff8989", categories: [.spring]),
        ModernPalette(code: "8a5f41a77f60f3e4c9ccd67f", categories: [.vintage]),
        ModernPalette(code: "8a76508e977dece7d1dbcea5", categories: [.pastel, .warm, .fall]),
        ModernPalette(code: "8a8635aa2b1dcc561ef3cf7a", categories: [.fall]),
        ModernPalette(code: "8b1e2de63946f4d35e457b9d", categories: [.warm]),
        ModernPalette(code: "8b2626ef6905f1e5a1486c2f", categories: [.vintage]),
        ModernPalette(code: "8cb9bdfefbf6ecb159b67352", categories: [.fall]),
        ModernPalette(code: "8ce4fffeee91ffa239ff5656", categories: [.neon]),
        ModernPalette(code: "8fa28ac7d3c0f7f4edc8a96b", categories: [.pastel, .vintage, .fall]),
        ModernPalette(code: "914f1edeac80f7dcb9b5c18e", categories: [.fall]),
        ModernPalette(code: "91c6bc4b9da9f6f3c2e37434", categories: [.summer]),
        ModernPalette(code: "932f67d92c54dddeab8abb6c", categories: [.spring]),
        ModernPalette(code: "934761ad5c7172baa9d5e7b5", categories: [.vintage]),
        ModernPalette(code: "97a87aa8bba3fcf9eaffa239", categories: [.pastel, .summer]),
        ModernPalette(code: "9cc6dbfcf6d9cf4b00ddba7d", categories: [.summer]),
        ModernPalette(code: "9ed3dcfefd99fcb7c7ca6180", categories: [.vintage, .spring]),
        ModernPalette(code: "9fa1ffb5baffaee2ffd9f9df", categories: [.pastel]),
        ModernPalette(code: "a0937de7d4b5f6e6cbb6c7aa", categories: [.fall]),
        ModernPalette(code: "a3dc9adee791fff9bdffd6ba", categories: [.spring]),
        ModernPalette(code: "a47251dd9e59f0d8a1dcf0c3", categories: [.vintage]),
        ModernPalette(code: "a4b885d46d25fdc086fff6a1", categories: [.pastel]),
        ModernPalette(code: "a5b68decdfccfcfaeeda8359", categories: [.fall]),
        ModernPalette(code: "a5c89efffbb1d8e983aeb877", categories: [.summer]),
        ModernPalette(code: "a8bba3b87c4cc4a484f7f1de", categories: [.fall]),
        ModernPalette(code: "a8df8ef0ffdfffd8dfffaab8", categories: [.spring]),
        ModernPalette(code: "a98b76bfa28cf3e4c9babf94", categories: [.pastel]),
        ModernPalette(code: "aaffc767c090215b63124170", categories: [.cold]),
        ModernPalette(code: "b17f59a5b68dc1cfa1ede8dc", categories: [.winter]),
        ModernPalette(code: "b1d690feec37ffa24cff77b7", categories: [.spring]),
        ModernPalette(code: "b5e18bf0ffc2eae6bc28396c", categories: [.vintage]),
        ModernPalette(code: "b77466ffe1afe2b59a957c62", categories: [.fall]),
        ModernPalette(code: "b7e5cd8abeb9305669c1785a", categories: [.winter]),
        ModernPalette(code: "b8db80f7f6d3ffe4eff39eb6", categories: [.spring]),
        ModernPalette(code: "ba5a5af7e49ba4ce8b86bcbd", categories: [.pastel]),
        ModernPalette(code: "bbe0ef161e54f16d34ff986a", categories: [.retro]),
        ModernPalette(code: "bc9f8bb5cfb7cadabfe7e8d8", categories: [.fall]),
        ModernPalette(code: "bd4444f1dec473976a677e61", categories: [.pastel]),
        ModernPalette(code: "be1a1ad0311ef7d87ff8ebab", categories: [.warm]),
        ModernPalette(code: "bf092f13244016476a3b9797", categories: [.winter]),
        ModernPalette(code: "bf1a1aff6c0cffe08f060771", categories: [.retro]),
        ModernPalette(code: "bf92646f826abbd8a3f0f1c5", categories: [.fall]),
        ModernPalette(code: "bfc6c4e8e2d86f8f72f2a65a", categories: [.pastel]),
        ModernPalette(code: "bfecffcdc1fffff6e3ffccea", categories: [.spring]),
        ModernPalette(code: "c00707ff4400ffb33f134e8e", categories: [.retro]),
        ModernPalette(code: "c0e1d2e5eee4f6f4e8dc9b9b", categories: [.pastel]),
        ModernPalette(code: "c1ebe9fff7c5f4ae524f252e", categories: [.vintage, .summer]),
        ModernPalette(code: "c3ff93ffdb5cffaf61ff70ab", categories: [.neon]),
        ModernPalette(code: "c40c0cff6500cc561ef6ce71", categories: [.warm]),
        ModernPalette(code: "c7db9cfff0bdfdab9ee50046", categories: [.spring]),
        ModernPalette(code: "cadcaee1e9c9eda35afee8d9", categories: [.spring]),
        ModernPalette(code: "cb9df0f0c1e1fddbbbfff9bf", categories: [.spring]),
        ModernPalette(code: "d2ff7273ec8b54c39215b392", categories: [.neon]),
        ModernPalette(code: "d6d46df4dfb6de8f5f9a4444", categories: [.fall]),
        ModernPalette(code: "d90000ffea938db355000000", categories: [.retro]),
        ModernPalette(code: "daddb1b3a492bfb29ed6c7ae", categories: [.fall]),
        ModernPalette(code: "db1a1afff6f68cc7c42c687b", categories: [.retro, .winter]),
        ModernPalette(code: "dca47cffd3b6fcf8f3698474", categories: [.fall]),
        ModernPalette(code: "df301cff9100fff1d100b7cd", categories: [.retro]),
        ModernPalette(code: "e05454c13383792ca2443199", categories: [.vintage, .warm]),
        ModernPalette(code: "e2852ef5c857ffee91abe0f0", categories: [.summer]),
        ModernPalette(code: "e2a16ffff0ddd1d3d486b0bd", categories: [.fall]),
        ModernPalette(code: "e3f2fd90caf92196f30d47a1", categories: [.cold]),
        ModernPalette(code: "e4e0e1d6c0b3ab886d493628", categories: [.fall]),
        ModernPalette(code: "e5cb90fff3c834a99d458393", categories: [.vintage, .summer]),
        ModernPalette(code: "e73f1efb6c00f9b637ffdd9c", categories: [.warm]),
        ModernPalette(code: "e87f24ffc81efefddf73a5ca", categories: [.summer]),
        ModernPalette(code: "e89951ecb65ff0e76fa5cf83", categories: [.warm, .summer]),
        ModernPalette(code: "e8edf22c3947547a95c2a56d", categories: [.vintage]),
        ModernPalette(code: "e9ff97ffd18effa38fff7ee2", categories: [.neon]),
        ModernPalette(code: "ea7b7bd253539e3b3bffead3", categories: [.pastel]),
        ModernPalette(code: "eaefefbfc9d125343fff9b51", categories: [.retro]),
        ModernPalette(code: "ec6530ffae6effe3e38fdddf", categories: [.vintage]),
        ModernPalette(code: "ececec84934a656d3f492828", categories: [.winter]),
        ModernPalette(code: "ecf4e8cbf3bbabe7b293bfc7", categories: [.summer]),
        ModernPalette(code: "ede9e6c9996b5c4f4a5c766d", categories: [.vintage, .winter]),
        ModernPalette(code: "eeedebe6b9a69391852f3645", categories: [.fall]),
        ModernPalette(code: "eefabda0d5856984a9263b6a", categories: [.cold]),
        ModernPalette(code: "efece38fabd44a70a9000000", categories: [.cold, .winter]),
        ModernPalette(code: "f075aef7db91fffdce9bc264", categories: [.spring, .summer]),
        ModernPalette(code: "f1e5d1dbb5b5c39898987070", categories: [.fall]),
        ModernPalette(code: "f1efecd4c9be123458030303", categories: [.winter]),
        ModernPalette(code: "f259125c3e94412b6b211832", categories: [.retro]),
        ModernPalette(code: "f26076ff9760ffd150458b73", categories: [.retro]),
        ModernPalette(code: "f2eae0b4d3d9bda6ce9b8ec7", categories: [.pastel]),
        ModernPalette(code: "f3eeeaebe3d5b0a695776b5d", categories: [.fall]),
        ModernPalette(code: "f3f4f4853953612d532c2c2c", categories: [.winter]),
        ModernPalette(code: "f4e7e1ff9b45d5451b521c0d", categories: [.fall]),
        ModernPalette(code: "f4f754e9d484cfadc14e61d3", categories: [.retro, .summer]),
        ModernPalette(code: "f599c6ffea887dccad4d6787", categories: [.pastel, .vintage, .spring]),
        ModernPalette(code: "f5ad189e1c60811844561530", categories: [.retro]),
        ModernPalette(code: "f5d2d2f8f7babde3c3a3ccda", categories: [.spring, .summer]),
        ModernPalette(code: "f5eedc27548a183b4edda853", categories: [.winter]),
        ModernPalette(code: "f5eedd7ae2cf077a7d06202b", categories: [.winter]),
        ModernPalette(code: "f5efe6e8dfca6d94c5cbdceb", categories: [.summer]),
        ModernPalette(code: "f5f2f2feb05d5a7acd2b2a2a", categories: [.retro]),
        ModernPalette(code: "f5f5dcfbc02dff8f00c62828", categories: [.warm]),
        ModernPalette(code: "f5f5f576abae303841ff5722", categories: [.retro]),
        ModernPalette(code: "f5f5f5dff1f1bbd5daff0000", categories: [.retro]),
        ModernPalette(code: "f5fbe6215e61233d4dfe7f2d", categories: [.winter]),
        ModernPalette(code: "f63049d027528a244b111f35", categories: [.warm]),
        ModernPalette(code: "f6f0d7c5d89d9cab8489986d", categories: [.pastel, .spring, .summer]),
        ModernPalette(code: "f72c5bff748ba7d477e4f1ac", categories: [.spring]),
        ModernPalette(code: "f7cfd8f4f8d3a6d6d68e7dbe", categories: [.spring]),
        ModernPalette(code: "f7cfd8f4f8d3a6f1e073c7c7", categories: [.spring]),
        ModernPalette(code: "f7f1deb0ba999d66384e220f", categories: [.vintage, .warm]),
        ModernPalette(code: "f875aafdedededfff0aedefc", categories: [.spring]),
        ModernPalette(code: "f8b2b2af719d8b639b403d88", categories: [.pastel, .warm]),
        ModernPalette(code: "f8f4ecff8fb7e83c9143334c", categories: [.retro]),
        ModernPalette(code: "f9b2d7cfecf3daf9def6ffdc", categories: [.pastel, .spring]),
        ModernPalette(code: "f9c0abf4e0afa8cd89355f2e", categories: [.spring]),
        ModernPalette(code: "f9e8a2b4e1eb95bdd778a4cb", categories: [.pastel, .summer]),
        ModernPalette(code: "fa5c5cfd8a6bfec288fbef76", categories: [.warm, .summer]),
        ModernPalette(code: "fae251d75656bd114aeeeeee", categories: [.warm]),
        ModernPalette(code: "faf7f0d8d2c2b174574a4947", categories: [.fall]),
        ModernPalette(code: "fbdb93be5b508a2d3b641b2e", categories: [.fall]),
        ModernPalette(code: "fbe4d6261fb31611790c0950", categories: [.winter]),
        ModernPalette(code: "fbefefffe2e2f5cbcbc5b3d3", categories: [.pastel]),
        ModernPalette(code: "fbf5a7ff97d0ff62bbb331f1", categories: [.spring]),
        ModernPalette(code: "fcd8cdfeebf6ebd6fb687fe5", categories: [.spring]),
        ModernPalette(code: "fcf9eabadfdbffa4a4ffbdbd", categories: [.spring]),
        ModernPalette(code: "fcffc1ffe893fbb4a5fb9ec6", categories: [.spring]),
        ModernPalette(code: "fdeb9e7ae2cf077a7d06202b", categories: [.retro, .cold]),
        ModernPalette(code: "fdf4afa5e9dd6fbeb234908b", categories: [.summer]),
        ModernPalette(code: "fdf4d2b0cde6a290b7946d6d", categories: [.pastel, .vintage]),
        ModernPalette(code: "fe5d26f2c078faedcac1dbb3", categories: [.spring]),
        ModernPalette(code: "fe81d4faacbffbc3c1ffeabb", categories: [.pastel, .warm]),
        ModernPalette(code: "fe9ec7f9f6c489d4ff44acff", categories: [.spring]),
        ModernPalette(code: "fed24ffff449b2d9597ec151", categories: [.summer]),
        ModernPalette(code: "fef2a0f3cd97e98b50bc4f4f", categories: [.warm]),
        ModernPalette(code: "ff204ea0153e5d0e4100224d", categories: [.neon]),
        ModernPalette(code: "ff2dd1fdffb84dffbe63c8ff", categories: [.neon]),
        ModernPalette(code: "ff3e9bff88ba3a8b9566d0bc", categories: [.retro]),
        ModernPalette(code: "ff3f33ffe6e1075b5e9fc87e", categories: [.spring]),
        ModernPalette(code: "ff5a5aff8b5affa95affd45a", categories: [.warm]),
        ModernPalette(code: "ff6a1cffda62ffae56f5788b", categories: [.warm]),
        ModernPalette(code: "ff76cefdffc294ffd8a3d8ff", categories: [.neon]),
        ModernPalette(code: "ff788dffdadafff2f2165823", categories: [.spring]),
        ModernPalette(code: "ff7f11acbfa4e2e8ce262626", categories: [.warm]),
        ModernPalette(code: "ff80c7ffbda3ffe1bbfaffc4", categories: [.spring]),
        ModernPalette(code: "ff84baffdf8299c2ffffefe3", categories: [.vintage]),
        ModernPalette(code: "ff9a86ffb399ffd6a6fff0be", categories: [.pastel]),
        ModernPalette(code: "ff9d9dffc5aaeef8cdbbf1d2", categories: [.spring]),
        ModernPalette(code: "ff9e20215e611d2128f4f2f2", categories: [.retro]),
        ModernPalette(code: "ffb6a6ffebd39bcec167a2c5", categories: [.pastel]),
        ModernPalette(code: "ffbe91ffddb0fffce1cfebff", categories: [.pastel, .vintage]),
        ModernPalette(code: "ffbf00fff78d467235283f24", categories: [.summer]),
        ModernPalette(code: "ffc349525ea75facd397dde9", categories: [.summer]),
        ModernPalette(code: "ffca95ff7873e22f808140dc", categories: [.warm]),
        ModernPalette(code: "ffcdb2ffb4a2e5989bb5828c", categories: [.fall]),
        ModernPalette(code: "ffd400ffc300ff8c00ff5f00", categories: [.warm, .summer]),
        ModernPalette(code: "ffd95fffefc8b8d576d70654", categories: [.spring]),
        ModernPalette(code: "ffdab3c8aaaa9f8383574964", categories: [.fall]),
        ModernPalette(code: "ffde4253cbf35478ff111fa2", categories: [.cold]),
        ModernPalette(code: "ffe97dffef9fe13f7cff537b", categories: [.warm]),
        ModernPalette(code: "ffeac5ffdbb56c4e31603f26", categories: [.fall]),
        ModernPalette(code: "ffedceffc193ff8383ff3737", categories: [.warm]),
        ModernPalette(code: "ffedfaffb8e0ec7fa9be5985", categories: [.spring]),
        ModernPalette(code: "ffeed6a5af79827148e8a07c", categories: [.pastel, .vintage, .summer]),
        ModernPalette(code: "fff2c6fff8deaac4f58ca9ff", categories: [.summer]),
        ModernPalette(code: "fff2e0c0c9eea2aadb898ac4", categories: [.winter]),
        ModernPalette(code: "fff4bfffbefbdc95ff8c56d4", categories: [.vintage]),
        ModernPalette(code: "fff58affbbe1dd7bdfb3bfff", categories: [.retro]),
        ModernPalette(code: "fff5f2f5babb568f87064232", categories: [.spring]),
        ModernPalette(code: "fff6de8bdfddf48f68ffe394", categories: [.vintage, .spring]),
        ModernPalette(code: "fff7cdfdc3a1fb9b8ff57799", categories: [.warm]),
        ModernPalette(code: "fff7d18b5dff6a42c2563a9c", categories: [.neon]),
        ModernPalette(code: "fff8e8f7eed3aab396674636", categories: [.fall]),
        ModernPalette(code: "fff8f0c085528c5a3c4b2e2b", categories: [.warm]),
        ModernPalette(code: "fff9d2ffebccbfddf08cc0eb", categories: [.pastel, .summer]),
        ModernPalette(code: "fffadcb6f500a4dd0098cd00", categories: [.neon]),
        ModernPalette(code: "fffaf0e03f4f81912ff8c463", categories: [.vintage]),
        ModernPalette(code: "fffbf1fff2d0ffb2b2e36a6a", categories: [.warm]),
        ModernPalette(code: "fffd8fb0ce884c763b043915", categories: [.summer]),
        ModernPalette(code: "fffdf1ffce99ff9644562f00", categories: [.warm]),
        ModernPalette(code: "ffff80ffaa80ff5580ff0080", categories: [.neon]),
        ModernPalette(code: "ffffecf1e4c3c6a969597e52", categories: [.fall]),
    ]

    /// Empty selection means every palette. Multiple selected categories form
    /// a union so choosing two tastes broadens the daily pool.
    static func palettes(
        matching categories: Set<ModernPaletteCategory>
    ) -> [ModernPalette] {
        guard !categories.isEmpty else { return all }
        return all.filter { !$0.categories.isDisjoint(with: categories) }
    }
}
