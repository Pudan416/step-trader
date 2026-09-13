import Foundation

protocol DayObjectsTransportClock: Sendable {
    func now() -> TimeInterval
    func sleep(untilHostTime hostTime: TimeInterval) async throws
}

protocol DayObjectsAudioHostTimeProviding: Sendable {
    func hostTimeSeconds() -> TimeInterval
}

struct SystemDayObjectsAudioHostTimeProvider: DayObjectsAudioHostTimeProviding {
    func hostTimeSeconds() -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

struct HostTimeDayObjectsTransportClock: DayObjectsTransportClock {
    private let hostTimeProvider: any DayObjectsAudioHostTimeProviding
    private let schedulingLookaheadSeconds: TimeInterval

    init(
        hostTimeProvider: any DayObjectsAudioHostTimeProviding = SystemDayObjectsAudioHostTimeProvider(),
        schedulingLookaheadSeconds: TimeInterval = 0.1
    ) {
        self.hostTimeProvider = hostTimeProvider
        self.schedulingLookaheadSeconds = max(0, schedulingLookaheadSeconds)
    }

    func now() -> TimeInterval {
        hostTimeProvider.hostTimeSeconds()
    }

    func sleep(untilHostTime hostTime: TimeInterval) async throws {
        let schedulingTime = hostTime - schedulingLookaheadSeconds
        let delay = schedulingTime - now()
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

/// Some voices expose immediate controls rather than sample-time scheduling.
/// Keep their entire musical event (attack, legato and release) at the same
/// audible deadline as the drums, whose buffers are submitted during lookahead.
/// One worker preserves transport order, including events sharing a deadline.
@MainActor
final class DayObjectsPlaybackDeadlineQueue {
    private struct Pending {
        let hostTime: TimeInterval
        let perform: @MainActor () -> Void
    }

    private let clock: any DayObjectsTransportClock
    private var pending: [Pending] = []
    private var worker: Task<Void, Never>?
    private var generation: UInt64 = 0

    var activeTaskCount: Int { worker == nil ? 0 : 1 }

    init(clock: any DayObjectsTransportClock = HostTimeDayObjectsTransportClock(schedulingLookaheadSeconds: 0)) {
        self.clock = clock
    }

    /// Returns false for an already-due event so offline rendering and the
    /// transport's first frame retain their synchronous result.
    func deferUntilDeadline(_ hostTime: TimeInterval, perform: @escaping @MainActor () -> Void) -> Bool {
        guard hostTime.isFinite else { return true }
        guard hostTime > clock.now() || !pending.isEmpty else { return false }
        pending.append(.init(hostTime: hostTime, perform: perform))
        guard worker == nil else { return true }
        let epoch = generation
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // A canceled worker may resume after a new playback epoch has
                // already submitted work. Only clean up our own generation.
                if self.generation == epoch {
                    self.worker = nil
                    self.pending.removeAll(keepingCapacity: true)
                }
            }
            while let next = self.pending.first {
                do { try await self.clock.sleep(untilHostTime: next.hostTime) }
                catch { return }
                guard !Task.isCancelled, self.generation == epoch else { return }
                self.pending.removeFirst()
                next.perform()
                guard self.generation == epoch else { return }
            }
        }
        return true
    }

    func cancel() {
        generation &+= 1
        worker?.cancel()
        worker = nil
        pending.removeAll(keepingCapacity: true)
    }
}

final class ManualDayObjectsTransportClock: DayObjectsTransportClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentHostTime: TimeInterval
    private var waiters: [UUID: Waiter] = [:]
    private var cancelledWaiterIDs: Set<UUID> = []

    init(now: TimeInterval = 0) {
        currentHostTime = now
    }

    func now() -> TimeInterval {
        lock.withLock { currentHostTime }
    }

    var pendingWaiterCount: Int {
        lock.withLock { waiters.count }
    }

    func advance(by interval: TimeInterval) {
        advance(to: now() + max(0, interval))
    }

    func advance(to hostTime: TimeInterval) {
        let dueWaiters: [Waiter] = lock.withLock {
            currentHostTime = max(currentHostTime, hostTime)
            let dueIDs = waiters.compactMap { id, waiter in
                waiter.deadline <= currentHostTime ? id : nil
            }
            return dueIDs.compactMap { waiters.removeValue(forKey: $0) }
        }
        dueWaiters
            .sorted { $0.deadline < $1.deadline }
            .forEach { $0.continuation.resume() }
    }

    func sleep(untilHostTime hostTime: TimeInterval) async throws {
        try Task.checkCancellation()
        let waiterID = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Resolution {
                    case wait
                    case ready
                    case cancelled
                }

                let resolution: Resolution = lock.withLock {
                    if cancelledWaiterIDs.remove(waiterID) != nil || Task.isCancelled {
                        return .cancelled
                    }
                    if hostTime <= currentHostTime {
                        return .ready
                    }
                    waiters[waiterID] = Waiter(deadline: hostTime, continuation: continuation)
                    return .wait
                }

                switch resolution {
                case .wait:
                    break
                case .ready:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancelWaiter(id: waiterID)
        }
    }

    private func cancelWaiter(id: UUID) {
        let waiter: Waiter? = lock.withLock {
            if let waiter = waiters.removeValue(forKey: id) {
                return waiter
            }
            cancelledWaiterIDs.insert(id)
            return nil
        }
        waiter?.continuation.resume(throwing: CancellationError())
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try operation()
    }
}
