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
