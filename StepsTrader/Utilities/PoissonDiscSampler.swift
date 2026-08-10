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

    /// How strongly `weight` competes with spacing. A candidate's score is
    /// `min(clearance, radius) * (weightFloor + (1 - weightFloor) * weight)` —
    /// clearance is capped at the round's spacing requirement, not left
    /// unbounded, so a zero-weight region is heavily discouraged but never
    /// impossible, and extra emptiness beyond what spacing already demands
    /// can't outbid a real weight difference.
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
        var fallbackTies = 0

        for round in 0..<relaxationRounds {
            let radius = minDistance * pow(relaxationFactor, Double(round))
            var bestAccepted: CGPoint?
            var bestAcceptedScore = -1.0
            var acceptedTies = 0

            for anchor in anchors {
                for _ in 0..<candidatesPerAnchor {
                    let candidate = annulusCandidate(
                        around: anchor, radius: radius, using: &rng)
                    guard bounds.contains(candidate) else { continue }

                    let clearance = anchors
                        .map { Double(hypot($0.x - candidate.x, $0.y - candidate.y)) }
                        .min() ?? .infinity
                    // Saturate at `radius`: once a candidate clears the
                    // spacing requirement, extra emptiness stops earning
                    // credit. An unbounded clearance term made the rule
                    // "put the point in the largest empty gap" — weight
                    // could only nudge that choice, never override it, which
                    // is why every archetype's layout collapsed to the same
                    // near-uniform centroid regardless of its field.
                    let score = min(clearance, radius) * biased(weight(candidate))

                    // Saturation means many candidates in an open, near-flat
                    // field score *exactly* alike (all reach the `radius`
                    // cap). Always keeping the first tie seen would bias
                    // growth toward whichever anchor happens to sort first
                    // — measured as a real ~0.13 population centroid drift
                    // for a flat weight field, not sampling noise. Reservoir
                    // sampling picks uniformly among ties instead, so a flat
                    // field stays flat and only a real weight difference can
                    // move the layout.
                    if clearance >= radius {
                        if score > bestAcceptedScore {
                            bestAcceptedScore = score
                            bestAccepted = candidate
                            acceptedTies = 1
                        } else if score == bestAcceptedScore {
                            acceptedTies += 1
                            if rng.nextDouble() < 1.0 / Double(acceptedTies) {
                                bestAccepted = candidate
                            }
                        }
                    }
                    if score > bestScore {
                        bestScore = score
                        bestFallback = candidate
                        fallbackTies = 1
                    } else if score == bestScore {
                        fallbackTies += 1
                        if rng.nextDouble() < 1.0 / Double(fallbackTies) {
                            bestFallback = candidate
                        }
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
            // Bridson's formulation picks a random active point, not the most
            // recently added one. A LIFO pop grows the frontier depth-first —
            // it snakes into one region and exhausts it before ever trying an
            // older branch — so a weighted field (the stipple texture's
            // density gradient) can end up looking uniform: growth follows
            // whatever chain it started down, not the weight, and a
            // maxPoints-truncated fill can be lopsided even when the weight
            // is even. A random pick grows the frontier isotropically, which
            // is what lets `weight` actually shape the outcome.
            let activeIndex = rng.nextInt(in: 0...(active.count - 1))
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
        // Candidates span the whole bounds, not a jittered patch around the
        // centre — a centre-biased seed made an off-centre peak (e.g.
        // cornerWeight's, anchored near a corner) unreachable by
        // construction, and every later point grew outward from that seed.
        // Sampling the full bounds and picking the best-weighted candidate
        // lets the field actually decide where the composition starts.
        var best = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestScore = -1.0
        for _ in 0..<candidatesPerAnchor {
            let candidate = CGPoint(
                x: bounds.minX + CGFloat(rng.nextDouble()) * bounds.width,
                y: bounds.minY + CGFloat(rng.nextDouble()) * bounds.height
            )
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
