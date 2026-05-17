import SwiftUI
import UIKit
import os.log

extension Notification.Name {
    /// Posted with `object: dayKey: String` whenever a canvas's persisted JSON changes
    /// and any cached thumbnail for that day must be invalidated.
    static let historyThumbnailNeedsRefresh = Notification.Name("historyThumbnailNeedsRefresh")
}

/// Two-tier (memory + disk PNG) cache of `DayCanvas` thumbnails for HistoryView.
///
/// Renders a fixed-time composition of `EnergyGradientBackground + GenerativeCanvasView`
/// at the requested point size and stores it under `caches/HistoryThumbnails/`. Past-day
/// canvases are immutable, so we only ever invalidate `today` (driven by GalleryView's
/// save path posting `.historyThumbnailNeedsRefresh`).
@MainActor
final class HistoryThumbnailCache {
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

    private init() {
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        diskCacheURL = cachesDir.appendingPathComponent("HistoryThumbnails", isDirectory: true)
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
        theme: AppTheme
    ) async -> UIImage? {
        let key = cacheKey(dayKey: dayKey, size: size, theme: theme)
        if let cached = memCache[key] {
            touchLRU(key)
            return cached
        }
        if let onDisk = loadFromDisk(key: key) {
            insertLRU(key, image: onDisk)
            return onDisk
        }

        let image = renderThumbnail(
            canvas: canvas,
            size: size,
            fixedTime: fixedTime,
            theme: theme
        )

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
                let url = diskCacheURL.appendingPathComponent(file)
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// Manually warms the memory cache for callers that already rendered a frame.
    func store(_ image: UIImage, dayKey: String, size: CGSize, theme: AppTheme) {
        let key = cacheKey(dayKey: dayKey, size: size, theme: theme)
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
        theme: AppTheme
    ) -> UIImage? {
        let renderSize = CGSize(width: size.width * 2, height: size.height * 2)

        let rawCanvas = ZStack {
            EnergyGradientBackground(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: canvas.stepsPoints > 0,
                hasSleepData: canvas.sleepPoints > 0,
                showGrain: true,
                gradientStyleOverride: canvas.gradientStyle,
                gradientPaletteOverride: canvas.gradientPalette,
                textureOverride: canvas.textureRaw
            )

            GenerativeCanvasView(
                elements: canvas.elements,
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
                hasStepsData: canvas.stepsPoints > 0,
                hasSleepData: canvas.sleepPoints > 0,
                fixedTime: fixedTime,
                isOffscreenRender: true
            )
        }
        .frame(width: renderSize.width, height: renderSize.height)
        .environment(\.appTheme, theme)

        let renderer = ImageRenderer(content: rawCanvas)
        renderer.scale = 1.0
        renderer.proposedSize = .init(renderSize)

        guard let raw = renderer.uiImage else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled
    }

    // MARK: - Disk

    private static let cacheVersion = 3

    private func cacheKey(dayKey: String, size: CGSize, theme: AppTheme) -> String {
        "\(dayKey)_\(Int(size.width))x\(Int(size.height))_\(theme.rawValue)_v\(Self.cacheVersion)"
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let url = diskCacheURL.appendingPathComponent("\(key).png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(_ image: UIImage, key: String) {
        guard let data = image.pngData() else { return }
        let url = diskCacheURL.appendingPathComponent("\(key).png")
        try? data.write(to: url, options: .atomic)
    }
}
