import Foundation
// INSERT_BARRIER
struct DayCanvas {
    var dayKey: String
    var needsRemoteHydration = false
    var pendingCloudUpload: Bool? = nil
    var localCloudOwnerID: String? = "owned"
    var elements = [1]
    var artworkRecipe: Int? = nil
    var remixSeed: Int? = nil
}
enum ModernPaletteCategory { case body }
enum ModernPaletteSelection { static func decode(_ raw: String) -> Set<ModernPaletteCategory> { [] } }
extension Notification.Name { static let historyThumbnailNeedsRefresh = Notification.Name("synthetic-refresh") }
@MainActor final class CanvasStorageService {
    static let shared = CanvasStorageService()
    let barrier = CanvasStorageWriteBarrier()
    var saves: [String] = []
    var widgets: [String] = []
    func captureWriteEpoch() -> CanvasStorageWriteEpoch { barrier.capture() }
    @discardableResult func saveCanvas(_ canvas: DayCanvas, expectedEpoch: CanvasStorageWriteEpoch? = nil) -> Bool {
        barrier.performWrite(epoch: expectedEpoch ?? captureWriteEpoch()) { saves.append(canvas.dayKey) }
    }
    func deleteCanvas(for dayKey: String, expectedEpoch: CanvasStorageWriteEpoch? = nil) {
        barrier.performWrite(epoch: expectedEpoch ?? captureWriteEpoch()) { saves.append("deleted-" + dayKey) }
    }
    func scheduleWidgetSnapshot(for canvas: DayCanvas, paletteCategories: Set<ModernPaletteCategory>) { widgets.append(canvas.dayKey) }
}
@MainActor final class SupabaseSyncService {
    static let shared = SupabaseSyncService()
    var uploads: [String] = []
    func syncDayCanvas(_ canvas: DayCanvas) async { uploads.append(canvas.dayKey) }
}
@MainActor final class AppModel {
    var isHistoryWorkSuspended = false
    func scheduleHistoryWork(_ body: @escaping @MainActor () async -> Void) { Task { await body() } }
}
@MainActor final class GalleryFixture {
    let model = AppModel()
    let canvasWriteEpoch = CanvasStorageService.shared.captureWriteEpoch()
    let isUnitTestHost = false
    let canvasLoaded = true
    let modernPaletteCategoriesRaw = ""
    var dayCanvas: DayCanvas
    init(owner: String) { dayCanvas = DayCanvas(dayKey: owner) }
    func run() { _ = saveCanvasLocally(); publishCanvasPersistence(dayCanvas) }
    func runSave() { _ = saveCanvasLocally() }
    // INSERT_CURRENT
    // INSERT_SAVE
    // INSERT_PUBLISH
    // INSERT_WIDGET
}
@main @MainActor struct GalleryAccountEpochHarness {
    static func main() async {
        let old = GalleryFixture(owner: "A")
        CanvasStorageService.shared.barrier.suspend()
        CanvasStorageService.shared.barrier.resume()
        old.run() // Old view callback starts only after B has resumed.
        for _ in 0..<10 { await Task.yield() }
        precondition(CanvasStorageService.shared.saves.isEmpty, "Old Gallery callback must not save A under B")
        precondition(CanvasStorageService.shared.widgets.isEmpty, "Old Gallery callback must not publish A widget under B")
        precondition(SupabaseSyncService.shared.uploads.isEmpty, "Old Gallery callback must not create new B-owned sync intent for A")
        let incoming = GalleryFixture(owner: "B")
        incoming.runSave()
        for _ in 0..<10 { await Task.yield() }
        precondition(CanvasStorageService.shared.saves == ["B"])
        precondition(CanvasStorageService.shared.widgets == ["B"])
        precondition(SupabaseSyncService.shared.uploads == ["B"])
        print("PASS retained Gallery epochs reject delayed outgoing save/upload/widget callbacks")
    }
}
