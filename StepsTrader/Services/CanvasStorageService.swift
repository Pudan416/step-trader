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

    private lazy var storageDirectory: URL = {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupport = paths.first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("StepsTrader", isDirectory: true)
                .appendingPathComponent("canvases", isDirectory: true)
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "StepsTrader"
        let dir = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("canvases", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create canvas storage directory: \(error.localizedDescription)")
        }
        return dir
    }()

    private lazy var snapshotDirectory: URL = {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docDir = paths.first else {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("StepsTrader", isDirectory: true)
                .appendingPathComponent("canvas_snapshots", isDirectory: true)
            do {
                try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            } catch {
                Self.log.error("Failed to create snapshot fallback directory: \(error.localizedDescription)")
            }
            return fallback
        }
        let dir = docDir.appendingPathComponent("canvas_snapshots", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create snapshot directory: \(error.localizedDescription)")
        }
        return dir
    }()

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
            fixedTime: Date()
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
            fixedTime: Date()
        )
        .frame(width: 200, height: 200)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let image = renderer.uiImage,
              let data = image.jpegData(compressionQuality: 0.8) else { return }

        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
        ) else { return }

        let dir = containerURL.appendingPathComponent("widget_snapshots", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create widget snapshot directory: \(error.localizedDescription)")
        }
        let url = dir.appendingPathComponent("canvas_today.jpg")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Self.log.error("Failed to save widget snapshot: \(error.localizedDescription)")
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
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }

        for dayKey in availableDayKeys() {
            guard let date = CachedFormatters.dayKey.date(from: dayKey), date < cutoffDate else { continue }
            deleteCanvas(for: dayKey)
            let snapshotUrl = snapshotURL(for: dayKey)
            try? fileManager.removeItem(at: snapshotUrl)
        }
    }

    // MARK: - Private

    private func canvasFileURL(for dayKey: String) -> URL {
        storageDirectory.appendingPathComponent("canvas_\(dayKey).json")
    }

    private func snapshotURL(for dayKey: String) -> URL {
        snapshotDirectory.appendingPathComponent("canvas_\(dayKey).png")
    }
}
