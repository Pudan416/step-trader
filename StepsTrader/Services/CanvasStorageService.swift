import Foundation
import SwiftUI
import os.log

// MARK: - Canvas Storage Service

/// Manages persistence of DayCanvas data and snapshot images.
/// - Live canvas: JSON file per day key
/// - Snapshots: PNG images rendered on day-end
/// - History is retained indefinitely (no retention prune). Access is gated in
///   the UI: Pro sees all days, Free sees only the most recent ones.
final class CanvasStorageService {
    static let shared = CanvasStorageService()

    private let fileManager = FileManager.default

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StepsTrader", category: "CanvasStorage")

    private let storageDirectory: URL
    private let snapshotDirectory: URL

    private init() {
        let fm = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "StepsTrader"

        let dir = URL.applicationSupportDirectory
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "canvases", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create canvas storage directory: \(error.localizedDescription)")
        }
        self.storageDirectory = dir

        let snapDir = URL.documentsDirectory
            .appending(path: "canvas_snapshots", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: snapDir, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create snapshot directory: \(error.localizedDescription)")
        }
        self.snapshotDirectory = snapDir
    }

    // MARK: - Canvas CRUD

    @discardableResult
    func saveCanvas(_ canvas: DayCanvas) -> Bool {
        let url = canvasFileURL(for: canvas.dayKey)
        do {
            let data = try JSONEncoder().encode(canvas)
            try data.write(to: url, options: .atomic)
            NotificationCenter.default.post(name: .todayCanvasStorageDidChange, object: canvas.dayKey)
            return true
        } catch {
            Self.log.error("Failed to save canvas for \(canvas.dayKey): \(error.localizedDescription)")
            return false
        }
    }

    func loadCanvas(for dayKey: String) -> DayCanvas? {
        let url = canvasFileURL(for: dayKey)
        guard let data = try? Data(contentsOf: url),
              let canvas = try? JSONDecoder().decode(DayCanvas.self, from: data) else {
            return nil
        }
        return canvas
    }

    func loadOrCreateCanvas(for dayKey: String) -> DayCanvas {
        if let existing = loadCanvas(for: dayKey) {
            return existing
        }
        let canvas = DayCanvas(dayKey: dayKey)
        saveCanvas(canvas)
        return canvas
    }

    func deleteCanvas(for dayKey: String) {
        let url = canvasFileURL(for: dayKey)
        try? fileManager.removeItem(at: url)
        NotificationCenter.default.post(name: .todayCanvasStorageDidChange, object: dayKey)
    }

    /// Moves the current session to a key produced by a day-end preference
    /// change. The destination is written atomically before the source is
    /// removed, so a failed write leaves the original canvas recoverable.
    @discardableResult
    func rekeyCanvas(from oldDayKey: String, to newDayKey: String) -> Bool {
        guard oldDayKey != newDayKey else { return true }
        guard var source = loadCanvas(for: oldDayKey) else { return true }

        source.dayKey = newDayKey
        if let destination = loadCanvas(for: newDayKey) {
            var knownIDs = Set(source.elements.map(\.id))
            source.elements.append(
                contentsOf: destination.elements.filter { knownIDs.insert($0.id).inserted }
            )
            source.lastModified = max(source.lastModified, destination.lastModified)
        }

        guard saveCanvas(source) else { return false }
        deleteCanvas(for: oldDayKey)
        return true
    }

    // MARK: - Snapshot

    @MainActor
    func saveSnapshot(
        for canvas: DayCanvas,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) async {
        if let image = await renderedSnapshot(
            canvas: canvas,
            size: CGSize(width: 390, height: 500),
            scale: 3,
            paletteCategories: paletteCategories
        ),
           let data = image.pngData() {
            let url = snapshotURL(for: canvas.dayKey)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("Failed to save snapshot for \(canvas.dayKey): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private static let widgetSnapshotQueue = CanvasWidgetSnapshotQueue { canvas, categories in
        await CanvasStorageService.shared.saveWidgetSnapshot(for: canvas, paletteCategories: categories)
    }

    @MainActor
    func scheduleWidgetSnapshot(for canvas: DayCanvas, paletteCategories: Set<ModernPaletteCategory>) {
        Self.widgetSnapshotQueue.submit(canvas, categories: paletteCategories)
    }

    /// Saves a smaller canvas snapshot to the shared App Group container
    /// so the widget extension can display today's canvas preview.
    /// Renders on main actor, then writes JPEG to disk in the background.
    @MainActor
    func saveWidgetSnapshot(
        for canvas: DayCanvas,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) async {
        guard let rendered = await renderedSnapshot(
            canvas: canvas,
            size: CGSize(width: 200, height: 200),
            scale: 2,
            paletteCategories: paletteCategories
        ) else { return }
        let opaqueRenderer = UIGraphicsImageRenderer(size: rendered.size, format: {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = rendered.scale
            fmt.opaque = true
            return fmt
        }())
        let data = opaqueRenderer.jpegData(withCompressionQuality: 0.8) { ctx in
            rendered.draw(at: .zero)
        }

        let fm = self.fileManager
        await Task.detached(priority: .utility) {
            guard let containerURL = fm.containerURL(
                forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
            ) else { return }

            let dir = containerURL.appending(path: "widget_snapshots", directoryHint: .isDirectory)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Self.log.error("Failed to create widget snapshot directory: \(error.localizedDescription)")
            }
            let url = dir.appending(path: "canvas_today.jpg")
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("Failed to save widget snapshot: \(error.localizedDescription)")
            }
        }.value
    }

    @MainActor
    func renderedSnapshot(
        canvas: DayCanvas,
        size: CGSize,
        scale: CGFloat,
        paletteCategories: Set<ModernPaletteCategory>
    ) async -> UIImage? {
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
                scale: scale,
                elapsedTime: 4
            )
        }

        let view = ZStack {
            EnergyGradientBackground(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                showGrain: true,
                gradientStyleOverride: canvas.gradientStyle,
                gradientPaletteOverride: canvas.gradientPalette,
                textureOverride: canvas.textureRaw,
                fixedTime: canvas.lastModified
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
                showLabelsOnCanvas: false,
                showsOutlinedLabels: false,
                showsBackgroundGradient: false,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                fixedTime: canvas.lastModified,
                isOffscreenRender: true
            )
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = .init(size)
        return renderer.uiImage
    }

    func loadSnapshotImage(for dayKey: String) -> UIImage? {
        let url = snapshotURL(for: dayKey)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func hasSnapshot(for dayKey: String) -> Bool {
        fileManager.fileExists(atPath: snapshotURL(for: dayKey).path)
    }

    // MARK: - History

    /// Returns all available day keys with canvas data, sorted newest first
    func availableDayKeys() -> [String] {
        guard let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> String? in
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix("canvas_") else { return nil }
                return String(name.dropFirst("canvas_".count))
            }
            .sorted(by: >)
    }

    // MARK: - Private

    private func canvasFileURL(for dayKey: String) -> URL {
        storageDirectory.appending(path: "canvas_\(dayKey).json")
    }

    private func snapshotURL(for dayKey: String) -> URL {
        snapshotDirectory.appending(path: "canvas_\(dayKey).png")
    }
}

/// Coordinates optional widget exports separately from the visible canvas.
@MainActor
final class CanvasWidgetSnapshotQueue {
    typealias Export = (DayCanvas, Set<ModernPaletteCategory>) async -> Void
    private let export: Export
    private let debounce: Duration
    private var pending: (DayCanvas, Set<ModernPaletteCategory>)?
    private var worker: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(300), export: @escaping Export) {
        self.debounce = debounce
        self.export = export
    }

    func submit(_ canvas: DayCanvas, categories: Set<ModernPaletteCategory>) {
        pending = (canvas, categories)
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.pending != nil {
                try? await Task.sleep(for: self.debounce)
                guard let request = self.pending else { break }
                self.pending = nil
                await self.export(request.0, request.1)
            }
            self.worker = nil
        }
    }
}
