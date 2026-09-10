import Foundation
import CoreGraphics
import UIKit
import ImageIO
import os.log
import WidgetKit

struct WidgetSnapshot: Codable {
    let balance: Int
    let earned: Int
    let stepsPoints: Int
    let sleepPoints: Int
    let bodyPoints: Int
    let mindPoints: Int
    let heartPoints: Int
    let timestamp: Date
}

enum WidgetDataFile {
    private static var fileURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
        )?.appending(path: "widget_data.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}


// MARK: - Shared wallpaper geometry

enum WidgetWallpaperPosition: String, CaseIterable, Codable {
    case top, middle, bottom
    var fraction: CGFloat {
        switch self { case .top: return 0; case .middle: return 0.5; case .bottom: return 1 }
    }
}

/// Screen coordinates in points; image coordinates in pixels. The wallpaper
/// must use the same centered aspect-fill transform as the Home Screen.
struct WidgetWallpaperGeometry {
    static func cropRect(imageSize: CGSize, screenSize: CGSize, widgetSize: CGSize,
                         position: WidgetWallpaperPosition,
                         top: Double = 0.10, bottom: Double = 0.80) -> CGRect? {
        let values = [imageSize.width, imageSize.height, screenSize.width, screenSize.height,
                      widgetSize.width, widgetSize.height]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }),
              top.isFinite, bottom.isFinite,
              widgetSize.width <= screenSize.width,
              widgetSize.height <= screenSize.height else { return nil }
        let upper = min(max(CGFloat(top), 0), 1) * screenSize.height
        let lower = min(max(CGFloat(bottom), 0), 1) * screenSize.height
        guard lower - upper >= widgetSize.height else { return nil }
        let origin = CGPoint(x: (screenSize.width - widgetSize.width) / 2,
                             y: upper + (lower - upper - widgetSize.height) * position.fraction)
        let scale = max(screenSize.width / imageSize.width, screenSize.height / imageSize.height)
        let overflow = CGSize(width: (imageSize.width * scale - screenSize.width) / 2,
                              height: (imageSize.height * scale - screenSize.height) / 2)
        return CGRect(x: (origin.x + overflow.width) / scale,
                      y: (origin.y + overflow.height) / scale,
                      width: widgetSize.width / scale, height: widgetSize.height / scale)
    }
}


/// The image and its screen dimensions are one atomic file, so a refresh can
/// never combine new wallpaper with metadata from the previous export.
struct WidgetWallpaperSnapshot: Codable {
    let imageData: Data
    let screenSize: CGSize
}

enum WidgetWallpaperFile {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId)?
            .appendingPathComponent("widget_snapshots", isDirectory: true)
    }

    static func write(_ snapshot: WidgetWallpaperSnapshot, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent("wallpaper_v2.plist"), options: .atomic)
    }

    static func read(from directory: URL) -> WidgetWallpaperSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("wallpaper_v2.plist")) else { return nil }
        return try? PropertyListDecoder().decode(WidgetWallpaperSnapshot.self, from: data)
    }

    static func background(widgetSize: CGSize, position: WidgetWallpaperPosition? = nil,
                           defaults: UserDefaults, directory: URL) -> UIImage? {
        let mode = defaults.string(forKey: SharedKeys.widgetBackgroundMode) ?? "basic"
        guard mode == "wallpaper" || mode == "aligned" else { return nil }
        let snapshot = read(from: directory)
        let data = snapshot?.imageData ?? (mode == "wallpaper"
            ? try? Data(contentsOf: directory.appendingPathComponent("wallpaper_bg.jpg")) : nil)
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: mode == "aligned" ? 2048 : 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        if mode == "aligned" {
            // These presets describe full-width iPhone widgets. Other hosts
            // must not display an unrelated crop as if it were aligned.
            guard let snapshot, snapshot.screenSize.height > snapshot.screenSize.width,
                  widgetSize.width >= snapshot.screenSize.width * 0.7 else { return nil }
            let selected = position ?? WidgetWallpaperPosition(rawValue:
                defaults.string(forKey: SharedKeys.widgetWallpaperPosition) ?? "top") ?? .top
            let top = defaults.object(forKey: SharedKeys.widgetWallpaperTop) as? Double ?? 0.10
            let bottom = defaults.object(forKey: SharedKeys.widgetWallpaperBottom) as? Double ?? 0.80
            guard let rect = WidgetWallpaperGeometry.cropRect(
                imageSize: CGSize(width: image.width, height: image.height),
                screenSize: snapshot.screenSize, widgetSize: widgetSize,
                position: selected, top: top, bottom: bottom),
                  let cropped = image.cropping(to: rect.integral) else { return nil }
            return UIImage(cgImage: cropped)
        }
        return UIImage(cgImage: image)
    }
}
