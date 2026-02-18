import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

struct TicketGroup: Identifiable, Codable {
    let id: String
    var name: String
    var selection: FamilyActivitySelection
    var settings: AppUnlockSettings
    var enabledIntervals: Set<AccessWindow> = [.minutes10, .minutes30, .hour1] // 10 / 30 / 60 min
    var templateApp: String? = nil // Template bundle ID (e.g., "com.burbn.instagram")
    /// Index into sticker themes (bright colors, shapes, fonts) for "sticker" look.
    var stickerThemeIndex: Int = 0

    init(id: String = UUID().uuidString, name: String, selection: FamilyActivitySelection = FamilyActivitySelection(), settings: AppUnlockSettings, enabledIntervals: Set<AccessWindow> = [.minutes10, .minutes30, .hour1], templateApp: String? = nil, stickerThemeIndex: Int = 0) {
        self.id = id
        self.name = name
        self.selection = selection
        self.settings = settings
        self.enabledIntervals = enabledIntervals
        self.templateApp = templateApp
        self.stickerThemeIndex = stickerThemeIndex
    }

    // Flat base costs for each interval
    func cost(for interval: AccessWindow) -> Int {
        let baseCosts: [AccessWindow: Int] = [
            .minutes10: 4,
            .minutes30: 10,
            .hour1: 20
        ]
        return baseCosts[interval] ?? 5
    }

    // Custom Codable implementation for FamilyActivitySelection
    enum CodingKeys: String, CodingKey {
        case id, name, selectionData, settings, enabledIntervals, templateApp, stickerThemeIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(AppUnlockSettings.self, forKey: .settings)

        // Decode only known intervals (ignore removed: single, minutes5, minutes15, hour2, day1)
        if let rawArray = try? container.decodeIfPresent([String].self, forKey: .enabledIntervals) {
            enabledIntervals = Set(rawArray.compactMap { AccessWindow(rawValue: $0) })
        }
        if enabledIntervals.isEmpty {
            enabledIntervals = [.minutes10, .minutes30, .hour1]
        }
        templateApp = try container.decodeIfPresent(String.self, forKey: .templateApp)
        stickerThemeIndex = try container.decodeIfPresent(Int.self, forKey: .stickerThemeIndex) ?? 0

        #if canImport(FamilyControls)
        if let data = try? container.decode(Data.self, forKey: .selectionData),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = decoded
        } else {
            selection = FamilyActivitySelection()
        }
        #else
        selection = FamilyActivitySelection()
        #endif
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(settings, forKey: .settings)
        try container.encode(enabledIntervals, forKey: .enabledIntervals)
        try container.encodeIfPresent(templateApp, forKey: .templateApp)
        try container.encode(stickerThemeIndex, forKey: .stickerThemeIndex)

        #if canImport(FamilyControls)
        if let data = try? JSONEncoder().encode(selection) {
            try container.encode(data, forKey: .selectionData)
        }
        #endif
    }
}
