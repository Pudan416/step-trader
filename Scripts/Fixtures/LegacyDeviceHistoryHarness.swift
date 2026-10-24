import Foundation

enum SharedKeys {
    static let happeningCatalog = "catalog"
    static let pastDaySnapshots = "snapshots"
    static let todayAdditions = "entries"
    static let appStepsSpentByDay = "spending"
}
enum EnergyDefaults {
    static let stepsTarget: Double = 10000
    static let sleepTargetHours: Double = 8
}
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { fatalError(message) }
}

@main
struct LegacyDeviceHistoryHarness {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "LegacyDeviceHistory-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: root)
        }
        let canvasDirectory = root.appendingPathComponent("working/canvases")
        let previewDirectory = root.appendingPathComponent("working/previews")
        let snapshotURL = root.appendingPathComponent("working/past.json")
        let spendingURL = root.appendingPathComponent("working/spending.json")
        try fm.createDirectory(at: canvasDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let original = Data("{\"dayKey\":\"2026-01-02\",\"elements\":[{\"optionId\":\"old\",\"label\":\"Original title\"}],\"inkSpent\":3,\"unknownFutureArtwork\":{\"preserve\":true}}".utf8)
        try original.write(to: canvasDirectory.appendingPathComponent("canvas_2026-01-02.json"))
        let corrupt = Data("future-unreadable-canvas-format".utf8)
        try corrupt.write(to: canvasDirectory.appendingPathComponent("canvas_2026-01-04.json"))
        let preview = Data("synthetic preview bytes".utf8)
        try preview.write(to: previewDirectory.appendingPathComponent("canvas_2026-01-02.png"))
        try Data("{\"2026-01-01\":{\"bodyIds\":[\"old\"],\"controlSpent\":5}}".utf8).write(to: snapshotURL)
        try Data("{\"2026-01-02\":{\"appA\":3,\"appB\":5},\"2026-01-03\":{\"app\":9}}".utf8).write(to: spendingURL)
        defaults.set(Data("[{\"id\":\"old\",\"title\":\"Archived title\"}]".utf8), forKey: SharedKeys.happeningCatalog)
        defaults.set(Data("[{\"dayKey\":\"2026-01-05\",\"optionId\":\"old\"}]".utf8), forKey: SharedKeys.todayAdditions)
        let vault = try AccountHistoryVault(root: root.appendingPathComponent("vault"), domains: [
            .init(defaults: defaults, keys: [SharedKeys.happeningCatalog, SharedKeys.todayAdditions])
        ], locations: [
            .init(name: "canvases", url: canvasDirectory, isDirectory: true),
            .init(name: "snapshots", url: previewDirectory, isDirectory: true),
            .init(name: "pastDaySnapshots", url: snapshotURL),
            .init(name: "appStepsSpentByDay", url: spendingURL)
        ])
        try vault.activate(owner: "account-A")
        try Data("owned account A".utf8).write(to: canvasDirectory.appendingPathComponent("canvas_2026-02-01.json"))
        try vault.activate(owner: "account-B")
        let bCatalog = Data("[{\"id\":\"old\",\"title\":\"B title\"}]".utf8)
        defaults.set(bCatalog, forKey: SharedKeys.happeningCatalog)
        let legacy = try vault.legacyArchive()!
        let history = try LegacyDeviceHistory(archive: legacy)
        try expect(history.days.map(\.id) == ["2026-01-05", "2026-01-04", "2026-01-03", "2026-01-02", "2026-01-01"], "all legacy day sources must stay visible, including unreadable Canvas and spending-only days")
        let days = Dictionary(uniqueKeysWithValues: history.days.map { ($0.id, $0) })
        try expect(days["2026-01-02"]?.titles == ["Original title"], "Canvas's frozen original title must survive")
        try expect(days["2026-01-01"]?.titles == ["Archived title"], "legacy category snapshots must resolve archived catalog, never B's catalog")
        try expect(days["2026-01-05"]?.titles == ["Archived title"], "unsnapshotted current additions must remain visible")
        try expect(days["2026-01-02"]?.spent == 8 && days["2026-01-03"]?.spent == 9, "readable archived spending must appear with its own day")
        try expect(legacy.fileData(at: days["2026-01-02"]!.previewPath!) == preview, "saved preview bytes must be readable without activation")
        try expect(legacy.fileData(at: "canvases/canvas_2026-01-02.json") == original, "projection must preserve unknown artwork bytes")
        try expect(legacy.fileData(at: "canvases/canvas_2026-01-04.json") == corrupt, "unreadable files must remain untouched")
        try expect(vault.activeOwner == "account-B" && defaults.data(forKey: SharedKeys.happeningCatalog) == bCatalog, "reading previous device history must not activate or mutate any account")
        print("PASS legacy read-only history")
    }
}
