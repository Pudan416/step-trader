import SwiftUI

// MARK: - Slide Types

enum OnboardingSlideAction: Equatable {
    case none
    case requestHealth
    case requestNotifications
}

enum OnboardingSlideType: Equatable {
    case coldOpen
    case colorCap
    case spendDemo
    case howItWorks
    case stepsSetup
    case sleepSetup
    case text
    case feedSelection
    case nowHereReveal
    case appleLogin
    case welcome
    // v8 slide types
    case theApp
    case canvasSleep
    case canvasSteps
    case balance
    case resetBedtime
    case bodyMindHeart
    case colorCapV8
    case notificationPermission
    case welcomeV8

    var isInteractive: Bool {
        switch self {
        case .colorCap, .spendDemo, .stepsSetup, .sleepSetup,
             .canvasSleep, .canvasSteps, .balance, .resetBedtime, .bodyMindHeart:
            return true
        default:
            return false
        }
    }
}

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let lines: [String]
    let symbol: String
    let gradient: [Color]
    let action: OnboardingSlideAction
    let slideType: OnboardingSlideType
    let microcopy: String?

    init(
        lines: [String],
        symbol: String = "",
        gradient: [Color] = [],
        action: OnboardingSlideAction = .none,
        slideType: OnboardingSlideType = .text,
        microcopy: String? = nil
    ) {
        self.lines = lines
        self.symbol = symbol
        self.gradient = gradient
        self.action = action
        self.slideType = slideType
        self.microcopy = microcopy
    }
}

// MARK: - Onboarding Phases (for progress bar grouping)

enum OnboardingPhase: Equatable {
    case story, setup, action

    static func phase(for slideType: OnboardingSlideType) -> OnboardingPhase {
        switch slideType {
        case .coldOpen, .nowHereReveal, .howItWorks,
             .theApp, .bodyMindHeart, .colorCap, .colorCapV8, .spendDemo:
            return .story
        case .canvasSleep, .canvasSteps, .balance, .resetBedtime,
             .stepsSetup, .sleepSetup:
            return .setup
        case .text, .feedSelection, .appleLogin, .welcome,
             .notificationPermission, .welcomeV8:
            return .action
        }
    }
}

// MARK: - Canonical slide sequence

enum OnboardingSlides {
    static let flowVersion = "v8"

    static let slideTypes: [OnboardingSlideType] = [
        .coldOpen,
        .theApp,
        .canvasSleep,
        .canvasSteps,
        .resetBedtime,
        .balance,
        .bodyMindHeart,
        .colorCapV8,
        .text, // health permission
        .feedSelection,
        .notificationPermission,
        .appleLogin,
        .welcomeV8,
    ]

    static func makeSlides() -> [OnboardingSlide] {
        [
            OnboardingSlide(
                lines: [
                    String(localized: "i live mostly online. working. scrolling. staring at a screen."),
                    String(localized: "probably just like you.")
                ],
                slideType: .coldOpen
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "for me it feels like being stuck in nowhere."),
                    String(localized: "so i made this app.")
                ],
                slideType: .theApp
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "each day forms a canvas."),
                    String(localized: "sleep deepens the dark."),
                    String(localized: "how many hours of sleep you need?")
                ],
                slideType: .canvasSleep
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "steps brighten it."),
                    String(localized: "how many steps a day is your goal?")
                ],
                slideType: .canvasSteps
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "each day the canvas resets."),
                    String(localized: "when does your day end?")
                ],
                slideType: .resetBedtime
            ),
            OnboardingSlide(
                lines: [],
                slideType: .balance
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "but what truly colors your canvas is what you do for your body, mind, and heart.")
                ],
                slideType: .bodyMindHeart
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "colors are the currency you earn for living a real life."),
                    String(localized: "each day can bring you a maximum of")
                ],
                slideType: .colorCapV8
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "the app needs access to apple health."),
                    String(localized: "we read steps, sleep, and workouts. nothing else.")
                ],
                action: .requestHealth,
                microcopy: String(localized: "you can change this in settings anytime.")
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "you can spend your colors on screen time."),
                    String(localized: "pick the one app that drains you the most.")
                ],
                slideType: .feedSelection,
                microcopy: String(localized: "this uses apple's screen time. you'll see a system prompt.")
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "also, allow notifications."),
                    String(localized: "they're needed to unlock the apps."),
                    String(localized: "you can control them in settings later.")
                ],
                action: .requestNotifications,
                slideType: .notificationPermission
            ),
            OnboardingSlide(
                lines: [
                    String(localized: "btw, my name is kosta."),
                    String(localized: "and who are you?")
                ],
                slideType: .appleLogin,
                microcopy: String(localized: "sign in to keep your data safe and synced across devices.")
            ),
            OnboardingSlide(
                lines: [],
                slideType: .welcomeV8
            ),
        ]
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
