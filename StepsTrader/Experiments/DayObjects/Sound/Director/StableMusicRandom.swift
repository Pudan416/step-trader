#if DEBUG || INTERNAL_BUILD
struct StableMusicRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64, domain: MusicSeedDomain) {
        state = seed ^ Self.fnv1a64(domain.rawValue)
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func nextInt(upperBound: Int) -> Int? {
        guard upperBound > 0 else { return nil }
        guard upperBound > 1 else { return 0 }

        let bound = UInt64(upperBound)
        let rejectionThreshold = (0 &- bound) % bound
        var value = nextUInt64()
        while value < rejectionThreshold {
            value = nextUInt64()
        }
        return Int(value % bound)
    }

    mutating func nextUnitDouble() -> Double {
        Double(nextUInt64() >> 11) / 9_007_199_254_740_992
    }

    mutating func bernoulli(probability: Double) -> Bool {
        guard probability.isFinite, probability > 0 else { return false }
        guard probability < 1 else { return true }
        return nextUnitDouble() < probability
    }

    mutating func shuffled<Element>(_ values: [Element]) -> [Element] {
        guard values.count > 1 else { return values }

        var result = values
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            guard let selectedIndex = nextInt(upperBound: index + 1) else { continue }
            result.swapAt(index, selectedIndex)
        }
        return result
    }

    mutating func choice<Element>(from values: [Element]) -> Element? {
        guard let index = nextInt(upperBound: values.count) else { return nil }
        return values[index]
    }

    private static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
#endif
