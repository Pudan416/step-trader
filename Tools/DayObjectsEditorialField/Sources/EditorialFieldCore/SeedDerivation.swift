import CryptoKit
import Foundation

public enum SeedDerivation {
    public static func daySeed(
        commit: String,
        nonce: String,
        suite: String,
        index: Int,
        collision: Int
    ) -> UInt64 {
        let input = [commit, nonce, suite, String(index), String(collision)]
            .joined(separator: "\u{001F}")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }

    static func uniqueSeed(
        commit: String,
        nonce: String,
        suite: String,
        index: Int,
        usedSeeds: Set<UInt64>
    ) -> (seed: UInt64, collision: Int) {
        var collision = 0
        while true {
            let seed = daySeed(
                commit: commit,
                nonce: nonce,
                suite: suite,
                index: index,
                collision: collision
            )
            if !usedSeeds.contains(seed) {
                return (seed, collision)
            }
            collision += 1
        }
    }
}
