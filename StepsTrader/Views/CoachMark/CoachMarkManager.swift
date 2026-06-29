import SwiftUI

@Observable
@MainActor
final class CoachMarkManager {
    var currentStep: CoachMarkStep? = nil
    var isActive: Bool = false

    @ObservationIgnored private var hasTicketGroups: () -> Bool = { false }

    static let actionNotification = Notification.Name("CoachMarkAction")

    func configure(hasTicketGroups: @escaping () -> Bool) {
        self.hasTicketGroups = hasTicketGroups
    }

    static func postAction(for step: CoachMarkStep) {
        NotificationCenter.default.post(name: actionNotification, object: step)
    }

    func start() {
        currentStep = .colorBalance
        isActive = true
        trackStepViewed()
    }

    func advance() {
        guard let current = currentStep else { finish(); return }
        trackStepCompleted(action: "next")
        goToNext(after: current)
    }

    func completeAction(for step: CoachMarkStep) {
        guard currentStep == step else { return }
        trackStepCompleted(action: "action")
        goToNext(after: step)
    }

    func skipAll() {
        trackStepCompleted(action: "skip_all")
        finish()
    }

    func tabRawValue(for step: CoachMarkStep) -> Int? {
        switch step {
        case .colorBalance, .expandChevron, .categoriesRevealed,
             .tapPlusButton, .categoryExplain, .tapMind,
             .spotlightFocusing, .tapAddToCanvas,
             .canvasTrace, .goToFeeds:
            return 0
        case .tapFeedsTab:
            return nil
        case .feedsExplain, .tapUnlockPill, .unlockSuccess:
            return 1
        case .allSet:
            return nil
        }
    }

    // MARK: - Private

    private func goToNext(after current: CoachMarkStep) {
        let allSteps = CoachMarkStep.allCases
        guard let idx = allSteps.firstIndex(of: current) else { finish(); return }
        let nextIdx = allSteps.index(after: idx)
        guard nextIdx < allSteps.endIndex else { finish(); return }

        var next = allSteps[nextIdx]

        // No blocked-app group → the whole Feeds leg of the tour is pointless
        // (the tab is empty and there is nothing to unlock). Jump straight to
        // the closing step instead of marching the user to an empty tab.
        if next.requiresTicketGroups && !hasTicketGroups() {
            next = .allSet
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
        trackStepViewed()
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = nil
            isActive = false
        }
    }

    // MARK: - Analytics

    private func trackStepViewed() {
        guard let step = currentStep else { return }
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "coach_mark_step_viewed",
                properties: [
                    "step": String(describing: step),
                    "step_index": String(step.rawValue)
                ]
            )
        }
    }

    private func trackStepCompleted(action: String) {
        guard let step = currentStep else { return }
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "coach_mark_step_completed",
                properties: [
                    "step": String(describing: step),
                    "step_index": String(step.rawValue),
                    "action": action
                ]
            )
        }
    }
}
