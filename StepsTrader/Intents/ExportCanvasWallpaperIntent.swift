import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Errors

enum ExportCanvasError: Error, CustomLocalizedStringResourceConvertible {
    case noCanvas
    case renderFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noCanvas:
            "No canvas found for today. Open the app and add some activities first."
        case .renderFailed:
            "Failed to render the canvas image."
        }
    }
}

// MARK: - AppIntent Enums

enum GradientStyleOption: String, AppEnum {
    case appDefault = "default"
    case radial
    case linear
    case radialReversed
    case linearReversed
    case organic

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Gradient Style"
    static var caseDisplayRepresentations: [GradientStyleOption: DisplayRepresentation] = [
        .appDefault:      "App Default",
        .radial:          "Radial",
        .linear:          "Linear",
        .radialReversed:  "Radial Reversed",
        .linearReversed:  "Linear Reversed",
        .organic:         "Organic",
    ]

    func resolved() -> GradientStyle {
        switch self {
        case .appDefault:
            let raw = UserDefaults(suiteName: SharedKeys.appGroupId)?.string(forKey: SharedKeys.gradientStyle)
                ?? UserDefaults.standard.string(forKey: SharedKeys.gradientStyle)
                ?? GradientStyle.radial.rawValue
            return GradientStyle(rawValue: raw) ?? .radial
        case .radial:          return .radial
        case .linear:          return .linear
        case .radialReversed:  return .radialReversed
        case .linearReversed:  return .linearReversed
        case .organic:         return .organic
        }
    }
}

enum ColorPaletteOption: String, AppEnum {
    case appDefault = "default"
    case warmSunset
    case roseGarden
    case ember

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Color Palette"
    static var caseDisplayRepresentations: [ColorPaletteOption: DisplayRepresentation] = [
        .appDefault:  "App Default",
        .warmSunset:  "Warm Sunset",
        .roseGarden:  "Rose Garden",
        .ember:       "Ember",
    ]

    func resolved() -> GradientPalette {
        switch self {
        case .appDefault:
            let raw = UserDefaults(suiteName: SharedKeys.appGroupId)?.string(forKey: SharedKeys.gradientPalette)
                ?? UserDefaults.standard.string(forKey: SharedKeys.gradientPalette)
                ?? GradientPalette.warmSunset.rawValue
            return GradientPalette(rawValue: raw) ?? .warmSunset
        case .warmSunset: return .warmSunset
        case .roseGarden: return .roseGarden
        case .ember:      return .ember
        }
    }
}

// MARK: - Export Canvas Wallpaper Intent

struct ExportCanvasWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Canvas Wallpaper"
    static var description: IntentDescription = IntentDescription(
        "Renders today's energy canvas as a wallpaper image. Optionally override gradient style and color palette.",
        categoryName: "Canvas"
    )

    @Parameter(title: "Gradient Style", default: .appDefault)
    var gradientStyle: GradientStyleOption

    @Parameter(title: "Color Palette", default: .appDefault)
    var colorPalette: ColorPaletteOption

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        Self.trackShortcutUsage()

        let dayKey = AppModel.dayKey(for: Date())
        let canvas = CanvasStorageService.shared.loadOrCreateCanvas(for: dayKey)
        let theme = Self.resolvedTheme()

        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen ?? UIScreen.main
        let baseWidth: CGFloat = screen.bounds.width
        let baseHeight: CGFloat = screen.bounds.height

        let isDaylight = theme == .daylight
        let bgColor: Color = isDaylight ? AppColors.Daylight.background : AppColors.Night.background
        let hasSteps = canvas.stepsPoints > 0
        let hasSleep = canvas.sleepPoints > 0

        let resolvedStyle = gradientStyle.resolved()
        let resolvedPalette = colorPalette.resolved()

        let view = ZStack {
            WallpaperGradientLayer(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: hasSteps,
                hasSleepData: hasSleep,
                isDaylight: isDaylight,
                gradientStyle: resolvedStyle,
                palette: resolvedPalette
            )

            GenerativeCanvasView(
                elements: canvas.elements,
                sleepPoints: canvas.sleepPoints,
                stepsPoints: canvas.stepsPoints,
                sleepColor: Color(hex: canvas.sleepColorHex),
                stepsColor: Color(hex: canvas.stepsColorHex),
                decayNorm: canvas.decayNorm,
                backgroundColor: bgColor,
                showLabelsOnCanvas: false,
                showsOutlinedLabels: false,
                showsBackgroundGradient: false,
                hasStepsData: hasSteps,
                hasSleepData: hasSleep,
                fixedTime: Date()
            )

            Image("grain 1")
                .resizable()
                .scaledToFill()
                .frame(width: baseWidth, height: baseHeight)
                .clipped()
                .opacity(0.4)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .frame(width: baseWidth, height: baseHeight)
        .clipped()

        let renderer = ImageRenderer(content: view)
        renderer.scale = screen.scale

        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            throw ExportCanvasError.renderFailed
        }

        Self.saveWallpaperToWidgetContainer(image: image)

        let file = IntentFile(data: data, filename: "canvas-wallpaper.png", type: .png)
        return .result(value: file)
    }

    private static func saveWallpaperToWidgetContainer(image: UIImage) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
        ) else { return }

        let dir = containerURL.appendingPathComponent("widget_snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("wallpaper_bg.jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)

        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Shortcut Usage Tracking

    private static func trackShortcutUsage() {
        let g = UserDefaults(suiteName: SharedKeys.appGroupId) ?? UserDefaults.standard
        g.set(true, forKey: "hasWallpaperShortcut")
        let current = g.integer(forKey: "wallpaperShortcutUses")
        g.set(current + 1, forKey: "wallpaperShortcutUses")

        Task.detached {
            await SupabaseSyncService.shared.trackWallpaperShortcutUsage()
        }
    }

    // MARK: - Theme Resolution

    private static func resolvedTheme() -> AppTheme {
        let raw = UserDefaults(suiteName: SharedKeys.appGroupId)?.string(forKey: "appTheme")
            ?? UserDefaults.standard.string(forKey: "appTheme")
            ?? "system"
        let theme = AppTheme.normalized(rawValue: raw)
        if theme == .system {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            return isDark ? .night : .daylight
        }
        return theme
    }
}

// MARK: - Wallpaper Gradient Layer

private struct WallpaperGradientLayer: View {
    let stepsPoints: Int
    let sleepPoints: Int
    let hasStepsData: Bool
    let hasSleepData: Bool
    let isDaylight: Bool
    let gradientStyle: GradientStyle
    let palette: GradientPalette

    var body: some View {
        Canvas { context, size in
            let pal = EnergyGradientRenderer.palette(for: palette)
            let stepsNorm = Double(min(max(stepsPoints, 0), 20)) / 20.0
            let sleepNorm = Double(min(max(sleepPoints, 0), 20)) / 20.0
            let Ss = EnergyGradientRenderer.smoothstep(stepsNorm)
            let Ls = EnergyGradientRenderer.smoothstep(sleepNorm)
            let opacities = EnergyGradientRenderer.computeOpacities(
                smoothedS: Ss,
                smoothedL: Ls,
                hasStepsData: hasStepsData,
                hasSleepData: hasSleepData,
                isDaylight: isDaylight
            )
            EnergyGradientRenderer.draw(
                context: &context,
                size: size,
                opacities: opacities,
                baseColor: isDaylight ? pal.daylightBase : pal.dark,
                gradientStyle: gradientStyle,
                colorPalette: pal
            )
        }
    }
}
