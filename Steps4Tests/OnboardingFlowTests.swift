import XCTest
@testable import Steps4

@MainActor
final class OnboardingFlowTests: XCTestCase {

    // MARK: - OnboardingSlide

    func testSlideInit_defaults() {
        let slide = OnboardingSlide(lines: ["hello", "world"])
        XCTAssertEqual(slide.lines, ["hello", "world"])
        XCTAssertEqual(slide.symbol, "")
        XCTAssertTrue(slide.gradient.isEmpty)
        XCTAssertEqual(slide.action, .none)
        XCTAssertEqual(slide.slideType, .text)
        XCTAssertNil(slide.microcopy)
    }

    func testSlideInit_customAction() {
        let slide = OnboardingSlide(
            lines: ["allow health"],
            action: .requestHealth,
            slideType: .stepsSetup,
            microcopy: "you can change this later"
        )
        XCTAssertEqual(slide.action, .requestHealth)
        XCTAssertEqual(slide.slideType, .stepsSetup)
        XCTAssertEqual(slide.microcopy, "you can change this later")
    }

    func testSlideIds_areUnique() {
        let a = OnboardingSlide(lines: ["a"])
        let b = OnboardingSlide(lines: ["b"])
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - OnboardingSlideType.isInteractive

    func testInteractiveSlideTypes() {
        let interactive: [OnboardingSlideType] = [
            .colorCap, .spendDemo, .stepsSetup, .sleepSetup,
            .canvasSleep, .canvasSteps, .balance, .resetBedtime, .bodyMindHeart
        ]
        for type in interactive {
            XCTAssertTrue(type.isInteractive, "\(type) should be interactive")
        }
    }

    func testNonInteractiveSlideTypes() {
        let nonInteractive: [OnboardingSlideType] = [
            .coldOpen, .text, .feedSelection, .nowHereReveal,
            .appleLogin, .welcome, .theApp, .colorCapV8,
            .notificationPermission, .welcomeV8, .howItWorks
        ]
        for type in nonInteractive {
            XCTAssertFalse(type.isInteractive, "\(type) should NOT be interactive")
        }
    }

    // MARK: - OnboardingPhase mapping

    func testPhase_storyTypes() {
        let storyTypes: [OnboardingSlideType] = [
            .coldOpen, .nowHereReveal, .howItWorks,
            .theApp, .bodyMindHeart, .colorCap, .colorCapV8, .spendDemo
        ]
        for type in storyTypes {
            XCTAssertEqual(OnboardingPhase.phase(for: type), .story,
                           "\(type) should be in story phase")
        }
    }

    func testPhase_setupTypes() {
        let setupTypes: [OnboardingSlideType] = [
            .canvasSleep, .canvasSteps, .balance, .resetBedtime,
            .stepsSetup, .sleepSetup
        ]
        for type in setupTypes {
            XCTAssertEqual(OnboardingPhase.phase(for: type), .setup,
                           "\(type) should be in setup phase")
        }
    }

    func testPhase_actionTypes() {
        let actionTypes: [OnboardingSlideType] = [
            .text, .feedSelection, .appleLogin, .welcome,
            .notificationPermission, .welcomeV8
        ]
        for type in actionTypes {
            XCTAssertEqual(OnboardingPhase.phase(for: type), .action,
                           "\(type) should be in action phase")
        }
    }

    // MARK: - OnboardingSlideAction equality

    func testSlideAction_equality() {
        XCTAssertEqual(OnboardingSlideAction.none, .none)
        XCTAssertEqual(OnboardingSlideAction.requestHealth, .requestHealth)
        XCTAssertNotEqual(OnboardingSlideAction.requestHealth, .requestNotifications)
    }

    // MARK: - Array safe subscript

    func testSafeSubscript_validIndex() {
        let arr = [10, 20, 30]
        XCTAssertEqual(arr[safe: 0], 10)
        XCTAssertEqual(arr[safe: 2], 30)
    }

    func testSafeSubscript_outOfBounds() {
        let arr = [10, 20, 30]
        XCTAssertNil(arr[safe: 3])
        XCTAssertNil(arr[safe: -1])
        XCTAssertNil(arr[safe: 100])
    }

    func testSafeSubscript_emptyArray() {
        let arr: [Int] = []
        XCTAssertNil(arr[safe: 0])
    }

    // MARK: - OnboardingCoordinator navigation

    private func makeV8Slides() -> [OnboardingSlide] {
        [
            OnboardingSlide(lines: ["slide 0"], slideType: .coldOpen),
            OnboardingSlide(lines: ["slide 1"], slideType: .theApp),
            OnboardingSlide(lines: ["slide 2"], slideType: .canvasSleep),
            OnboardingSlide(lines: ["slide 3"], slideType: .canvasSteps),
            OnboardingSlide(lines: ["slide 4"], slideType: .resetBedtime),
            OnboardingSlide(lines: ["slide 5"], slideType: .balance),
            OnboardingSlide(lines: ["slide 6"], slideType: .bodyMindHeart),
            OnboardingSlide(lines: ["slide 7"], slideType: .colorCapV8),
            OnboardingSlide(lines: ["allow health"], action: .requestHealth),
            OnboardingSlide(lines: ["pick app"], slideType: .feedSelection),
            OnboardingSlide(lines: ["notifications"], action: .requestNotifications, slideType: .notificationPermission),
            OnboardingSlide(lines: ["sign in"], slideType: .appleLogin),
            OnboardingSlide(lines: ["welcome"], slideType: .welcomeV8),
        ]
    }

    func testCoordinator_initialState() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")
        XCTAssertEqual(coord.index, 0)
        XCTAssertFalse(coord.isLastSlide)
        XCTAssertEqual(coord.currentSlide?.slideType, .coldOpen)
        XCTAssertEqual(coord.flowVersion, "v8")
    }

    func testCoordinator_nextAdvances() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        let result = coord.next(
            isAuthenticated: true, hasAppSelection: false,
            onHealth: nil, onNotifications: nil, onFamilyControls: nil
        )
        XCTAssertEqual(result, .advance)
        XCTAssertEqual(coord.index, 1)
        XCTAssertEqual(coord.currentSlide?.slideType, .theApp)
    }

    func testCoordinator_goBack() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)
        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)
        XCTAssertEqual(coord.index, 2)

        coord.goBack()
        XCTAssertEqual(coord.index, 1)
    }

    func testCoordinator_goBackAtZeroStays() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        coord.goBack()
        XCTAssertEqual(coord.index, 0)
    }

    func testCoordinator_skipToSetup() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        XCTAssertTrue(coord.isInStoryPhase)
        coord.skipToSetup()

        let expected = slides.firstIndex { OnboardingPhase.phase(for: $0.slideType) == .setup }!
        XCTAssertEqual(coord.index, expected)
        XCTAssertEqual(coord.currentSlide?.slideType, .canvasSleep)
    }

    func testCoordinator_lastSlideFinishes() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        for i in 0..<slides.count - 1 {
            let r = coord.next(
                isAuthenticated: true, hasAppSelection: false,
                onHealth: nil, onNotifications: nil, onFamilyControls: nil
            )
            if slides[i].slideType == .appleLogin {
                XCTAssertEqual(r, .advance, "Authenticated → still advance")
            }
        }
        XCTAssertTrue(coord.isLastSlide)

        let final = coord.next(
            isAuthenticated: true, hasAppSelection: false,
            onHealth: nil, onNotifications: nil, onFamilyControls: nil
        )
        XCTAssertEqual(final, .finish)
    }

    // MARK: - Health permission trigger

    func testCoordinator_healthTriggeredOnce() {
        let slides = [
            OnboardingSlide(lines: ["a"], slideType: .coldOpen),
            OnboardingSlide(lines: ["health"], action: .requestHealth),
            OnboardingSlide(lines: ["done"], slideType: .welcomeV8),
        ]
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        var healthCallCount = 0
        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)

        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: { healthCallCount += 1 }, onNotifications: nil, onFamilyControls: nil)
        XCTAssertEqual(healthCallCount, 1)

        coord.goBack()
        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: { healthCallCount += 1 }, onNotifications: nil, onFamilyControls: nil)
        XCTAssertEqual(healthCallCount, 1, "Health should only trigger once")
    }

    // MARK: - Notification trigger + feed re-prompt

    func testCoordinator_notificationRepromptsAfterFeed() {
        let slides = [
            OnboardingSlide(lines: ["a"], slideType: .coldOpen),
            OnboardingSlide(lines: ["pick app"], slideType: .feedSelection),
            OnboardingSlide(lines: ["notif"], action: .requestNotifications, slideType: .notificationPermission),
            OnboardingSlide(lines: ["done"], slideType: .welcomeV8),
        ]
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)

        _ = coord.next(isAuthenticated: true, hasAppSelection: true,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)
        XCTAssertTrue(coord.needsNotificationAfterFeed,
                      "When feed has apps, needsNotificationAfterFeed should be set")

        var notifCount = 0
        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: { notifCount += 1 }, onFamilyControls: nil)
        XCTAssertEqual(notifCount, 1)
        XCTAssertFalse(coord.needsNotificationAfterFeed, "Should be cleared after triggering")
    }

    // MARK: - Apple sign-in gating

    func testCoordinator_appleLoginGatesWhenNotAuthenticated() {
        let slides = [
            OnboardingSlide(lines: ["a"], slideType: .coldOpen),
            OnboardingSlide(lines: ["sign in"], slideType: .appleLogin),
            OnboardingSlide(lines: ["welcome"], slideType: .welcomeV8),
        ]
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)

        let result = coord.next(
            isAuthenticated: false, hasAppSelection: false,
            onHealth: nil, onNotifications: nil, onFamilyControls: nil
        )
        XCTAssertEqual(result, .triggerAppleSignIn)
        XCTAssertEqual(coord.index, 1, "Should NOT advance past login when not authenticated")
    }

    func testCoordinator_appleLoginPassesWhenAuthenticated() {
        let slides = [
            OnboardingSlide(lines: ["a"], slideType: .coldOpen),
            OnboardingSlide(lines: ["sign in"], slideType: .appleLogin),
            OnboardingSlide(lines: ["welcome"], slideType: .welcomeV8),
        ]
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)

        let result = coord.next(
            isAuthenticated: true, hasAppSelection: false,
            onHealth: nil, onNotifications: nil, onFamilyControls: nil
        )
        XCTAssertEqual(result, .advance)
        XCTAssertEqual(coord.index, 2)
    }

    // MARK: - isInStoryPhase

    func testCoordinator_isInStoryPhase() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        XCTAssertTrue(coord.isInStoryPhase, "coldOpen is story")

        _ = coord.next(isAuthenticated: true, hasAppSelection: false,
                       onHealth: nil, onNotifications: nil, onFamilyControls: nil)
        XCTAssertTrue(coord.isInStoryPhase, "theApp is story")

        coord.skipToSetup()
        XCTAssertFalse(coord.isInStoryPhase, "After skip, should be in setup")
    }

    // MARK: - firstSetupSlideIndex

    func testCoordinator_firstSetupSlideIndex_v8() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        let idx = coord.firstSetupSlideIndex
        XCTAssertEqual(slides[idx].slideType, .canvasSleep,
                       "First setup slide in v8 is canvasSleep")
    }

    func testCoordinator_firstSetupSlideIndex_allStory() {
        let slides = [
            OnboardingSlide(lines: ["a"], slideType: .coldOpen),
            OnboardingSlide(lines: ["b"], slideType: .theApp),
        ]
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "test")
        XCTAssertEqual(coord.firstSetupSlideIndex, 0,
                       "No setup slides → falls back to 0")
    }

    // MARK: - StepResult equality

    func testStepResult_cases() {
        XCTAssertEqual(OnboardingCoordinator.StepResult.advance, .advance)
        XCTAssertEqual(OnboardingCoordinator.StepResult.finish, .finish)
        XCTAssertEqual(OnboardingCoordinator.StepResult.triggerAppleSignIn, .triggerAppleSignIn)
        XCTAssertEqual(OnboardingCoordinator.StepResult.stay, .stay)
        XCTAssertNotEqual(OnboardingCoordinator.StepResult.advance, .finish)
    }

    // MARK: - Empty slides coordinator

    func testCoordinator_emptySlides() {
        let coord = OnboardingCoordinator(slides: [], flowVersion: "v8")
        XCTAssertNil(coord.currentSlide)
        XCTAssertFalse(coord.isLastSlide, "0 != -1, so not considered last slide")

        let result = coord.next(
            isAuthenticated: true, hasAppSelection: false,
            onHealth: nil, onNotifications: nil, onFamilyControls: nil
        )
        XCTAssertEqual(result, .stay)
    }

    // MARK: - markFamilyControlsRequested

    func testCoordinator_markFamilyControls() {
        let coord = OnboardingCoordinator(slides: makeV8Slides(), flowVersion: "v8")
        XCTAssertFalse(coord.didTriggerFamilyControlsRequest)
        coord.markFamilyControlsRequested()
        XCTAssertTrue(coord.didTriggerFamilyControlsRequest)
    }

    // MARK: - v7 slide sequence structure

    func testV7SlideSequence_firstAndLast() {
        let v7Slides: [OnboardingSlideType] = [
            .coldOpen, .nowHereReveal, .colorCap, .spendDemo,
            .howItWorks, .stepsSetup, .sleepSetup, .text,
            .feedSelection, .appleLogin, .welcome
        ]
        XCTAssertEqual(v7Slides.first, .coldOpen)
        XCTAssertEqual(v7Slides.last, .welcome)
        XCTAssertEqual(v7Slides.count, 11)
    }

    func testV8SlideSequence_firstAndLast() {
        let v8Slides: [OnboardingSlideType] = [
            .coldOpen, .theApp, .canvasSleep, .canvasSteps,
            .resetBedtime, .balance, .bodyMindHeart, .colorCapV8,
            .text, .feedSelection, .notificationPermission,
            .appleLogin, .welcomeV8
        ]
        XCTAssertEqual(v8Slides.first, .coldOpen)
        XCTAssertEqual(v8Slides.last, .welcomeV8)
        XCTAssertEqual(v8Slides.count, 13)
    }

    // MARK: - Phase transitions in v8 flow

    func testV8Flow_phaseOrder() {
        let slides = makeV8Slides()
        var seenSetup = false
        var seenAction = false

        for slide in slides {
            let phase = OnboardingPhase.phase(for: slide.slideType)
            if phase == .setup { seenSetup = true }
            if phase == .action {
                XCTAssertTrue(seenSetup, "Action phase should come after setup for: \(slide.slideType)")
                seenAction = true
            }
        }
        XCTAssertTrue(seenSetup)
        XCTAssertTrue(seenAction)
    }

    // MARK: - Full navigation walk-through

    func testCoordinator_fullWalkthrough() {
        let slides = makeV8Slides()
        let coord = OnboardingCoordinator(slides: slides, flowVersion: "v8")

        var healthCalled = false
        var notifCalled = false
        var results: [OnboardingCoordinator.StepResult] = []

        while coord.index < slides.count {
            let r = coord.next(
                isAuthenticated: true, hasAppSelection: false,
                onHealth: { healthCalled = true },
                onNotifications: { notifCalled = true },
                onFamilyControls: nil
            )
            results.append(r)
            if r == .finish { break }
        }

        XCTAssertTrue(healthCalled, "Health should be triggered during walkthrough")
        XCTAssertTrue(notifCalled, "Notifications should be triggered during walkthrough")
        XCTAssertEqual(results.last, .finish)
        XCTAssertEqual(results.filter { $0 == .advance }.count, slides.count - 1)
    }
}
