import Foundation
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
        )?.appendingPathComponent("widget_data.json")
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
