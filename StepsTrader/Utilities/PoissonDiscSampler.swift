import CoreGraphics
import Foundation

/// Incremental Poisson-disc sampling, adapted from Bridson's algorithm.
///
/// Two entry points, one algorithm. `nextPoint` adds a single well-spaced
/// point — the shape the canvas needs, since it gains one element per tap.
/// `fill` produces a whole set at once, which is what a stipple texture needs.
///
/// Both take a `weight` field in `0...1`. It biases *where* points prefer to
/// land without ever hard-excluding a region, so a composition archetype or a
/// texture density gradient can be expressed as one closure.
enum PoissonDiscSampler {

    /// Candidates drawn around each anchor before moving on. Sampling happens
    /// once per tap or once per cached texture, so a generous count costs
    /// nothing and keeps the relaxed fallback rounds rare.
    private static let candidatesPerAnchor = 20

    /// Spacing is relaxed by this factor per round when the region is full.
    private static let relaxationFactor = 0.75
    private static let relaxationRounds = 3

    /// The first point sits near the middle, jittered by this fraction of the
    /// bounds so an opening element is not pinned dead centre.
    private static let firstPointJitter = 0.25

    /// How strongly `weight` competes with spacing. A candidate's score is
    /// `clearance * (weightFloor + (1 - weightFloor) * weight)`, so a
    /// zero-weight region is heavily discouraged but never impossible.
    private static let weightFloor = 0.05

    /// One more point respecting `minDistance` from `existing`, clamped to
    /// `bounds` and biased by `weight`. Never fails: if the region is
    /// saturated it relaxes the spacing, and failing that returns the
    /// best-scoring candidate it saw.
    static func nextPoint(
        existing: [CGPoint],
        bounds: CGRect,
        minDistance: Double,
        weight: (CGPoint) -> Double,
        using rng: inout SeededRNG
    ) -> CGPoint {
        guard !existing.isEmpty else {
            return firstPoint(in: bounds, weight: weight, using: &rng)
        }

        // Callers pass element positions whose array order can shift after a
        // sync merge. Sorting makes the layout independent of that order.
        let anchors = existing.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }

        var bestFallback = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestScore = -1.0

        for round in 0..<relaxationRounds {
            let radius = minDistance * pow(relaxationFactor, Double(round))
            var bestAccepted: CGPoint?
            var bestAcceptedScore = -1.0

            for anchor in anchors {
                for _ in 0..<candidatesPerAnchor {
                    let candidate = annulusCandidate(
                        around: anchor, radius: radius, using: &rng)
                    guard bounds.contains(candidate) else { continue }

                    let clearance = anchors
                        .map { Double(hypot($0.x - candidate.x, $0.y - candidate.y)) }
                        .min() ?? .infinity
                    let score = clearance * biased(weight(candidate))

                    if clearance >= radius, score > bestAcceptedScore {
                        bestAcceptedScore = score
                        bestAccepted = candidate
                    }
                    if score > bestScore {
                        bestScore = score
                        bestFallback = candidate
                    }
                }
            }

            // Take the best-weighted candidate of this round rather than the
            // first that clears the radius — that is what lets `weight`
            // actually steer the layout.
            if let accepted = bestAccepted { return accepted }
        }
        return bestFallback
    }

    /// A whole set of well-spaced points. Used by the stipple texture, where
    /// `weight` carries the density gradient across the form.
    static func fill(
        bounds: CGRect,
        minDistance: Double,
        maxPoints: Int,
        weight: (CGPoint) -> Double,
        using rng: inout SeededRNG
    ) -> [CGPoint] {
        guard maxPoints > 0 else { return [] }
        var points = [firstPoint(in: bounds, weight: weight, using: &rng)]

        // Frontier of points still worth growing from — the active list in
        // Bridson's formulation.
        var active = [0]

        while !active.isEmpty, points.count < maxPoints {
            let activeIndex = active.count - 1
            let anchor = points[active[activeIndex]]
            var placed = false

            for _ in 0..<candidatesPerAnchor {
                let candidate = annulusCandidate(
                    around: anchor, radius: minDistance, using: &rng)
                guard bounds.contains(candidate) else { continue }

                let clearance = points
                    .map { Double(hypot($0.x - candidate.x, $0.y - candidate.y)) }
                    .min() ?? .infinity
                guard clearance >= minDistance else { continue }

                // Weight thins the field rather than gating it, so a low-weight
                // region ends up sparse instead of empty.
                guard rng.nextDouble() < biased(weight(candidate)) else { continue }

                points.append(candidate)
                active.append(points.count - 1)
                placed = true
                break
            }

            if !placed { active.remove(at: activeIndex) }
        }
        return points
    }

    // MARK: - Helpers

    private static func biased(_ weight: Double) -> Double {
        let clamped = min(max(weight, 0), 1)
        return weightFloor + (1 - weightFloor) * clamped
    }

    private static func firstPoint(
        in bounds: CGRect,
        weight: (CGPoint) -> Double,
        using rng: inout SeededRNG
    ) -> CGPoint {
        var best = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestScore = -1.0
        for _ in 0..<candidatesPerAnchor {
            let candidate = CGPoint(
                x: bounds.midX + CGFloat(rng.nextDouble(in: -1...1))
                    * bounds.width * firstPointJitter,
                y: bounds.midY + CGFloat(rng.nextDouble(in: -1...1))
                    * bounds.height * firstPointJitter
            )
            guard bounds.contains(candidate) else { continue }
            let score = biased(weight(candidate))
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    private static func annulusCandidate(
        around anchor: CGPoint,
        radius: Double,
        using rng: inout SeededRNG
    ) -> CGPoint {
        let angle = rng.nextDouble(in: 0...(2 * .pi))
        // Annulus [radius, 2*radius) — the Bridson construction.
        let reach = radius * (1.0 + rng.nextDouble())
        return CGPoint(
            x: anchor.x + CGFloat(cos(angle) * reach),
            y: anchor.y + CGFloat(sin(angle) * reach)
        )
    }
}
