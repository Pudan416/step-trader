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
}
