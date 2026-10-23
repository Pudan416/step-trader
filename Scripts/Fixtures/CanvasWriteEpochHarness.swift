import Foundation
import CoreGraphics

/*__STATE__*/
struct DayCanvas: Codable {
    var dayKey = "fixture-day"
    var marker: String
    var localCloudOwnerID: String? = "fixture-owner"
    var pendingCloudUpload: Bool?
    mutating func freezeNativeBackgroundIfNeeded() {}
}
enum ModernPaletteCategory: Hashable { case fixture }
enum ModernPaletteSelection { static let all: Set<ModernPaletteCategory> = [.fixture] }
extension Notification.Name { static let todayCanvasStorageDidChange = Self("fixture.canvas.changed") }
struct Logger: Sendable { func error(_ message: String) {} }
enum SharedKeys { static let appGroupId = "fixture-app-group" }
final class FixtureFileManager: @unchecked Sendable {
    let root: URL
    init(_ root: URL) { self.root = root }
    func containerURL(forSecurityApplicationGroupIdentifier: String) -> URL? { root }
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }
}
@MainActor final class UIImage {
    let marker: String
    let size = CGSize(width: 10, height: 10)
    let scale: CGFloat = 1
    init(_ marker: String) { self.marker = marker }
    func pngData() -> Data? { Data(marker.utf8) }
    func draw(at: CGPoint) { Raster.data = Data(marker.utf8) }
}
@MainActor enum Raster { static var data = Data() }
@MainActor final class UIGraphicsImageRendererFormat { var scale: CGFloat = 1; var opaque = false }
@MainActor final class UIGraphicsImageRenderer {
    init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    func jpegData(withCompressionQuality: Double, actions: (Int) -> Void) -> Data { actions(0); return Raster.data }
}
@MainActor final class CanvasStorageService {
    static var shared: CanvasStorageService!
    nonisolated static let log = Logger()
    let fileManager: FixtureFileManager
    let root: URL
    /*__BARRIER_PROPERTY__*/
    static let widgetSnapshotQueue = CanvasWidgetSnapshotQueue { canvas, categories in
        await CanvasStorageService.shared.saveWidgetSnapshot(for: canvas, paletteCategories: categories)
        CanvasStorageService.shared.noteFinished(canvas.marker)
    }
    var renderStarted: CheckedContinuation<Void, Never>?
    var delayedRender: CheckedContinuation<Void, Never>?
    var secondRenderStarted: CheckedContinuation<Void, Never>?
    var delayedSecondRender: CheckedContinuation<Void, Never>?
    var finished: [String] = []
    var finishedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    init(root: URL) { self.root = root; fileManager = FixtureFileManager(root) }
    func canvasFileURL(for day: String) -> URL { root.appendingPathComponent("canvas.json") }
    func snapshotURL(for day: String) -> URL { root.appendingPathComponent("snapshot.png") }
    func renderedSnapshot(canvas: DayCanvas, size: CGSize, scale: CGFloat, paletteCategories: Set<ModernPaletteCategory>) async -> UIImage? {
        if canvas.marker == "A" {
            await withCheckedContinuation { continuation in
                delayedRender = continuation
                renderStarted?.resume(); renderStarted = nil
            }
        }
        if canvas.marker == "queue-B" {
            await withCheckedContinuation { continuation in
                delayedSecondRender = continuation
                secondRenderStarted?.resume(); secondRenderStarted = nil
            }
        }
        return UIImage(canvas.marker)
    }
    func noteFinished(_ marker: String) {
        finished.append(marker)
        finishedWaiters.removeValue(forKey: marker)?.resume()
    }
    func waitForFinished(_ marker: String) async {
        if !finished.contains(marker) { await withCheckedContinuation { finishedWaiters[marker] = $0 } }
    }
    /*__METHODS__*/
}
@MainActor
/*__QUEUE__*/

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: " + message); exit(1) }
}
@main struct Runner {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = CanvasStorageService(root: root)
        CanvasStorageService.shared = storage
        let a = DayCanvas(marker: "A", localCloudOwnerID: "owner-a")
        let b = DayCanvas(marker: "B", localCloudOwnerID: "owner-b")
        switch CommandLine.arguments[1] {
        case "active-write":
            let barrier = storage.writeBarrier
            let epoch = barrier.capture()
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let invalidated = DispatchSemaphore(value: 0)
            let url = root.appendingPathComponent("active-write.txt")
            let writer = Task.detached {
                try barrier.performWrite(epoch: epoch) {
                    entered.signal()
                    release.wait()
                    try Data("A".utf8).write(to: url, options: .atomic)
                }
            }
            entered.wait()
            let invalidate = Task.detached { barrier.suspend(); invalidated.signal() }
            expect(invalidated.wait(timeout: .now() + .milliseconds(30)) == .timedOut,
                   "invalidation returned before an active disk write completed")
            release.signal()
            _ = try await writer.value
            await invalidate.value
            let written = try Data(contentsOf: url)
            expect(String(data: written, encoding: .utf8) == "A", "active atomic write did not complete before swap")
            expect(!barrier.performWrite(epoch: epoch) {}, "invalidated writer was readmitted")
        case "queue-switch", "queue-normal":
            let queue = CanvasStorageService.widgetSnapshotQueue
            queue.submit(a, categories: ModernPaletteSelection.all)
            if storage.delayedRender == nil { await withCheckedContinuation { storage.renderStarted = $0 } }
            queue.submit(DayCanvas(marker: "discarded"), categories: ModernPaletteSelection.all)
            if CommandLine.arguments[1] == "queue-switch" {
                await storage.invalidatePendingWritesForAccountSwitch()
                storage.resumeWritesAfterAccountSwitch()
                queue.submit(DayCanvas(marker: "queue-B"), categories: ModernPaletteSelection.all)
                if storage.delayedSecondRender == nil { await withCheckedContinuation { storage.secondRenderStarted = $0 } }
                storage.delayedRender?.resume(); storage.delayedRender = nil
                await storage.waitForFinished("A")
                queue.submit(DayCanvas(marker: "C"), categories: ModernPaletteSelection.all)
                for _ in 0..<100 { await Task.yield() }
                expect(!storage.finished.contains("C"), "old worker cleared incoming worker ownership")
                storage.delayedSecondRender?.resume(); storage.delayedSecondRender = nil
                await storage.waitForFinished("C")
                expect(storage.finished == ["A", "queue-B", "C"], "old pending export survived cancellation")
            } else {
                queue.submit(DayCanvas(marker: "C"), categories: ModernPaletteSelection.all)
                for _ in 0..<100 { await Task.yield() }
                expect(storage.finished.isEmpty, "normal widget exports overlapped")
                storage.delayedRender?.resume(); storage.delayedRender = nil
                await storage.waitForFinished("C")
                expect(storage.finished == ["A", "C"], "normal queue did not keep only latest pending canvas")
            }
            let contents = try Data(contentsOf: root.appendingPathComponent("widget_snapshots/canvas_today.jpg"))
            expect(String(data: contents, encoding: .utf8) == "C", "latest queued export did not persist")
        case "json":
            let oldEpoch = storage.captureWriteEpoch()
            expect(storage.saveCanvas(a), "normal JSON write rejected")
            await storage.invalidatePendingWritesForAccountSwitch()
            let duringSwap = storage.captureWriteEpoch()
            expect(!storage.saveCanvas(a), "writes were allowed while account swap was suspended")
            storage.resumeWritesAfterAccountSwitch()
            expect(storage.saveCanvas(b), "incoming JSON write rejected")
            expect(!storage.saveCanvas(a, expectedEpoch: oldEpoch), "old callback wrote into incoming account")
            expect(!storage.saveCanvas(a, expectedEpoch: duringSwap), "work created while suspended became valid")
            let actual = try JSONDecoder().decode(DayCanvas.self, from: Data(contentsOf: storage.canvasFileURL(for: a.dayKey)))
            expect(actual.marker == "B" && actual.localCloudOwnerID == b.localCloudOwnerID && actual.pendingCloudUpload == true, "JSON metadata or account contents changed")
        default:
            let isWidget = CommandLine.arguments[1] == "widget"
            let task = Task { @MainActor in
                if isWidget { await storage.saveWidgetSnapshot(for: a) }
                else { await storage.saveSnapshot(for: a) }
            }
            // Wait for the actual production export to suspend inside rendering.
            if storage.delayedRender == nil {
                await withCheckedContinuation { storage.renderStarted = $0 }
            }
            await storage.invalidatePendingWritesForAccountSwitch()
            storage.resumeWritesAfterAccountSwitch()
            if isWidget { await storage.saveWidgetSnapshot(for: b) }
            else { await storage.saveSnapshot(for: b) }
            storage.delayedRender?.resume(); storage.delayedRender = nil
            await task.value
            let url = isWidget ? root.appendingPathComponent("widget_snapshots/canvas_today.jpg") : storage.snapshotURL(for: a.dayKey)
            let contents = try Data(contentsOf: url)
            expect(String(data: contents, encoding: .utf8) == "B", "delayed A export overwrote incoming B")
        }
    }
}
