import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Spike scaffolding. Answers the one question `Feeds-Spec.md` blocks the timer on:
/// can a `DeviceActivityMonitor` extension reach ActivityKit at all?
///
/// Everything in this file is disposable — see `Feeds-Spike.md`. If the answer is no,
/// it is deleted whole; if yes, `SpikeLiveActivityAttributes` is replaced by the real
/// Feeds attributes and only the shape survives.
enum SpikeProbe {
    /// Schedule-triggered. Wakes the extension through `intervalDidStart` without a
    /// single minute of app usage, so the answer arrives in about three minutes.
    static let probeActivityName = "spikeProbe"

    /// Usage-triggered. The production path — one event at a 1-minute threshold on a
    /// real group's selection, reaching the extension via `eventDidReachThreshold`.
    static let usageActivityName = "spikeUsage"
    static let usageEventName = "spikeUsageTick"

    /// App-group key holding the id of the Live Activity the app started, so the
    /// extension can find the one it is meant to update.
    static let activityIdKey = "spike_liveActivityId"

    /// App-group key holding the minute count the app last published, so a probe can
    /// step it down and make a landed update visible at a glance.
    static let remainingMinutesKey = "spike_remainingMinutes"

    /// App-group key holding the last probe verdict. Separate from `monitorLogs`, which
    /// is capped at 30 entries and can roll over before the user reopens the app.
    static let lastResultKey = "spike_lastResult"

    /// How long the extension waits on the async `update` before giving up. The
    /// extension process is torn down shortly after a callback returns, so an
    /// unbounded wait would report a teardown as a refusal.
    static let updateTimeout: TimeInterval = 8
}

/// Which process wrote the current `ContentState`. This is the spike's actual answer:
/// anything beginning `monitor:` on the Lock Screen means the extension got through.
enum SpikeTrigger: String {
    case app = "app"
    case intervalDidStart = "monitor:intervalDidStart"
    case eventDidReachThreshold = "monitor:eventDidReachThreshold"
}

#if canImport(ActivityKit)
struct SpikeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Stands in for what the Feeds timer would show. Present only so a landed
        /// update is visible without reading logs.
        var remainingMinutes: Int

        /// Increments on every successful update, so a second update from the same
        /// trigger is still distinguishable from the first.
        var updateCount: Int

        /// Raw value of `SpikeTrigger`.
        var lastUpdatedBy: String
    }

    var label: String
}
#endif
