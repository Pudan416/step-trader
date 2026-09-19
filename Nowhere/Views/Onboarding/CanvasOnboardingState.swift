import Foundation
import Observation

/// Persists completion separately from the tour's transient navigation state.
/// Existing installs keep their completion; replaying the tour never erases data.
@Observable
@MainActor
final class CanvasOnboardingState {
    static let completionKey = "onboarding_state_v1"
    static let resettableKeys = [
        completionKey,
        "hasCompletedOnboarding_v1",
        "hasSeenIntro_v3",
        "hasSeenEnergySetup_v1",
        "hasMigratedOnboarding_v1",
        "shouldStartCoachMark"
    ]

    static let shared: CanvasOnboardingState = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let defaults: UserDefaults? = arguments.contains("debug-canvas-tour-fixtures") ? nil : .standard
        // This launch-only fixture resets before the process claims its first
        // automatic presentation. The Developer action instead requires restart.
        if arguments.contains("canvas-onboarding-test-first-launch") {
            resettableKeys.forEach { defaults?.removeObject(forKey: $0) }
        }
        return CanvasOnboardingState(defaults: defaults)
        #else
        return CanvasOnboardingState(defaults: .standard)
        #endif
    }()

    private(set) var isCompleted: Bool
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var hasClaimedAutomaticStart = false

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let currentComplete = (defaults?.integer(forKey: Self.completionKey) ?? 0) >= 1
        let legacyComplete = defaults?.bool(forKey: "hasCompletedOnboarding_v1") == true
            || (defaults?.bool(forKey: "hasSeenIntro_v3") == true
                && defaults?.bool(forKey: "hasSeenEnergySetup_v1") == true)
        isCompleted = currentComplete || legacyComplete
        if isCompleted && !currentComplete {
            defaults?.set(1, forKey: Self.completionKey)
        }
    }

    /// A root rebuild or background transition cannot present another tour.
    /// Explicit tour starts also claim this slot to avoid a bootstrap race.
    @discardableResult
    func claimAutomaticStart() -> Bool {
        guard !isCompleted, !hasClaimedAutomaticStart else { return false }
        hasClaimedAutomaticStart = true
        return true
    }

    func complete() {
        hasClaimedAutomaticStart = true
        defaults?.set(1, forKey: Self.completionKey)
        isCompleted = true
    }

    /// Developer test action: reset only onboarding flags, then restart the app.
    /// Burning this process's slot prevents a pending bootstrap from starting a
    /// first-launch session immediately after a mid-session reset.
    func resetForFirstLaunchTest() {
        Self.resettableKeys.forEach { defaults?.removeObject(forKey: $0) }
        hasClaimedAutomaticStart = true
        isCompleted = false
    }
}
