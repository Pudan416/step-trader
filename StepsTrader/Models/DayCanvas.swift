import Foundation

struct DayCanvas: Codable {
    var dayKey: String                          // "2026-02-12"
    var elements: [CanvasElement] {             // spawned from activities
        didSet {
            let previousIDs = Set(oldValue.map { $0.id.uuidString.lowercased() })
            let eventIDs = elements.map { $0.id.uuidString.lowercased() }
            artworkRecipe = artworkRecipe?.reconciled(
                eventIDs: eventIDs, addingEventIDs: Set(eventIDs).subtracting(previousIDs)
            )
        }
    }
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
    /// Absent in historical artwork. Never synthesize during decoding.
    var artworkRecipe: NativeAtlasRecipe?
    /// Optional so historical canvases retain their exact pre-Remix artwork.
    var remixSeed: UInt64?
    var soundWorldRaw: String?
    var soundMoodRaw: String?
    var guestSoundWorldRaw: String?

    var resolvedRemixSeed: UInt64 {
        remixSeed ?? CanvasElement.makeSeed(
            optionId: "dayObjects:primary-canvas", dayKey: dayKey, index: 0
        )
    }

    var resolvedMusicSelection: DayObjectsWorldSelection {
        let fallback = DayObjectsWorldSelector.makeSelection(remixSeed: resolvedRemixSeed)
        return .init(
            world: soundWorldRaw.flatMap(DayObjectsSoundWorld.init(rawValue:)) ?? fallback.world,
            mood: soundMoodRaw.flatMap(DayObjectsSoundMood.init(rawValue:)) ?? fallback.mood,
            guestWorld: soundWorldRaw == nil
                ? fallback.guestWorld
                : guestSoundWorldRaw.flatMap(DayObjectsSoundWorld.init(rawValue:))
        )
    }

    /// Preferences continue to style untouched days. A Remix owns its saved
    /// background, so later health refreshes cannot replace it.
    @discardableResult
    mutating func applyVisualPreferences(
        gradientStyle: String, gradientPalette: String,
        overlayStyle: String, textureRaw: String
    ) -> Bool {
        guard remixSeed == nil else { return false }
        let changed = self.gradientStyle != gradientStyle
            || self.gradientPalette != gradientPalette
            || self.overlayStyle != overlayStyle || self.textureRaw != textureRaw
        self.gradientStyle = gradientStyle
        self.gradientPalette = gradientPalette
        self.overlayStyle = overlayStyle
        self.textureRaw = textureRaw
        return changed
    }

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
        self.artworkRecipe = nil
    }

    @discardableResult
    mutating func freezeNativeBackgroundIfNeeded() -> Bool {
        guard var recipe = artworkRecipe, recipe.isSupported,
              recipe.backgroundStyle == nil else { return false }
        recipe.backgroundStyle = recipe.resolvedBackgroundStyle(dayKey: dayKey)
        artworkRecipe = recipe
        return true
    }

    /// Explicit appearance edits update only the canvas selected by the caller.
    /// Loading or rendering saved artwork never reapplies current preferences.
    @discardableResult
    mutating func applyNativeBackground(paletteCategories: Set<ModernPaletteCategory>) -> Bool {
        guard var recipe = artworkRecipe, recipe.isSupported,
              !recipe.locks.contains("artwork") else { return false }
        let background = NativeAtlasRecipe.makeBackgroundStyle(
            dayKey: dayKey, recipeSeed: UInt64(recipe.seedHex, radix: 16) ?? 0,
            paletteCategories: paletteCategories
        )
        guard recipe.backgroundStyle != background else { return false }
        recipe.backgroundStyle = background
        artworkRecipe = recipe
        lastModified = .now
        return true
    }

    static func newDailyCanvas(
        dayKey: String,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) -> Self {
        var canvas = Self(dayKey: dayKey)
        canvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue
        canvas.artworkRecipe = .make(dayKey: dayKey, paletteCategories: paletteCategories)
        return canvas
    }
}
