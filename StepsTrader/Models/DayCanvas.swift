import Foundation

struct DayCanvas: Codable {
    var dayKey: String                          // "2026-02-12"
    var elements: [CanvasElement]               // spawned from activities
    var sleepPoints: Int
    var stepsPoints: Int
    var sleepColorHex: String
    var stepsColorHex: String
    var inkEarned: Int
    var inkSpent: Int
    let createdAt: Date
    var lastModified: Date
    var gradientStyle: String?
    var gradientPalette: String?
    var overlayStyle: String?
    var textureRaw: String?
    var visualStyleRaw: String?
    var hasStepsData: Bool?
    var hasSleepData: Bool?

    /// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all colors spent)
    var decayNorm: Double {
        guard inkEarned > 0 else { return 0 }
        return min(1.0, Double(inkSpent) / Double(inkEarned))
    }

    /// Resolved flag: prefers stored boolean, falls back to points > 0 for legacy canvases.
    var resolvedHasStepsData: Bool {
        hasStepsData ?? (stepsPoints > 0)
    }

    /// Resolved flag: prefers stored boolean, falls back to points > 0 for legacy canvases.
    var resolvedHasSleepData: Bool {
        hasSleepData ?? (sleepPoints > 0)
    }

    /// Canvases written before the Editorial promotion are historical Legacy
    /// canvases. Only the one-time active-day migration may promote a missing
    /// value; ordinary decoding never changes old artwork retroactively.
    var resolvedVisualStyle: CanvasVisualStyle {
        CanvasVisualStyle(rawValue: visualStyleRaw ?? "") ?? .legacy
    }

    init(dayKey: String) {
        self.dayKey = dayKey
        self.elements = []
        self.sleepPoints = 0
        self.stepsPoints = 0
        self.sleepColorHex = "#000000"
        self.stepsColorHex = "#FED415"
        self.inkEarned = 0
        self.inkSpent = 0
        self.createdAt = .now
        self.lastModified = .now
        self.gradientStyle = nil
        self.gradientPalette = nil
        self.overlayStyle = nil
        self.textureRaw = nil
        self.visualStyleRaw = nil
        self.hasStepsData = nil
        self.hasSleepData = nil
    }
}
