import SwiftUI
import Combine

extension Notification.Name {
    static let todayCanvasStorageDidChange = Notification.Name("todayCanvasStorageDidChange")
}

/// Only values that affect today's artwork. Unrelated model updates never render it again.
struct TodayCanvasAppearance: Equatable {
    var dayKey: String
    var steps: Int
    var sleep: Int
    var earned: Int
    var spent: Int
    var hasSteps: Bool
    var hasSleep: Bool
    var style: String
    var gradient: String
    var palette: String
    var texture: String
    var categories: String

    static var initial: Self {
        let defaults = UserDefaults.standard
        return Self(
            dayKey: AppModel.dayKey(for: .now), steps: 0, sleep: 0, earned: 0, spent: 0,
            hasSteps: false, hasSleep: false,
            style: defaults.string(forKey: SharedKeys.canvasVisualStyle) ?? CanvasVisualStyle.editorial.rawValue,
            gradient: defaults.string(forKey: SharedKeys.gradientStyle) ?? GradientStyle.radial.rawValue,
            palette: defaults.string(forKey: SharedKeys.gradientPalette) ?? GradientPalette.warmSunset.rawValue,
            texture: defaults.string(forKey: SharedKeys.canvasTexture) ?? CanvasTexture.grainSmall.rawValue,
            categories: defaults.string(forKey: SharedKeys.modernPaletteCategories) ?? ""
        )
    }

    func canvas(from saved: DayCanvas?) -> DayCanvas {
        var canvas = saved.flatMap { $0.dayKey == dayKey ? $0 : nil } ?? DayCanvas(dayKey: dayKey)
        canvas.stepsPoints = steps
        canvas.sleepPoints = sleep
        canvas.inkEarned = earned
        canvas.inkSpent = spent
        canvas.hasStepsData = hasSteps
        canvas.hasSleepData = hasSleep
        canvas.visualStyleRaw = style
        if canvas.remixSeed == nil {
            canvas.gradientStyle = gradient
            canvas.gradientPalette = palette
            canvas.textureRaw = texture
        }
        // Freeze after the newest shape has completed its spawn animation. A
        // reference-date frame would precede creation and make Legacy shapes invisible.
        let latestCreation = canvas.elements.map(\.createdAt).max() ?? canvas.createdAt
        canvas.lastModified = max(canvas.lastModified, latestCreation).addingTimeInterval(1)
        return canvas
    }
}

/// The same palette selection as today's artwork, ordered by perceived lightness.
/// Computed when the shared backdrop changes, never during a timer tick.
struct TodayCanvasUnlockPalette: Equatable {
    let colors: [DayObjectRGB]

    /// Sample the rendered colors, including the canvas's lighting/post processing.
    /// A tiny grid is evaluated once per snapshot, never per card or animation frame.
    static func sampled(from image: UIImage) -> Self? {
        guard let source = image.cgImage else { return nil }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        let colors = stride(from: 0, to: pixels.count, by: 4).compactMap { i -> DayObjectRGB? in
            let alpha = Float(pixels[i + 3]) / 255
            guard alpha > 0.9 else { return nil }
            return DayObjectRGB(sRGB: SIMD3(Float(pixels[i]), Float(pixels[i + 1]), Float(pixels[i + 2])) / (255 * alpha))
        }.sorted { $0.perceptualOKLab.x > $1.perceptualOKLab.x }
        guard !colors.isEmpty else { return nil }
        // Trim extremes so tiny dark actors/highlights do not dominate a whole card.
        return Self(colors: [0.1, 0.35, 0.65, 0.9].map { colors[Int(Double(colors.count - 1) * $0)] })
    }

    static func make(appearance: TodayCanvasAppearance, canvas: DayCanvas? = nil) -> Self {
        let currentCanvas = canvas ?? appearance.canvas(from: nil)
        let colors: [DayObjectRGB]
        if currentCanvas.resolvedVisualStyle == .editorial {
            let identity = currentCanvas.remixSeed.map { "primary-canvas:remix:\($0)" } ?? "primary-canvas"
            let seed = CanvasElement.makeSeed(
                optionId: "dayObjects:\(identity)", dayKey: appearance.dayKey, index: 0
            )
            colors = DayObjectPaletteSet.backgroundPalette(
                rootSeed: seed,
                categories: ModernPaletteSelection.decode(appearance.categories),
                dayKey: appearance.dayKey, identity: identity
            ).hexes.map { DayObjectRGB(hex: $0) }
        } else {
            let palette = EnergyGradientRenderer.palette(for: GradientPalette.normalized(
                rawValue: currentCanvas.gradientPalette ?? appearance.palette
            ))
            colors = [palette.bright, palette.warm, palette.cool, palette.dark].map { color in
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                return DayObjectRGB(sRGB: SIMD3(Float(red), Float(green), Float(blue)))
            }
        }
        return Self(colors: colors.sorted { $0.perceptualOKLab.x > $1.perceptualOKLab.x })
    }
}

struct TodayCanvasUnlockFill: View {
    var darkToLight = false
    @ObservedObject private var backdrop = TodayCanvasBackdropStore.shared

    var body: some View {
        LinearGradient(
            colors: (darkToLight ? Array(backdrop.unlockPalette.colors.reversed()) : backdrop.unlockPalette.colors).map { color in
                Color(.sRGB, red: Double(color.sRGB.x), green: Double(color.sRGB.y), blue: Double(color.sRGB.z))
            },
            startPoint: .leading, endPoint: .trailing
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One image shared by tabs, navigation destinations and sheets. No live Metal
/// views, display links, gestures or audio are attached to these backgrounds.
@MainActor
final class TodayCanvasBackdropStore: ObservableObject {
    static let shared = TodayCanvasBackdropStore(onRenderedCanvas: { canvas, categories in
        Task { @MainActor in
            _ = await MePosterSnapshotCache.shared.image(for: canvas, categories: categories)
        }
    })
    @Published private(set) var unlockPalette = TodayCanvasUnlockPalette.make(appearance: .initial)
    /// Feeds uses the day's original pigment, before snapshot lighting and haze.
    /// Keep the sampled palette for existing backgrounds and resource surfaces.
    @Published private(set) var feedPalette = TodayCanvasUnlockPalette.make(appearance: .initial)
    @Published private(set) var image: UIImage?
    @Published private(set) var dayKey: String?
    private var sourceData: Data?
    private var requested: Request?
    private var completed: Request?
    private var worker: Task<Void, Never>?
    private let load: (String) -> DayCanvas?
    private let render: (DayCanvas, Set<ModernPaletteCategory>) async -> UIImage?
    private let debounce: Duration
    private let onRenderedCanvas: (DayCanvas, Set<ModernPaletteCategory>) -> Void

    init(
        debounce: Duration = .milliseconds(180),
        load: @escaping (String) -> DayCanvas? = { CanvasStorageService.shared.loadCanvas(for: $0) },
        render: @escaping (DayCanvas, Set<ModernPaletteCategory>) async -> UIImage? = { canvas, categories in
            return await CanvasStorageService.shared.renderedSnapshot(
                canvas: canvas, size: CGSize(width: 390, height: 844), scale: 1.5,
                paletteCategories: categories
            )
        },
        onRenderedCanvas: @escaping (DayCanvas, Set<ModernPaletteCategory>) -> Void = { _, _ in }
    ) {
        self.onRenderedCanvas = onRenderedCanvas
        self.debounce = debounce
        self.load = load
        self.render = render
    }

    private struct Request: Equatable {
        var appearance: TodayCanvasAppearance
        var sourceData: Data?
    }

    func refresh(_ appearance: TodayCanvasAppearance, reload: Bool = false) {
        if dayKey != appearance.dayKey || reload {
            if dayKey != appearance.dayKey {
                unlockPalette = TodayCanvasUnlockPalette(colors: [])
                image = nil // Never show yesterday's artwork while the new day loads.
                dayKey = appearance.dayKey
            }
            let source = load(appearance.dayKey)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            sourceData = source.flatMap { try? encoder.encode($0) }
        }
        let saved = sourceData.flatMap { try? JSONDecoder().decode(DayCanvas.self, from: $0) }
        let nextPalette = TodayCanvasUnlockPalette.make(appearance: appearance, canvas: appearance.canvas(from: saved))
        if feedPalette != nextPalette { feedPalette = nextPalette }
        if image == nil, unlockPalette != nextPalette { unlockPalette = nextPalette }
        requested = Request(appearance: appearance, sourceData: sourceData)
        guard requested != completed, worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            // Coalesce bursts of preference / Health / persistence updates. A single
            // worker also prevents simultaneous GPU exports if input changes mid-render.
            while self.requested != self.completed {
                if self.image != nil { try? await Task.sleep(for: self.debounce) }
                guard let request = self.requested else { break }
                let saved = request.sourceData.flatMap { try? JSONDecoder().decode(DayCanvas.self, from: $0) }
                let canvas = request.appearance.canvas(from: saved)
                let rendered = await self.render(
                    canvas, ModernPaletteSelection.decode(request.appearance.categories)
                )
                if let rendered {
                    self.completed = request
                    if request == self.requested {
                        self.unlockPalette = TodayCanvasUnlockPalette.sampled(from: rendered)
                            ?? TodayCanvasUnlockPalette.make(appearance: request.appearance, canvas: canvas)
                        self.image = rendered
                        // Rejected, obsolete exports must never warm the poster cache.
                        self.onRenderedCanvas(canvas, ModernPaletteSelection.decode(request.appearance.categories))
                    }
                } else if request == self.requested {
                    // Keep the last successful frame. An identical later refresh
                    // can retry, but an export failure must not create a busy loop.
                    break
                }
            }
            self.worker = nil
        }
    }
}

struct TodayCanvasBackground: View {
    var detail = false
    var matchesCanvas = false
    @ObservedObject private var backdrop = TodayCanvasBackdropStore.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppColors.Night.background
                LinearGradient(
                    colors: backdrop.unlockPalette.colors.map {
                        Color(.sRGB, red: Double($0.sRGB.x), green: Double($0.sRGB.y), blue: Double($0.sRGB.z))
                    },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                if let image = backdrop.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: matchesCanvas ? 0 : (detail ? 12 : 6), opaque: true)
                }
                if !matchesCanvas {
                    Color.black.opacity(reduceTransparency ? 0.78 : (detail ? 0.68 : 0.58))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single refresh owner at the tab host; backgrounds themselves only display an image.
struct TodayCanvasBackdropHost: ViewModifier {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedKeys.canvasVisualStyle) private var style = CanvasVisualStyle.editorial.rawValue
    @AppStorage(SharedKeys.gradientStyle) private var gradient = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var palette = GradientPalette.warmSunset.rawValue
    @AppStorage(SharedKeys.canvasTexture) private var texture = CanvasTexture.grainSmall.rawValue
    @AppStorage(SharedKeys.modernPaletteCategories) private var categories = ModernPaletteSelection.encode(ModernPaletteSelection.all)
    @AppStorage(SharedKeys.dayEndHour, store: UserDefaults.stepsTrader()) private var dayEndHour = 0
    @AppStorage(SharedKeys.dayEndMinute, store: UserDefaults.stepsTrader()) private var dayEndMinute = 0
    @State private var currentDay = AppModel.dayKey(for: .now)
    private let dayCheck = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var appearance: TodayCanvasAppearance {
        TodayCanvasAppearance(
            dayKey: currentDay, steps: model.stepsPointsToday, sleep: model.sleepPointsToday,
            earned: model.baseEnergyToday, spent: model.spentStepsToday,
            hasSteps: model.hasStepsData, hasSleep: model.hasSleepData,
            style: style, gradient: gradient, palette: palette, texture: texture, categories: categories
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: appearance, initial: true) { _, value in
                guard scenePhase == .active else { return }
                TodayCanvasBackdropStore.shared.refresh(value)
            }
            .onChange(of: dayEndHour * 60 + dayEndMinute) { _, _ in
                if scenePhase == .active { refresh(reload: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh(reload: true) }
            }
            .onReceive(dayCheck) { _ in
                if scenePhase == .active { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .todayCanvasStorageDidChange)
                .receive(on: DispatchQueue.main)) { notification in
                guard scenePhase == .active,
                      notification.object as? String == AppModel.dayKey(for: .now) else { return }
                refresh(reload: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                if scenePhase == .active { refresh(reload: true) }
            }
    }

    private func refresh(reload: Bool = false) {
        let key = AppModel.dayKey(for: .now)
        currentDay = key
        var value = appearance
        value.dayKey = key
        TodayCanvasBackdropStore.shared.refresh(value, reload: reload)
    }
}

extension View {
    func todayCanvasBackground(detail: Bool = false, matchesCanvas: Bool = false) -> some View {
        background { TodayCanvasBackground(detail: detail, matchesCanvas: matchesCanvas) }
    }
}
