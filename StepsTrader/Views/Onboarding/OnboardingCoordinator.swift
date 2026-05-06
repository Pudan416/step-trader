import SwiftUI

/// Manages onboarding navigation state and permission gating.
/// Extracted from OnboardingStoriesView for testability.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    let slides: [OnboardingSlide]
    let flowVersion: String

    @Published var index: Int = 0
    @Published private(set) var didTriggerHealthRequest = false
    @Published private(set) var didTriggerNotificationRequest = false
    @Published private(set) var didTriggerFamilyControlsRequest = false
    @Published var needsNotificationAfterFeed = false

    private var slideAppearedAt = Date()

    init(slides: [OnboardingSlide], flowVersion: String) {
        self.slides = slides
        self.flowVersion = flowVersion
    }

    var currentSlide: OnboardingSlide? {
        slides[safe: index]
    }

    var isLastSlide: Bool {
        index == slides.count - 1
    }

    var isInStoryPhase: Bool {
        guard let slide = currentSlide else { return false }
        return OnboardingPhase.phase(for: slide.slideType) == .story
    }

    var firstSetupSlideIndex: Int {
        slides.firstIndex { OnboardingPhase.phase(for: $0.slideType) == .setup } ?? 0
    }

    // MARK: - Navigation

    enum StepResult {
        case advance
        case finish
        case triggerAppleSignIn
        case stay
    }

    func next(
        isAuthenticated: Bool,
        hasAppSelection: Bool,
        onHealth: (() -> Void)?,
        onNotifications: (() -> Void)?,
        onFamilyControls: (() -> Void)?
    ) -> StepResult {
        guard slides.indices.contains(index) else { return .stay }
        let slide = slides[index]

        switch slide.action {
        case .requestHealth:
            if !didTriggerHealthRequest {
                didTriggerHealthRequest = true
                onHealth?()
            }
        case .requestNotifications:
            if !didTriggerNotificationRequest || needsNotificationAfterFeed {
                didTriggerNotificationRequest = true
                needsNotificationAfterFeed = false
                onNotifications?()
            }
        case .none:
            break
        }

        if slide.slideType == .appleLogin, !isAuthenticated {
            return .triggerAppleSignIn
        }

        if slide.slideType == .feedSelection, hasAppSelection {
            needsNotificationAfterFeed = true
        }

        trackSlideCompleted(action: isLastSlide ? "finished" : "next")

        if index < slides.count - 1 {
            index += 1
            return .advance
        } else {
            return .finish
        }
    }

    func goBack() {
        guard index > 0 else { return }
        trackSlideCompleted(action: "back")
        index -= 1
    }

    func skipToSetup() {
        trackSlideCompleted(action: "skipped_intro")
        index = firstSetupSlideIndex
    }

    func markFamilyControlsRequested() {
        didTriggerFamilyControlsRequest = true
    }

    // MARK: - Analytics

    func onSlideAppeared() {
        slideAppearedAt = Date()
        trackSlideViewed()
    }

    private func trackSlideViewed() {
        guard slides.indices.contains(index) else { return }
        let slideName = String(describing: slides[index].slideType)
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_slide_viewed",
                properties: [
                    "slide_index": String(index),
                    "slide_name": slideName,
                    "flow_version": flowVersion
                ]
            )
        }
    }

    private func trackSlideCompleted(action: String) {
        guard slides.indices.contains(index) else { return }
        let slideName = String(describing: slides[index].slideType)
        let durationMs = Int(Date().timeIntervalSince(slideAppearedAt) * 1000)
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_slide_completed",
                properties: [
                    "slide_index": String(index),
                    "slide_name": slideName,
                    "flow_version": flowVersion,
                    "duration_ms": String(durationMs),
                    "action_taken": action
                ]
            )
        }
    }
}
