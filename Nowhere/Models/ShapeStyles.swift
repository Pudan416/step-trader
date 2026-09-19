import SwiftUI

/// Visual shape types available for canvas elements.
/// Each shape bundles its own rendering style and movement behavior.
/// The set a new element may take is user-configured — see `allowedByUser`.
enum CanvasShapeType: String, CaseIterable, Codable, Identifiable {
    case circle      // dense gradient circles, overlapping, no deformation
    case snowflake   // symmetric rectmorph outline, Lissajous drift, morphing trail ghosts
    case rays        // Metal spotlight cones, edge-anchored, sweep oscillation
    case organicBlob // multi-layer organic contour morph + breathe
    case blob        // (hidden) legacy noise-deformed closed path — kept for legacy data
    case spirograph  // (hidden) legacy hypotrochoid curves — kept for legacy data

    var id: String { rawValue }

    /// Only the shapes exposed in the picker UI.
    static var selectableCases: [CanvasShapeType] {
        [.circle, .snowflake, .rays, .organicBlob]
    }

    var displayName: String {
        switch self {
        case .circle:      String(localized: "Circle", comment: "Canvas shape type")
        case .snowflake:   String(localized: "Snowflake", comment: "Canvas shape type")
        case .rays:        String(localized: "Rays", comment: "Canvas shape type")
        case .organicBlob: String(localized: "Organic", comment: "Canvas shape type")
        case .blob:        String(localized: "Blob", comment: "Canvas shape type")
        case .spirograph:  String(localized: "Spirograph", comment: "Canvas shape type")
        }
    }

    var iconName: String {
        switch self {
        case .circle:      "circle.fill"
        case .snowflake:   "snowflake"
        case .rays:        "rays"
        case .organicBlob: "aqi.medium"
        case .blob:        "drop.fill"
        case .spirograph:  "circle.fill"
        }
    }

    // MARK: - User-configured shape set
    //
    // The three per-category keys collapse into one multi-select. Shape choice
    // stops being derived from a category and becomes a set the user picks from.

    /// The shapes a new element may take.
    ///
    /// Seeds itself from the three legacy per-category keys on first read, so a
    /// user's current preferences carry over.
    ///
    /// Never returns empty: `CanvasElement.spawn` picks from this with a
    /// seeded index, and `reroll` with `randomElement()`.
    static var allowedByUser: [CanvasShapeType] {
        let stored: [CanvasShapeType]
        if let raw = UserDefaults.standard.stringArray(forKey: SharedKeys.allowedCanvasShapes) {
            stored = raw.compactMap(CanvasShapeType.init(rawValue:)).map(migrateHiddenLegacy)
        } else {
            stored = seedFromLegacyKeys()
        }

        let usable = Set(stored).filter { selectableCases.contains($0) }
        guard !usable.isEmpty else { return selectableCases }

        // Picker order, so the set reads the same everywhere it is shown.
        return selectableCases.filter(usable.contains)
    }

    /// Writes the user's selection. Rejects a set that is empty once hidden
    /// legacy shapes are filtered out — the UI blocks deselecting the last
    /// shape, and this is the backstop behind that rule.
    @discardableResult
    static func setAllowed(_ shapes: Set<CanvasShapeType>) -> Bool {
        let valid = shapes.filter { selectableCases.contains($0) }
        guard !valid.isEmpty else { return false }
        UserDefaults.standard.set(
            selectableCases.filter(valid.contains).map(\.rawValue),
            forKey: SharedKeys.allowedCanvasShapes
        )
        return true
    }

    /// Union of the three legacy keys, persisted so this runs only once.
    private static func seedFromLegacyKeys() -> [CanvasShapeType] {
        let legacy = [SharedKeys.bodyCanvasShape, SharedKeys.mindCanvasShape, SharedKeys.heartCanvasShape]
            .compactMap { UserDefaults.standard.string(forKey: $0) }
            .compactMap(CanvasShapeType.init(rawValue:))
            .map(migrateHiddenLegacy)
        guard !legacy.isEmpty else { return selectableCases }

        let seeded = selectableCases.filter(Set(legacy).contains)
        guard !seeded.isEmpty else { return selectableCases }
        UserDefaults.standard.set(seeded.map(\.rawValue), forKey: SharedKeys.allowedCanvasShapes)
        return seeded
    }

    /// Hidden legacy shapes collapse to circle, exactly as `resolved(for:)` did.
    private static func migrateHiddenLegacy(_ shape: CanvasShapeType) -> CanvasShapeType {
        (shape == .blob || shape == .spirograph) ? .circle : shape
    }
}
