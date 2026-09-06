import Foundation

/// A value-only editing session. Selection never writes preferences until Apply.
struct SettingsAppearanceDraft: Equatable {
    var style: String
    var palette: String
    var automatic: Bool
    var texture: String
    var categories: String
    var canvasStyle: String
    var shapes: Set<CanvasShapeType>
    var fills: Set<TextureKind>
    var manualStyle: String
    var manualPalette: String

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let shapeKeys = [SharedKeys.bodyCanvasShape, SharedKeys.mindCanvasShape, SharedKeys.heartCanvasShape]
        let legacyShapes = shapeKeys.compactMap { defaults.string(forKey: $0) }
        let shapes = (defaults.stringArray(forKey: SharedKeys.allowedCanvasShapes) ?? legacyShapes)
            .compactMap(CanvasShapeType.init(rawValue:))
            .map { $0 == .blob || $0 == .spirograph ? CanvasShapeType.circle : $0 }
            .filter { CanvasShapeType.selectableCases.contains($0) }
        let fills = defaults.stringArray(forKey: SharedKeys.allowedCanvasFills)?
            .compactMap(TextureKind.init(rawValue:)) ?? TextureKind.allCases
        return Self(
            style: defaults.string(forKey: SharedKeys.gradientStyle) ?? GradientStyle.radial.rawValue,
            palette: defaults.string(forKey: SharedKeys.gradientPalette) ?? GradientPalette.warmSunset.rawValue,
            automatic: defaults.bool(forKey: SharedKeys.dailyRandomThemeEnabled),
            texture: defaults.string(forKey: SharedKeys.canvasTexture) ?? CanvasTexture.grainSmall.rawValue,
            categories: defaults.string(forKey: SharedKeys.modernPaletteCategories) ?? "",
            canvasStyle: defaults.string(forKey: SharedKeys.canvasVisualStyle) ?? CanvasVisualStyle.editorial.rawValue,
            shapes: Set(shapes.isEmpty ? CanvasShapeType.selectableCases : shapes),
            fills: Set(fills.isEmpty ? TextureKind.allCases : fills),
            manualStyle: defaults.string(forKey: SharedKeys.userGradientStyle) ?? GradientStyle.radial.rawValue,
            manualPalette: defaults.string(forKey: SharedKeys.userGradientPalette) ?? GradientPalette.warmSunset.rawValue
        )
    }

    mutating func setAutomatic(_ enabled: Bool) {
        guard enabled != automatic else { return }
        if enabled {
            manualStyle = style
            manualPalette = palette
            reroll()
        } else {
            style = manualStyle
            palette = manualPalette
        }
        automatic = enabled
    }

    mutating func reroll() {
        palette = GradientPalette.allCases.filter { $0.rawValue != palette }.randomElement()?.rawValue ?? palette
        style = GradientStyle.allCases.filter { $0.rawValue != style }.randomElement()?.rawValue ?? style
    }

    func apply(to defaults: UserDefaults = .standard, shared: UserDefaults?, dayKey: String) {
        let values: [String: Any] = [
            SharedKeys.gradientStyle: style, SharedKeys.gradientPalette: palette,
            SharedKeys.dailyRandomThemeEnabled: automatic, SharedKeys.canvasTexture: texture,
            SharedKeys.modernPaletteCategories: categories, SharedKeys.canvasVisualStyle: canvasStyle,
            SharedKeys.allowedCanvasShapes: CanvasShapeType.selectableCases.filter(shapes.contains).map(\.rawValue),
            SharedKeys.allowedCanvasFills: TextureKind.allCases.filter(fills.contains).map(\.rawValue),
            SharedKeys.userGradientStyle: automatic ? manualStyle : style,
            SharedKeys.userGradientPalette: automatic ? manualPalette : palette
        ]
        for (key, value) in values {
            defaults.set(value, forKey: key)
            shared?.set(value, forKey: key)
        }
        if automatic {
            defaults.set(dayKey, forKey: SharedKeys.dailyRandomThemeLastRolledKey)
        } else {
            defaults.removeObject(forKey: SharedKeys.dailyRandomThemeLastRolledKey)
        }
    }
}
