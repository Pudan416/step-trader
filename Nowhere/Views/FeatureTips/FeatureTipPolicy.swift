import Foundation

/// First offers keep the existing cold-launch thresholds. Scheduling and history
/// live separately from SwiftUI so time, persistence and dismissal are testable.
enum FeatureTip: String, Identifiable, CaseIterable, Codable {
    case widgets
    case wallpaper

    var id: String { rawValue }
    static var orderedByPriority: [FeatureTip] { [.widgets, .wallpaper] }
    var minLaunch: Int { self == .widgets ? 5 : 7 }
}

/// Use from the main actor in the app. Tests use isolated defaults and a clock.
final class FeatureTipStore {
    static let shared = FeatureTipStore()
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let historyKey = "featureTipHistory_v2"
    private let promptDateKey = "featureTipLastPrompt_v2"

    private struct History: Codable {
        var presentations = 0
        var snoozedAt: Date?
        var canvasDays: [String] = []
        var completed = false
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    private func history(for tip: FeatureTip) -> History {
        if let data = defaults.data(forKey: "\(historyKey)_\(tip.rawValue)"),
           let history = try? JSONDecoder().decode(History.self, from: data) {
            return history
        }
        // v1 did not distinguish acceptance from dismissal. Preserve its opt-out.
        return History(completed: defaults.bool(forKey: "featureTipSeen_\(tip.rawValue)_v1"))
    }

    private func save(_ history: History, for tip: FeatureTip) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: "\(historyKey)_\(tip.rawValue)")
    }

    func canPresentPrompt(now: Date = .now) -> Bool {
        guard let last = defaults.object(forKey: promptDateKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= 48 * 60 * 60
    }

    func isEligible(_ tip: FeatureTip, launchCount: Int, hasCanvas: Bool,
                    featureUsed: Bool, now: Date = .now) -> Bool {
        let history = history(for: tip)
        guard launchCount >= tip.minLaunch, !featureUsed, !history.completed,
              tip != .wallpaper || hasCanvas,
              canPresentPrompt(now: now), history.presentations < 2 else { return false }
        if history.presentations == 0 { return true }
        guard let snoozedAt = history.snoozedAt else { return false }
        return now.timeIntervalSince(snoozedAt) >= 7 * 24 * 60 * 60
            && history.canvasDays.count >= 3
    }

    func recordPresentation(_ tip: FeatureTip, now: Date = .now) {
        var history = history(for: tip)
        guard !history.completed, history.presentations < 2 else { return }
        history.presentations += 1
        // If the process exits while the sheet is visible, recover as "later".
        history.snoozedAt = now
        history.canvasDays = []
        save(history, for: tip)
        defaults.set(now, forKey: promptDateKey)
    }

    func recordDismissal(_ tip: FeatureTip, now: Date = .now) {
        var history = history(for: tip)
        guard !history.completed, history.presentations > 0 else { return }
        history.snoozedAt = now
        history.canvasDays = []
        save(history, for: tip)
    }

    func recordAcceptance(_ tip: FeatureTip) {
        var history = history(for: tip)
        history.completed = true
        save(history, for: tip)
    }

    func recordReviewRequest(now: Date = .now) {
        defaults.set(now, forKey: promptDateKey)
    }

    func recordCanvasUse(now: Date = .now) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: now)
        let day = "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        for tip in FeatureTip.allCases {
            var history = history(for: tip)
            guard !history.completed, history.presentations == 1,
                  let snoozedAt = history.snoozedAt,
                  calendar.startOfDay(for: now) > calendar.startOfDay(for: snoozedAt),
                  history.canvasDays.count < 3, !history.canvasDays.contains(day) else { continue }
            history.canvasDays.append(day)
            save(history, for: tip)
        }
    }

    /// Used by the existing developer action, including migration flags.
    func reset() {
        for tip in FeatureTip.allCases {
            defaults.removeObject(forKey: "\(historyKey)_\(tip.rawValue)")
            defaults.removeObject(forKey: "featureTipSeen_\(tip.rawValue)_v1")
        }
        defaults.removeObject(forKey: promptDateKey)
    }
}
