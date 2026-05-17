import Foundation

struct DayCanvas: Codable {
    let dayKey: String                          // "2026-02-12"
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

    /// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all colors spent)
    var decayNorm: Double {
        guard inkEarned > 0 else { return 0 }
        return min(1.0, Double(inkSpent) / Double(inkEarned))
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
        self.createdAt = Date()
        self.lastModified = Date()
        self.gradientStyle = nil
        self.gradientPalette = nil
    }
}
