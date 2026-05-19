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
    case mesh
    case angular

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Gradient Style"
    static var caseDisplayRepresentations: [GradientStyleOption: DisplayRepresentation] = [
        .appDefault:      "App Default",
        .radial:          "Radial",
        .linear:          "Linear",
        .radialReversed:  "Radial Reversed",
        .linearReversed:  "Linear Reversed",
        .organic:         "Organic",
        .mesh:            "Mesh",
        .angular:         "Angular",
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
        case .mesh:            return .mesh
        case .angular:         return .angular
        }
    }
}

enum ColorPaletteOption: String, AppEnum {
    case appDefault = "default"
    case warmSunset
    case ocean
    case aurora
    case dusk

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Color Palette"
    static var caseDisplayRepresentations: [ColorPaletteOption: DisplayRepresentation] = [
        .appDefault:  "App Default",
        .warmSunset:  "Sunset",
        .ocean:       "Ocean",
        .aurora:      "Aurora",
        .dusk:        "Dusk",
    ]

    func resolved() -> GradientPalette {
        switch self {
        case .appDefault:
            let raw = UserDefaults(suiteName: SharedKeys.appGroupId)?.string(forKey: SharedKeys.gradientPalette)
                ?? UserDefaults.standard.string(forKey: SharedKeys.gradientPalette)
                ?? GradientPalette.warmSunset.rawValue
            return GradientPalette.normalized(rawValue: raw)
        case .warmSunset: return .warmSunset
        case .ocean:      return .ocean
        case .aurora:     return .aurora
        case .dusk:       return .dusk
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

        let dayKey = AppModel.dayKey(for: .now)
        let canvas = CanvasStorageService.shared.loadOrCreateCanvas(for: dayKey)
        guard let screen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.screen else {
            throw ExportCanvasError.renderFailed
        }
        let baseWidth: CGFloat = screen.bounds.width
        let baseHeight: CGFloat = screen.bounds.height

        let bgColor = AppColors.Night.background
        let hasSteps = canvas.resolvedHasStepsData
        let hasSleep = canvas.resolvedHasSleepData

        let resolvedStyle = gradientStyle.resolved()
        let resolvedPalette = colorPalette.resolved()

        let view = ZStack {
            WallpaperGradientLayer(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: hasSteps,
                hasSleepData: hasSleep,
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
                fixedTime: .now,
                isOffscreenRender: true
            )

            let textureRaw = UserDefaults.standard.string(forKey: SharedKeys.canvasTexture) ?? "grain (small)"
            let texture = CanvasTexture.fromStored(textureRaw)
            if let assetName = texture.assetName {
                let blendMode = texture.blendMode
                let opacity = texture.defaultOpacity
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: baseWidth, height: baseHeight)
                    .clipped()
                    .blendMode(blendMode)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            }
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

        Task {
            await SupabaseSyncService.shared.trackWallpaperShortcutUsage()
        }
    }

    // MARK: - Theme Resolution

    @MainActor
    private static func resolvedTheme() -> AppTheme { .night }
}

// MARK: - Wallpaper Gradient Layer

private struct WallpaperGradientLayer: View {
    let stepsPoints: Int
    let sleepPoints: Int
    let hasStepsData: Bool
    let hasSleepData: Bool
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
                hasSleepData: hasSleepData
            )
            EnergyGradientRenderer.draw(
                context: &context,
                size: size,
                opacities: opacities,
                baseColor: pal.dark,
                gradientStyle: gradientStyle,
                colorPalette: pal
            )
        }
    }
}
