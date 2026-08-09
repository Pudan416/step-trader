import Foundation
import QuartzCore
import SwiftUI

struct CanvasHappeningSpawnResult {
    let canvas: DayCanvas
    let entry: OptionEntry
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
