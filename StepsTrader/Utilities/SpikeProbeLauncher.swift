#if DEBUG
import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(DeviceActivity)
import DeviceActivity
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Spike scaffolding. Starts the Live Activity and both probe activities, so the
/// `DeviceActivityMonitor` extension gets two independent chances to reach ActivityKit.
/// Disposable — delete alongside `Shared/SpikeLiveActivityAttributes.swift` and the
/// probe section of the monitor extension. See `Feeds-Spike.md`.
enum SpikeProbeLauncher {
    struct Outcome {
        let ok: Bool
        let message: String
    }

    /// Minutes the Live Activity claims at the start, so a probe stepping it down by one
    /// is visible without reading logs.
    private static let startingMinutes = 10

    @MainActor
    static func start(groups: [TicketGroup]) async -> Outcome {
        #if canImport(ActivityKit) && canImport(DeviceActivity) && canImport(FamilyControls)
        let calendar = Calendar.current
        let now = Date()

        // Both schedules are expressed as times of day, so an interval that runs past
        // 23:59 wraps and DeviceActivity treats it as already ended — killing the monitor
        // before anything can fire. Refuse rather than start a probe that cannot report.
        let usageStart = now.addingTimeInterval(60)
        let probeStart = now.addingTimeInterval(2 * 60)
        let probeEnd = now.addingTimeInterval(20 * 60)
        let usageEnd = now.addingTimeInterval(26 * 60)
        guard calendar.isDate(now, inSameDayAs: usageEnd), calendar.isDate(now, inSameDayAs: probeEnd) else {
            return Outcome(ok: false, message: "Too close to midnight — the probe schedule would wrap past 23:59 and DeviceActivity would kill it. Retry after midnight.")
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return Outcome(ok: false, message: "Live Activities are off for Nowhere. Enable them in iOS Settings and retry.")
        }

        let defaults = UserDefaults.stepsTrader()

        // End any activity left over from a previous run, so two runs cannot be confused
        // for one another on the Lock Screen.
        for stale in Activity<SpikeLiveActivityAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }

        let initial = SpikeLiveActivityAttributes.ContentState(
            remainingMinutes: startingMinutes,
            updateCount: 0,
            lastUpdatedBy: SpikeTrigger.app.rawValue
        )

        let activity: Activity<SpikeLiveActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: SpikeLiveActivityAttributes(label: "Feeds spike"),
                content: ActivityContent(state: initial, staleDate: nil),
                pushType: nil
            )
        } catch {
            return Outcome(ok: false, message: "Couldn't start the Live Activity: \(error.localizedDescription)")
        }

        defaults.set(activity.id, forKey: SpikeProbe.activityIdKey)
        defaults.set(startingMinutes, forKey: SpikeProbe.remainingMinutesKey)
        defaults.removeObject(forKey: SpikeProbe.lastResultKey)

        let center = DeviceActivityCenter()
        center.stopMonitoring([
            DeviceActivityName(SpikeProbe.probeActivityName),
            DeviceActivityName(SpikeProbe.usageActivityName)
        ])

        var problems: [String] = []

        // Probe A — schedule-triggered. Needs no app usage at all.
        do {
            try center.startMonitoring(
                DeviceActivityName(SpikeProbe.probeActivityName),
                during: DeviceActivitySchedule(
                    intervalStart: calendar.dateComponents([.hour, .minute, .second], from: probeStart),
                    intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: probeEnd),
                    repeats: false
                )
            )
        } catch {
            problems.append("probe A failed: \(error.localizedDescription)")
        }

        // Probe B — the production callback, driven by a real minute of usage.
        //
        // The interval deliberately starts in a minute rather than at 00:00 as production
        // does. Thresholds count usage from the interval's start, so a full-day interval
        // would measure against however much the app was already used today — firing at
        // once, or never. A fresh interval measures from a known zero. The callback
        // exercised is identical; only the interval differs.
        if let group = groups.first(where: { !$0.selection.applicationTokens.isEmpty }) {
            let event = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: group.selection.categoryTokens,
                threshold: DateComponents(minute: 1)
            )
            do {
                try center.startMonitoring(
                    DeviceActivityName(SpikeProbe.usageActivityName),
                    during: DeviceActivitySchedule(
                        intervalStart: calendar.dateComponents([.hour, .minute, .second], from: usageStart),
                        intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: usageEnd),
                        repeats: false
                    ),
                    events: [DeviceActivityEvent.Name(SpikeProbe.usageEventName): event]
                )
            } catch {
                problems.append("probe B failed: \(error.localizedDescription)")
            }
        } else {
            problems.append("probe B skipped: no group with apps selected")
        }

        if problems.isEmpty {
            return Outcome(ok: true, message: "Both probes armed. A reports in ~3 min with the phone idle; B needs a minute inside a blocked app, starting a minute from now.")
        }
        return Outcome(ok: false, message: problems.joined(separator: " · "))
        #else
        return Outcome(ok: false, message: "ActivityKit / DeviceActivity unavailable in this build.")
        #endif
    }
}
#endif
