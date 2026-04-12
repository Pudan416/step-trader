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

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
