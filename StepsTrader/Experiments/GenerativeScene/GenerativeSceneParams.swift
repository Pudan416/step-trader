import SwiftUI

/// The `VisualMapper` layer of the generative-scene experiment: raw day data in,
/// normalised `0...1` scene properties out. Nothing here touches HealthKit or
/// the renderer, so the mapping stays unit-testable and the shader never sees a
/// step count.
///
/// The two health inputs are deliberately kept on different axes. Steps and
/// sleep both reaching for brightness would cancel each other — a long day on a
/// good night would land in the same grey middle as a short day on a bad one.
/// So steps own energy (size, sparks, emission) and sleep owns clarity (how
/// deep and clean the darks are, how settled the contour is).
struct GenerativeSceneParams: Equatable {
    /// Steps → how much the scene has to give.
    var energy: Double
    /// Sleep → how clean and deep the picture reads.
    var clarity: Double
    /// Happenings → how many masses the composition carries.
    var events: Double
    /// The day's variation, `0..<1`. Stable for a given day.
    var seed: Double

    var palette: GenerativeScenePalette

    init(
        energy: Double,
        clarity: Double,
        events: Double,
        seed: Double,
        palette: GenerativeScenePalette
    ) {
        self.energy = Self.clamped(energy)
        self.clarity = Self.clamped(clarity)
        self.events = Self.clamped(events)
        self.seed = seed - seed.rounded(.down)
        self.palette = palette
    }

    // MARK: - Normalisation

    /// Saturating, not stepped. The brief's `0–2k / 2–6k / 6–10k` bands are for
    /// describing the result, never for computing it — a threshold crossing
    /// would show up as a visible jump in the scene.
    ///
    /// Reaches ~0.63 at 6k and ~0.86 at 12k, so a very long day still reads as
    /// more than a long one without the curve going flat.
    static func energy(forSteps steps: Int) -> Double {
        guard steps > 0 else { return 0 }
        return 1 - exp(-Double(steps) / 6000)
    }

    /// Monotone in hours slept. Not a peak curve: ten hours may be unusual, but
    /// it is not visually "worse" than eight, and a non-monotone mapping makes
    /// the picture impossible to read back.
    static func clarity(forSleepHours hours: Double) -> Double {
        clamped((hours - 3.0) / 5.0)
    }

    /// Saturating for the same reason as `energy`, and tuned against
    /// `DayComposition.nominalDayCount`: five happenings already fill the frame.
    static func events(forCount count: Int) -> Double {
        guard count > 0 else { return 0 }
        return 1 - exp(-Double(count) / 2.6)
    }

    /// `hash(dayKey)` folded into `0..<1`. Reuses the canvas seed function so a
    /// day's scene is reproducible across reinstalls, exactly like
    /// `DayComposition.forDay`.
    static func seed(forDayKey dayKey: String) -> Double {
        let raw = CanvasElement.makeSeed(optionId: "generativeScene", dayKey: dayKey, index: 0)
        return Double(raw >> 11) / Double(1 << 53)
    }

    static func forDay(
        dayKey: String,
        steps: Int,
        sleepHours: Double,
        eventCount: Int
    ) -> GenerativeSceneParams {
        let seed = Self.seed(forDayKey: dayKey)
        return GenerativeSceneParams(
            energy: energy(forSteps: steps),
            clarity: clarity(forSleepHours: sleepHours),
            events: events(forCount: eventCount),
            seed: seed,
            palette: GenerativeScenePalette.forSeed(seed)
        )
    }

    private static func clamped(_ v: Double) -> Double { min(max(v, 0), 1) }
}

// MARK: - Palette

/// Three colours the shader works in: the ground the scene sits on, the body's
/// own light, and the warm accent inside it.
///
/// The families come from `AppColors.PayGate`, which the app already ships, so
/// the experiment stays inside the existing colour world instead of inventing a
/// second one. The accent is `AppColors.brandAccent` in every family — it is
/// the app's yellow and it is what the reference uses for its sparks.
struct GenerativeScenePalette: Equatable {
    var deep: Color
    var mid: Color
    var glow: Color

    /// Named so the lab can show which family a seed picked.
    var name: String

    static let midnight = GenerativeScenePalette(
        deep: AppColors.PayGate.midnight1,
        mid: AppColors.PayGate.midnight3,
        glow: AppColors.brandAccent,
        name: "Midnight"
    )

    static let ocean = GenerativeScenePalette(
        deep: AppColors.PayGate.ocean1,
        mid: AppColors.PayGate.ocean3,
        glow: AppColors.brandAccent,
        name: "Ocean"
    )

    static let aurora = GenerativeScenePalette(
        deep: AppColors.PayGate.aurora1,
        mid: AppColors.PayGate.aurora3,
        glow: AppColors.brandAccent,
        name: "Aurora"
    )

    static let neon = GenerativeScenePalette(
        deep: AppColors.PayGate.neon1,
        mid: AppColors.PayGate.neon3,
        glow: AppColors.brandAccent,
        name: "Neon"
    )

    static let all: [GenerativeScenePalette] = [.midnight, .ocean, .aurora, .neon]

    static func forSeed(_ seed: Double) -> GenerativeScenePalette {
        let index = Int((seed - seed.rounded(.down)) * Double(all.count))
        return all[min(max(index, 0), all.count - 1)]
    }
}
