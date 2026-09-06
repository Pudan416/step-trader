import Foundation
import QuartzCore
import SwiftUI

struct CanvasHappeningSpawnResult {
    let canvas: DayCanvas
    let entry: OptionEntry
}

struct CanvasHappeningRemovalResult {
    let canvas: DayCanvas
    let removedElement: CanvasElement
}

struct CanvasHappeningReconciliation: Equatable {
    let entriesToAdd: [OptionEntry]
    let entryIDsToRemove: [String]
    let duplicateElementIDsToRemove: [UUID]

    init(
        entriesToAdd: [OptionEntry],
        entryIDsToRemove: [String],
        duplicateElementIDsToRemove: [UUID] = []
    ) {
        self.entriesToAdd = entriesToAdd
        self.entryIDsToRemove = entryIDsToRemove
        self.duplicateElementIDsToRemove = duplicateElementIDsToRemove
    }
}

enum CanvasHappeningReconciliationPolicy {
    static func reconcileIfReady(
        canvasLoaded: Bool,
        appModelIsBootstrapping: Bool,
        canvas: DayCanvas,
        entries: [OptionEntry],
        dayKey: String,
        now: Date
    ) -> CanvasHappeningReconciliation? {
        guard canvasLoaded, !appModelIsBootstrapping else { return nil }
        return CanvasHappeningReconciler.reconcile(
            canvas: canvas,
            entries: entries,
            dayKey: dayKey,
            now: now
        )
    }
}

/// Repairs the denormalized daily-entry projection after a Canvas load.
/// Canvas elements are authoritative; existing entry identities survive when
/// either their stable UUID or, for legacy data, their happening id matches.
enum CanvasHappeningReconciler {
    static func reconcile(
        canvas: DayCanvas,
        entries: [OptionEntry],
        dayKey: String,
        now: Date
    ) -> CanvasHappeningReconciliation {
        guard canvas.dayKey == dayKey else {
            return CanvasHappeningReconciliation(entriesToAdd: [], entryIDsToRemove: [])
        }

        var seenOptionIDs = Set<String>()
        var canonicalElementIndices = [Int]()
        var duplicateElementIDs = [UUID]()
        for index in canvas.elements.indices {
            let element = canvas.elements[index]
            if seenOptionIDs.insert(element.optionId).inserted {
                canonicalElementIndices.append(index)
            } else {
                duplicateElementIDs.append(element.id)
            }
        }

        let currentEntries = entries.filter { $0.dayKey == dayKey }
        var unmatchedEntryIndices = Set(currentEntries.indices)
        var unmatchedElementIndices = Set(canonicalElementIndices)
        var conflictingEntryIndices = Set<Int>()
        var conflictingElementIndices = Set<Int>()

        // Prefer the durable element/entry identity. Requiring the happening
        // id to agree lets Canvas repair a corrupt entry instead of preserving
        // stale domain metadata merely because its UUID happens to match.
        for elementIndex in canonicalElementIndices {
            let element = canvas.elements[elementIndex]
            guard let entryIndex = currentEntries.indices.first(where: {
                unmatchedEntryIndices.contains($0)
                    && UUID(uuidString: currentEntries[$0].id) == element.id
            }) else { continue }
            guard currentEntries[entryIndex].optionId == element.optionId else {
                // Reserve both sides of a conflicting stable identity. Neither
                // may be rescued by the legacy option-only fallback: Canvas
                // must replace the stale entry with its canonical metadata.
                conflictingEntryIndices.insert(entryIndex)
                conflictingElementIndices.insert(elementIndex)
                continue
            }
            unmatchedEntryIndices.remove(entryIndex)
            unmatchedElementIndices.remove(elementIndex)
        }

        // Older entries did not necessarily share the Canvas UUID. Keep their
        // existing ids by pairing each remaining occurrence by happening id.
        for elementIndex in unmatchedElementIndices.sorted() {
            guard !conflictingElementIndices.contains(elementIndex) else { continue }
            let element = canvas.elements[elementIndex]
            guard let entryIndex = currentEntries.indices.first(where: {
                unmatchedEntryIndices.contains($0)
                    && !conflictingEntryIndices.contains($0)
                    && currentEntries[$0].optionId == element.optionId
            }) else { continue }
            unmatchedEntryIndices.remove(entryIndex)
            unmatchedElementIndices.remove(elementIndex)
        }

        let additions = unmatchedElementIndices.sorted().map { index in
            let element = canvas.elements[index]
            return OptionEntry(
                id: element.id.uuidString,
                dayKey: dayKey,
                optionId: element.optionId,
                colorHex: element.hexColor,
                timestamp: now,
                assetVariant: element.assetVariant
            )
        }
        let removals = unmatchedEntryIndices.sorted().map { currentEntries[$0].id }
        return CanvasHappeningReconciliation(
            entriesToAdd: additions,
            entryIDsToRemove: removals,
            duplicateElementIDsToRemove: duplicateElementIDs
        )
    }
}

@MainActor
enum CanvasHappeningReconciliationTransaction {
    static func commit(
        _ reconciliation: CanvasHappeningReconciliation,
        model: AppModel
    ) {
        commit(
            reconciliation,
            model: model,
            syncOperations: enqueueCloudSync
        )
    }

    static func commit(
        _ reconciliation: CanvasHappeningReconciliation,
        model: AppModel,
        syncOperations: ([CanvasHappeningReconciliationSyncOperation]) -> Void
    ) {
        // Removal first allows a malformed same-identity entry to be replaced
        // from Canvas without being rejected as a duplicate for the day.
        for entryID in reconciliation.entryIDsToRemove {
            model.removeAddition(entryId: entryID, syncToCloud: false)
        }
        var committedEntries = [OptionEntry]()
        for entry in reconciliation.entriesToAdd {
            guard let committed = model.addHappening(
                id: entry.optionId,
                colorHex: entry.colorHex,
                assetVariant: entry.assetVariant,
                at: entry.timestamp,
                recordUse: false,
                entryId: entry.id,
                syncToCloud: false
            ) else { continue }
            committedEntries.append(committed)
        }

        let operations = reconciliation.entryIDsToRemove.map {
            CanvasHappeningReconciliationSyncOperation.delete(entryID: $0)
        } + committedEntries.map(CanvasHappeningReconciliationSyncOperation.upsert)
        if !operations.isEmpty {
            syncOperations(operations)
        }
    }

    private static func enqueueCloudSync(
        _ operations: [CanvasHappeningReconciliationSyncOperation]
    ) {
        Task {
            for operation in operations {
                switch operation {
                case let .delete(entryID):
                    await SupabaseSyncService.shared.deleteOptionEntry(id: entryID)
                case let .upsert(entry):
                    await SupabaseSyncService.shared.syncOptionEntry(entry)
                }
            }
        }
    }
}

enum CanvasHappeningReconciliationSyncOperation: Equatable {
    case delete(entryID: String)
    case upsert(OptionEntry)
}

/// Persists the canonical post-removal canvas, including a valid empty canvas.
/// The Bool result must decide whether the matching domain entry is removed.
enum CanvasHappeningRemovalPersistence {
    static func persist(
        _ canvas: DayCanvas,
        save: (DayCanvas) -> Bool
    ) -> Bool {
        save(canvas)
    }
}

/// Persists the canonical canvas before committing the matching day entry.
/// A failed or not-yet-loaded canvas therefore cannot consume a palette zone.
@MainActor
enum CanvasHappeningSpawnTransaction {
    static func commit(
        canvasLoaded: Bool,
        canvas: DayCanvas,
        model: AppModel,
        element: CanvasElement,
        recordUse: Bool,
        at date: Date,
        persist: (DayCanvas) -> Bool
    ) -> CanvasHappeningSpawnResult? {
        let capturedDayKey = AppModel.dayKey(for: date)
        guard canvasLoaded,
              canvas.dayKey == capturedDayKey,
              model.canAddHappening(id: element.optionId, on: date) else {
            return nil
        }

        var canonical = canvas
        canonical.elements.append(element)
        canonical.lastModified = date
        guard persist(canonical) else { return nil }

        guard let entry = model.addHappening(
            id: element.optionId,
            colorHex: element.hexColor,
            assetVariant: element.assetVariant,
            at: date,
            recordUse: recordUse,
            entryId: element.id.uuidString
        ) else {
            // The preflight and commit are synchronous on MainActor, so this is
            // defensive. Restore the previous durable canvas if the invariant
            // is ever broken by a future model change.
            _ = persist(canvas)
            return nil
        }

        return CanvasHappeningSpawnResult(canvas: canonical, entry: entry)
    }
}

@MainActor
enum CanvasHappeningRemovalTransaction {
    static func commit(
        canvasLoaded: Bool,
        canvas: DayCanvas,
        model: AppModel,
        happeningID: String,
        at date: Date,
        persist: (DayCanvas) -> Bool
    ) -> CanvasHappeningRemovalResult? {
        let capturedDayKey = AppModel.dayKey(for: date)
        guard canvasLoaded,
              canvas.dayKey == capturedDayKey,
              let index = canvas.elements.firstIndex(where: { $0.optionId == happeningID })
        else { return nil }
        var canonical = canvas
        let removed = canonical.elements.remove(at: index)
        canonical.lastModified = date
        guard persist(canonical) else { return nil }
        model.removeAddition(entryId: removed.id.uuidString)
        return CanvasHappeningRemovalResult(canvas: canonical, removedElement: removed)
    }
}

/// Render-only launch positions. Canonical `DayCanvas` data always keeps the
/// generated destination so an unrelated save can never persist a flight frame.
struct CanvasSpawnPresentationState {
    private var origins: [UUID: CGPoint] = [:]

    mutating func stage(elementID: UUID, origin: CGPoint) {
        origins[elementID] = origin
    }

    mutating func complete(elementID: UUID) {
        origins.removeValue(forKey: elementID)
    }

    func renderedElements(from canonical: [CanvasElement]) -> [CanvasElement] {
        canonical.map { element in
            guard let origin = origins[element.id] else { return element }
            var presented = element
            presented.basePosition = origin
            return presented
        }
    }
}

/// A direct, durable request/acknowledgement channel between one MainTabView
/// and its intended GalleryView. Requests survive lazy tab materialization and
/// are cleared only by the selected Gallery when it can present.
struct CanvasPaletteRouteState: Equatable {
    private(set) var pendingRequestID: UUID?

    mutating func requestOpen(id: UUID = UUID()) {
        pendingRequestID = id
    }

    mutating func cancelPendingRequest() {
        pendingRequestID = nil
    }

    mutating func consumeIfReady(
        isCanvasSelected: Bool,
        canPresent: Bool
    ) -> UUID? {
        guard isCanvasSelected, canPresent, let pendingRequestID else {
            return nil
        }
        self.pendingRequestID = nil
        return pendingRequestID
    }

    static func blocksTabBar(
        isCanvasSelected: Bool,
        isPaletteVisible: Bool
    ) -> Bool {
        isCanvasSelected && isPaletteVisible
    }

    static func shouldClosePalette(
        isCanvasSelected: Bool,
        isPaletteVisible: Bool
    ) -> Bool {
        !isCanvasSelected && isPaletteVisible
    }
}

@MainActor
enum CanvasDisplayFrameScheduler {
    static func waitForOriginFrame() async {
        // One tick admits the staged state to the render cycle; the second
        // guarantees a completed origin frame before destination animation.
        await waitForNextFrame()
        await waitForNextFrame()
    }

    private static func waitForNextFrame() async {
        let waiter = DisplayLinkWaiter()
        await waiter.wait()
    }
}

@MainActor
private final class DisplayLinkWaiter: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?
    private var displayLink: CADisplayLink?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let displayLink = CADisplayLink(target: self, selector: #selector(frameDidRender))
            self.displayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }
    }

    @objc private func frameDidRender() {
        displayLink?.invalidate()
        displayLink = nil
        continuation?.resume()
        continuation = nil
    }
}

extension Notification.Name {
    static let canvasElementSpawnRequested = Notification.Name("canvasElementSpawnRequested")
    static let canvasElementRemoveRequested = Notification.Name("canvasElementRemoveRequested")
    static let canvasElementRerollRequested = Notification.Name("canvasElementRerollRequested")
}

enum MetricOverlayKind: Identifiable, Equatable {
    case steps
    case sleep
    case happenings

    var id: String {
        switch self {
        case .steps: return "steps"
        case .sleep: return "sleep"
        case .happenings: return "happenings"
        }
    }
}
