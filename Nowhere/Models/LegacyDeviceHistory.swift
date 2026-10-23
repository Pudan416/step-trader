import Foundation

/// A read-only index. Decoding a preview never modifies or activates its source.
struct LegacyDeviceHistory {
    struct Day: Identifiable {
        let id: String
        var titles: [String] = []
        var spent: Int?
        var previewPath: String?
    }

    let days: [Day]
    let archive: AccountHistoryVault.LegacyArchive

    private struct CatalogItem: Decodable { let id: String; let title: String }
    private struct Entry: Decodable { let dayKey: String; let optionId: String }
    private struct Canvas: Decodable {
        struct Element: Decodable { let optionId: String; let label: String? }
        let dayKey: String
        let elements: [Element]
        let inkSpent: Int?
    }

    init(archive: AccountHistoryVault.LegacyArchive) throws {
        self.archive = archive
        let defaults = archive.defaults.reduce(into: [String: Any]()) { merged, domain in
            merged.merge(domain) { first, _ in first }
        }
        let decoder = JSONDecoder()
        let catalog = (defaults[SharedKeys.happeningCatalog] as? Data).flatMap {
            try? decoder.decode([CatalogItem].self, from: $0)
        } ?? []
        let titles = Dictionary(catalog.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var indexed: [String: Day] = [:]
        let snapshotData = try archive.fileData(at: "pastDaySnapshots") ?? defaults[SharedKeys.pastDaySnapshots] as? Data
        if let data = snapshotData, let snapshots = try? decoder.decode([String: PastDaySnapshot].self, from: data) {
            for (key, snapshot) in snapshots {
                indexed[key] = Day(id: key, titles: snapshot.happeningIds.map { titles[$0] ?? $0 }, spent: snapshot.inkSpent)
            }
        }
        for path in archive.filePaths where path.hasPrefix("canvases/canvas_") && path.hasSuffix(".json") {
            let key = String(path.dropFirst("canvases/canvas_".count).dropLast(".json".count))
            var day = indexed[key] ?? Day(id: key)
            if let data = try archive.fileData(at: path), let canvas = try? decoder.decode(Canvas.self, from: data) {
                day.titles = canvas.elements.map { $0.label ?? titles[$0.optionId] ?? $0.optionId }
                day.spent = canvas.inkSpent ?? day.spent
            }
            // Even an unreadable preview keeps its dated entry; the raw file
            // remains archived rather than being dropped by a failed decoder.
            indexed[key] = day
        }
        if let data = defaults[SharedKeys.todayAdditions] as? Data,
           let entries = try? decoder.decode([Entry].self, from: data) {
            for (key, entries) in Dictionary(grouping: entries, by: \.dayKey) where indexed[key] == nil {
                indexed[key] = Day(id: key, titles: entries.map { titles[$0.optionId] ?? $0.optionId })
            }
        }
        let spendingData = try archive.fileData(at: "appStepsSpentByDay") ?? defaults[SharedKeys.appStepsSpentByDay] as? Data
        if let data = spendingData, let spending = try? decoder.decode([String: [String: Int]].self, from: data) {
            for (key, amounts) in spending {
                var day = indexed[key] ?? Day(id: key)
                day.spent = amounts.values.reduce(0, +)
                indexed[key] = day
            }
        }
        for path in archive.filePaths where path.hasPrefix("snapshots/canvas_") && path.hasSuffix(".png") {
            let key = String(path.dropFirst("snapshots/canvas_".count).dropLast(".png".count))
            var day = indexed[key] ?? Day(id: key)
            day.previewPath = path
            indexed[key] = day
        }
        days = indexed.values.sorted { $0.id > $1.id }
    }
}
