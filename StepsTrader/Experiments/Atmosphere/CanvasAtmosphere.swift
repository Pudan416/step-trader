import Foundation
import SwiftUI

/// Depth planes the canvas is split across.
///
/// The existing renderer draws every element into one flat `Canvas`, which is
/// why the result reads as an appliqué however good the shapes are. Splitting
/// the same elements across three planes and giving each its own blur, scale
/// and opacity turns the identical drawing into a scene — no change to the
/// shape renderers at all.
enum CanvasDepthPlane: Int, CaseIterable, Hashable {
    case far, mid, near

    /// Parallax. Far things sit slightly smaller, near things slightly larger.
    var scale: Double {
        switch self {
        case .far: 0.93
        case .mid: 1.0
        case .near: 1.09
        }
    }

    /// Aerial perspective: distance costs contrast, and an out-of-focus
    /// foreground reads as a veil rather than an object.
    var opacity: Double {
        switch self {
        case .far: 0.70
        case .mid: 1.0
        case .near: 0.82
        }
    }

    /// Share of elements assigned to this plane. The mid plane keeps the
    /// majority — it is the one in focus, and a scene whose subject is mostly
    /// out of focus reads as a mistake, not as depth.
    var share: Double {
        switch self {
        case .far: 0.28
        case .mid: 0.48
        case .near: 0.24
        }
    }
}

/// The two things the day puts into the air.
///
/// Both are deliberately perceptual rather than symbolic: dust is something you
/// see hanging in the light, focus is something you feel before you name it.
/// The previous mapping (energy/coherence/clarity) described the parameters and
/// not the picture, which is exactly why it read as arbitrary.
struct CanvasAtmosphere: Equatable {
    /// `0...1` — how much is suspended in the air. From steps.
    var dust: Double
    /// `0...1` — 1 is a crisp frame, 0 is one that drifts out of focus entirely.
    /// From sleep.
    var focus: Double

    init(dust: Double, focus: Double) {
        self.dust = min(max(dust, 0), 1)
        self.focus = min(max(focus, 0), 1)
    }

    static let neutral = CanvasAtmosphere(dust: 0.45, focus: 0.8)

    // MARK: - Mapping

    /// Saturating, like every other day metric here: a threshold would show up
    /// as a step change in the air itself.
    static func dust(forSteps steps: Int) -> Double {
        guard steps > 0 else { return 0 }
        return 1 - exp(-Double(steps) / 8000)
    }

    /// Monotone in hours slept. Eight hours is a fully sharp frame; three is a
    /// frame with nothing to hold on to.
    static func focus(forSleepHours hours: Double) -> Double {
        min(max((hours - 3.0) / 5.0, 0), 1)
    }

    static func forDay(steps: Int, sleepHours: Double) -> CanvasAtmosphere {
        CanvasAtmosphere(
            dust: dust(forSteps: steps),
            focus: focus(forSleepHours: sleepHours)
        )
    }

    // MARK: - Derived render values

    /// Blur for a plane, in points.
    ///
    /// The base term is the depth of field that exists on any well-shot frame:
    /// the near plane is always soft, the subject never is. The second term is
    /// sleep — as it drops, the drift spreads to every plane including the mid
    /// one, so a bad night takes the frame's anchor away rather than just
    /// dimming it.
    func blurRadius(for plane: CanvasDepthPlane) -> Double {
        let drift = 1 - focus
        switch plane {
        case .far:  return 4 + 12 * drift
        case .mid:  return 0 + 7 * drift
        case .near: return 12 + 16 * drift
        }
    }

    /// Dust motes are always softer than the elements on the same plane — they
    /// are small enough that any defocus swallows them whole.
    func dustBlurRadius(for plane: CanvasDepthPlane) -> Double {
        switch plane {
        case .far:  return 1 + 3 * (1 - focus)
        case .mid:  return 0
        case .near: return 9 + 10 * (1 - focus)
        }
    }

    /// Mote frequency per plane. Far dust is fine and dense, near dust is a few
    /// large bokeh discs — that contrast is most of what sells the depth.
    func dustScale(for plane: CanvasDepthPlane) -> Double {
        switch plane {
        case .far:  return 46
        case .mid:  return 26
        case .near: return 9
        }
    }

    func dustOpacity(for plane: CanvasDepthPlane) -> Double {
        let base: Double = switch plane {
        case .far: 0.55
        case .mid: 0.75
        case .near: 0.5
        }
        return base * (0.25 + 0.75 * dust)
    }

    // MARK: - Assignment

    /// Which plane an element belongs to.
    ///
    /// Deterministic and stable for the life of the element: a mote of dust may
    /// drift, but an element must not hop between planes on the next frame, or
    /// re-render, or app launch. Seeded on the element's own `shapeSeed` via the
    /// same FNV construction the rest of the canvas uses — never `hashValue`,
    /// which Swift re-seeds per process.
    static func plane(for element: CanvasElement, dayKey: String) -> CanvasDepthPlane {
        let seed = element.shapeSeed
            ?? CanvasElement.makeSeed(optionId: element.optionId, dayKey: dayKey, index: 0)
        var rng = SeededRNG.derived(from: seed, domain: "depthPlane")
        let roll = rng.nextDouble()

        var cumulative = 0.0
        for plane in CanvasDepthPlane.allCases {
            cumulative += plane.share
            if roll < cumulative { return plane }
        }
        return .mid
    }

    /// The elements of each plane, in the order the renderer expects them.
    static func split(
        _ elements: [CanvasElement],
        dayKey: String
    ) -> [CanvasDepthPlane: [CanvasElement]] {
        var result: [CanvasDepthPlane: [CanvasElement]] = [:]
        for plane in CanvasDepthPlane.allCases { result[plane] = [] }
        for element in elements {
            result[plane(for: element, dayKey: dayKey), default: []].append(element)
        }
        return result
    }
}
