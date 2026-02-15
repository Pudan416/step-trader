import Foundation
import SwiftUI

// MARK: - Canvas Storage Service

/// Manages persistence of DayCanvas data and snapshot images.
/// - Live canvas: JSON file per day key
/// - Snapshots: PNG images rendered on day-end
/// - Auto-prunes history older than 90 days
final class CanvasStorageService {
    static let shared = CanvasStorageService()

    private let fileManager = FileManager.default
    private let retentionDays = 90

    private var storageDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first!
        let bundleID = Bundle.main.bundleIdentifier ?? "StepsTrader"
        let dir = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("canvases", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var snapshotDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("canvas_snapshots", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Canvas CRUD

    func saveCanvas(_ canvas: DayCanvas) {
        let url = canvasFileURL(for: canvas.dayKey)
        guard let data = try? JSONEncoder().encode(canvas) else { return }
        try? data.write(to: url, options: .atomic)
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
            backgroundColor: backgroundColor
        )
        .frame(width: 390, height: 500)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        if let image = renderer.uiImage,
           let data = image.pngData() {
            let url = snapshotURL(for: dayKey)
            try? data.write(to: url, options: .atomic)
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

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for dayKey in availableDayKeys() {
            guard let date = formatter.date(from: dayKey), date < cutoffDate else { continue }
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
