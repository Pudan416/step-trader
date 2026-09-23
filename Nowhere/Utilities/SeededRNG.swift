import Foundation
import CoreGraphics

/// Deterministic SplitMix64-based pseudo-random number generator.
///
/// SplitMix64 is the same algorithm Java's `SplittableRandom` uses for its
/// initial mixing step. It has excellent avalanche characteristics so even
/// adjacent seeds (e.g. `n` and `n+1`) produce well-distributed output, and
/// every UInt64 seed (including 0) is valid.
///
/// Reference: <https://prng.di.unimi.it/splitmix64.c>
///
/// Use this struct anywhere we need reproducible pseudo-randomness — same
/// seed must always produce the same sequence across launches, devices, and
/// Swift versions. It conforms to `RandomNumberGenerator` so it can be
/// passed to `Int.random(in:using:)`, `Array.shuffled(using:)`, etc.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Double in [0, 1) using the top 53 bits (full mantissa precision).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat(range.lowerBound) + CGFloat(nextDouble()) * CGFloat(range.upperBound - range.lowerBound)
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        precondition(range.upperBound >= range.lowerBound, "SeededRNG.nextInt: invalid range")
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// A child generator isolated from the parent's call order.
    ///
    /// Without this, every consumer of a seed draws from one shared sequence:
    /// adding a single `next()` anywhere shifts everything downstream and every
    /// saved canvas regenerates differently. Giving each aspect — `"shape"`,
    /// `"placement"`, `"texture"`, `"palette"` — its own domain makes the
    /// streams independent, so a new parameter can be added without disturbing
    /// the rest.
    static func derived(from seed: UInt64, domain: StaticString) -> SeededRNG {
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        domain.withUTF8Buffer { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= prime
            }
        }
        return SeededRNG(seed: seed ^ hash)
    }
}
