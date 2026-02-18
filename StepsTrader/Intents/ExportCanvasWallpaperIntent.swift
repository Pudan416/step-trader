import AppIntents
import SwiftUI

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

// MARK: - Export Canvas Wallpaper Intent

struct ExportCanvasWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Canvas Wallpaper"
    static var description: IntentDescription = IntentDescription(
        "Renders today's energy canvas as a 9:16 wallpaper image.",
        categoryName: "Canvas"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let dayKey = AppModel.dayKey(for: Date())
        let canvas = CanvasStorageService.shared.loadOrCreateCanvas(for: dayKey)
        let theme = Self.resolvedTheme()

        // Match actual device screen size so iOS doesn't upscale/crop
        let screen = UIScreen.main
        let baseWidth: CGFloat = screen.bounds.width
        let baseHeight: CGFloat = screen.bounds.height

        let isDaylight = theme == .daylight
        let bgColor: Color = isDaylight ? AppColors.Daylight.background : AppColors.Night.background
        let hasSteps = canvas.stepsPoints > 0
        let hasSleep = canvas.sleepPoints > 0

        let view = ZStack {
            // Background gradient — use the same EnergyGradientRenderer the app uses
            WallpaperGradientLayer(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: hasSteps,
                hasSleepData: hasSleep,
                isDaylight: isDaylight
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
                hasSleepData: hasSleep
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

        let file = IntentFile(data: data, filename: "canvas-wallpaper.png", type: .png)
        return .result(value: file)
    }

    // MARK: - Theme Resolution

    private static func resolvedTheme() -> AppTheme {
        let raw = UserDefaults(suiteName: SharedKeys.appGroupId)?.string(forKey: "appTheme")
            ?? UserDefaults.standard.string(forKey: "appTheme")
            ?? "system"
        let theme = AppTheme.normalized(rawValue: raw)
        if theme == .system {
            // Check actual device appearance
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            return isDark ? .night : .daylight
        }
        return theme
    }
}

// MARK: - Wallpaper Gradient Layer

/// Renders the energy gradient using the same `EnergyGradientRenderer` the app uses,
/// ensuring pixel-perfect match with in-app appearance for both themes.
private struct WallpaperGradientLayer: View {
    let stepsPoints: Int
    let sleepPoints: Int
    let hasStepsData: Bool
    let hasSleepData: Bool
    let isDaylight: Bool

    var body: some View {
        Canvas { context, size in
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
                baseColor: isDaylight
                    ? EnergyGradientRenderer.daylightBase
                    : EnergyGradientRenderer.night
            )
        }
    }
}
