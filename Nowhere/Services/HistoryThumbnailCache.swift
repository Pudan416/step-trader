import SwiftUI
import os.log

extension Notification.Name {
    /// Posted with `object: dayKey: String` whenever a canvas's persisted JSON changes
    /// and any cached thumbnail for that day must be invalidated.
    static let historyThumbnailNeedsRefresh = Notification.Name("historyThumbnailNeedsRefresh")
}

/// Two-tier (memory + disk PNG) cache of `DayCanvas` thumbnails for the Me calendar.
///
/// Renders a fixed-time composition of `EnergyGradientBackground + GenerativeCanvasView`
/// at the requested point size and stores it under `caches/HistoryThumbnails/`. Past-day
/// canvases are immutable, so we only ever invalidate `today` (driven by GalleryView's
/// save path posting `.historyThumbnailNeedsRefresh`).
@MainActor
final class HistoryThumbnailCache {
    typealias Render = @MainActor (DayCanvas, CGSize, Date, AppTheme, Set<ModernPaletteCategory>) async -> UIImage?
    static let shared = HistoryThumbnailCache()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "StepsTrader",
        category: "HistoryThumbnailCache"
    )

    private static let maxMemoryCacheEntries = 30

    private var memCache: [String: UIImage] = [:]
    private var accessOrder: [String] = []
    private let diskCacheURL: URL
    private let fileManager = FileManager.default
    private var observer: NSObjectProtocol?
    private let renderOverride: Render?
    private var accountEpoch = UUID()
    private var accountSwitchSuspended = false
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    init(directory: URL? = nil, render: Render? = nil) {
        let cachesDir = URL.cachesDirectory
        diskCacheURL = directory ?? cachesDir.appending(path: "HistoryThumbnails", directoryHint: .isDirectory)
        renderOverride = render
        do {
            try fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create thumbnail cache dir: \(error.localizedDescription)")
        }

        // Listen for invalidations posted by GalleryView (today's canvas changed).
        observer = NotificationCenter.default.addObserver(
            forName: .historyThumbnailNeedsRefresh,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let dayKey = note.object as? String else { return }
            Task { @MainActor [weak self] in
                self?.invalidate(dayKey: dayKey)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Public API

    /// Returns a thumbnail image for `dayKey`. Hits memory first, then disk, then renders.
    /// Thumbnails are **raw paintings** (gradient + shapes, no poster frame) so the
    /// history gallery shows only the artwork.
    func thumbnail(
        for dayKey: String,
        canvas: DayCanvas,
        size: CGSize,
        fixedTime: Date,
        theme: AppTheme,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) async -> UIImage? {
        guard !accountSwitchSuspended, !Task.isCancelled else { return nil }
        let epoch = accountEpoch
        let key = cacheKey(
            dayKey: dayKey,
            style: canvas.resolvedVisualStyle,
            size: size,
            theme: theme
        )
        if let cached = memCache[key] {
            touchLRU(key)
            return cached
        }
        if let onDisk = loadFromDisk(key: key) {
            insertLRU(key, image: onDisk)
            return onDisk
        }

        let id = UUID()
        let render = Task { @MainActor in
            await self.renderThumbnail(canvas: canvas, size: size, fixedTime: fixedTime,
                                       theme: theme, paletteCategories: paletteCategories)
        }
        inFlight[id] = render
        let image = await render.value
        inFlight.removeValue(forKey: id)
        guard accountEpoch == epoch, !accountSwitchSuspended, !Task.isCancelled else { return nil }

        if let image {
            insertLRU(key, image: image)
            saveToDisk(image, key: key)
        }
        return image
    }

    /// Drops every cached entry for the given `dayKey`, both in memory and on disk.
    /// Past days never need this — call it for `today` after the live canvas changes.
    func invalidate(dayKey: String) {
        let prefix = "\(dayKey)_"
        memCache = memCache.filter { !$0.key.hasPrefix(prefix) }

        if let files = try? fileManager.contentsOfDirectory(atPath: diskCacheURL.path) {
            for file in files where file.hasPrefix(prefix) {
                let url = diskCacheURL.appending(path: file)
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// Drops all style-dependent thumbnails after a global appearance change.
    func invalidateAll() {
        accountEpoch = UUID()
        for task in inFlight.values { task.cancel() }
        memCache.removeAll()
        accessOrder.removeAll()
        guard let files = try? fileManager.contentsOfDirectory(atPath: diskCacheURL.path) else { return }
        for file in files {
            try? fileManager.removeItem(at: diskCacheURL.appending(path: file))
        }
    }

    func suspendForAccountSwitch() async throws {
        accountSwitchSuspended = true
        accountEpoch = UUID()
        let tasks = Array(inFlight.values)
        for task in tasks { task.cancel() }
        for task in tasks { _ = await task.value }
        inFlight.removeAll()
        memCache.removeAll()
        accessOrder.removeAll()
        guard fileManager.fileExists(atPath: diskCacheURL.path) else { return }
        for url in try fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: url)
        }
    }

    func resumeAfterAccountSwitch() {
        accountSwitchSuspended = false
    }

    /// Manually warms the memory cache for callers that already rendered a frame.
    func store(
        _ image: UIImage,
        dayKey: String,
        style: CanvasVisualStyle = .legacy,
        size: CGSize,
        theme: AppTheme
    ) {
        guard !accountSwitchSuspended, !Task.isCancelled else { return }
        let key = cacheKey(dayKey: dayKey, style: style, size: size, theme: theme)
        insertLRU(key, image: image)
        saveToDisk(image, key: key)
    }

    // MARK: - LRU

    private func touchLRU(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func insertLRU(_ key: String, image: UIImage) {
        memCache[key] = image
        touchLRU(key)
        while memCache.count > Self.maxMemoryCacheEntries {
            let evicted = accessOrder.removeFirst()
            memCache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Rendering

    private func renderThumbnail(
        canvas: DayCanvas,
        size: CGSize,
        fixedTime: Date,
        theme: AppTheme,
        paletteCategories: Set<ModernPaletteCategory>
    ) async -> UIImage? {
        if let renderOverride {
            return await renderOverride(canvas, size, fixedTime, theme, paletteCategories)
        }
        if CanvasExportRoute(canvas: canvas) == .editorialMetal {
            return await DayObjectsImageRenderer.image(
                input: EditorialCanvasInputFactory.make(
                    canvas: canvas,
                    metrics: EditorialCanvasMetrics(
                        stepsProgress: Double(canvas.stepsPoints) / 20,
                        sleepProgress: Double(canvas.sleepPoints) / 20,
                        spentProgress: canvas.decayNorm
                    ),
                    paletteCategories: paletteCategories
                ),
                size: size,
                scale: 2,
                elapsedTime: 4
            )
        }

        let rawCanvas = ZStack {
            EnergyGradientBackground(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                showGrain: true,
                gradientStyleOverride: canvas.gradientStyle,
                gradientPaletteOverride: canvas.gradientPalette,
                textureOverride: canvas.textureRaw
            )

            GenerativeCanvasView(
                elements: canvas.elements,
                dayKey: canvas.dayKey,
                remixSeed: canvas.remixSeed,
                sleepPoints: canvas.sleepPoints,
                stepsPoints: canvas.stepsPoints,
                sleepColor: Color(hex: canvas.sleepColorHex),
                stepsColor: Color(hex: canvas.stepsColorHex),
                decayNorm: canvas.decayNorm,
                backgroundColor: .clear,
                labelColor: theme.textPrimary,
                showLabelsOnCanvas: false,
                showsOutlinedLabels: false,
                showsBackgroundGradient: false,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                fixedTime: fixedTime,
                isOffscreenRender: true
            )
        }
        .frame(width: size.width, height: size.height)
        .environment(\.appTheme, theme)

        let renderer = ImageRenderer(content: rawCanvas)
        renderer.scale = 2.0
        renderer.proposedSize = .init(size)

        return renderer.uiImage
    }

    // MARK: - Disk

    private static let cacheVersion = 7

    nonisolated static func cacheIdentity(
        dayKey: String,
        style: CanvasVisualStyle
    ) -> String {
        "\(dayKey)_\(style.rawValue)"
    }

    private func cacheKey(
        dayKey: String,
        style: CanvasVisualStyle,
        size: CGSize,
        theme: AppTheme
    ) -> String {
        "\(Self.cacheIdentity(dayKey: dayKey, style: style))_\(Int(size.width))x\(Int(size.height))_\(theme.rawValue)_v\(Self.cacheVersion)"
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let url = diskCacheURL.appending(path: "\(key).png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(_ image: UIImage, key: String) {
        guard let data = image.pngData() else { return }
        let url = diskCacheURL.appending(path: "\(key).png")
        try? data.write(to: url, options: .atomic)
    }
}
