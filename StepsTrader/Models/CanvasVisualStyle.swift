import Foundation

enum CanvasVisualStyle: String, Codable, CaseIterable, Hashable, Identifiable {
    case editorial
    case legacy

    var id: String { rawValue }
}

enum CanvasVisualStyleMigration {
    static let currentVersion = 1

    enum Decision: Equatable {
        case use(CanvasVisualStyle)
        case persist(CanvasVisualStyle, markVersion: Int)
    }

    static func decision(
        dayKey: String,
        storedStyleRaw: String?,
        currentDayKey: String,
        completedVersion: Int
    ) -> Decision {
        if let storedStyleRaw,
           let explicit = CanvasVisualStyle(rawValue: storedStyleRaw) {
            return .use(explicit)
        }
        guard dayKey == currentDayKey,
              completedVersion < currentVersion else {
            return .use(.legacy)
        }
        return .persist(.editorial, markVersion: currentVersion)
    }
}
