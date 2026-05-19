import Foundation
import SwiftUI
import os.log

// MARK: - Canvas Storage Service

/// Manages persistence of DayCanvas data and snapshot images.
/// - Live canvas: JSON file per day key
/// - Snapshots: PNG images rendered on day-end
/// - Auto-prunes history older than 90 days
final class CanvasStorageService {
    static let shared = CanvasStorageService()

    private let fileManager = FileManager.default
    private let retentionDays = 90

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
    }

    // MARK: - Snapshot

    @MainActor
    func saveSnapshot(for dayKey: String, elements: [CanvasElement], sleepPoints: Int, stepsPoints: Int, sleepColor: Color, stepsColor: Color, decayNorm: Double, backgroundColor: Color = AppColors.Night.background) {
        let view = GenerativeCanvasView(
            elements: elements,
            sleepPoints: sleepPoints,
            stepsPoints: stepsPoints,
            sleepColor: sleepColor,
            stepsColor: stepsColor,
            decayNorm: decayNorm,
            backgroundColor: backgroundColor,
            fixedTime: Date.now,
            isOffscreenRender: true
        )
        .frame(width: 390, height: 500)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        if let image = renderer.uiImage,
           let data = image.pngData() {
            let url = snapshotURL(for: dayKey)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("Failed to save snapshot for \(dayKey): \(error.localizedDescription)")
            }
        }
    }

    /// Saves a smaller canvas snapshot to the shared App Group container
    /// so the widget extension can display today's canvas preview.
    /// Renders on main actor, then writes JPEG to disk in the background.
    @MainActor
    func saveWidgetSnapshot(for dayKey: String, elements: [CanvasElement], sleepPoints: Int, stepsPoints: Int, sleepColor: Color, stepsColor: Color, decayNorm: Double, backgroundColor: Color = AppColors.Night.background) {
        let view = GenerativeCanvasView(
            elements: elements,
            sleepPoints: sleepPoints,
            stepsPoints: stepsPoints,
            sleepColor: sleepColor,
            stepsColor: stepsColor,
            decayNorm: decayNorm,
            backgroundColor: backgroundColor,
            showLabelsOnCanvas: false,
            showsOutlinedLabels: false,
            fixedTime: Date.now,
            isOffscreenRender: true
        )
        .frame(width: 200, height: 200)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let rendered = renderer.uiImage else { return }
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
        Task.detached(priority: .utility) {
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
        }
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

    // MARK: - Pruning

    func pruneOldCanvases() {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: Date.now) else { return }

        for dayKey in availableDayKeys() {
            guard let date = CachedFormatters.dayKey.date(from: dayKey), date < cutoffDate else { continue }
            deleteCanvas(for: dayKey)
            let snapshotUrl = snapshotURL(for: dayKey)
            try? fileManager.removeItem(at: snapshotUrl)
        }
    }

    // MARK: - Private

    private func canvasFileURL(for dayKey: String) -> URL {
        storageDirectory.appending(path: "canvas_\(dayKey).json")
    }

    private func snapshotURL(for dayKey: String) -> URL {
        snapshotDirectory.appending(path: "canvas_\(dayKey).png")
    }
}
