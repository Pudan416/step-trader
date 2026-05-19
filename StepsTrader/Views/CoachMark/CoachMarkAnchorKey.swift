#if DEBUG
import SwiftUI

enum CoachMarkStep: Int, CaseIterable, Equatable {
    // Canvas tab — color balance
    case colorBalance
    case expandChevron
    case categoriesRevealed
    case tapPlusButton
    case categoryExplain
    case tapMind

    // Inside CategoryDetailView sheet
    case spotlightFocusing
    case tapAddToCanvas

    // Back on canvas
    case canvasTrace
    case goToFeeds

    // Feeds tab
    case tapFeedsTab
    case feedsExplain
    case tapUnlockPill
    case unlockSuccess

    // Closing
    case allSet

    var tooltip: String {
        switch self {
        case .colorBalance:
            return "your color balance — steps, sleep, and what you actually do fill it up"
        case .expandChevron:
            return "tap here to see what's going on"
        case .categoriesRevealed:
            return "steps and sleep come from health. body, mind, heart — that's on you"
        case .tapPlusButton:
            return "tap here to add something you did"
        case .categoryExplain:
            return "body — movement, physical stuff. mind — reading, learning, focus. heart — people, feelings, kindness"
        case .tapMind:
            return "try mind"
        case .spotlightFocusing:
            return "tap focusing — you're focused on this text right now. that's enough."
        case .tapAddToCanvas:
            return "nice. now tap done"
        case .canvasTrace:
            return "your first trace on the canvas. real things you do become colors here"
        case .goToFeeds:
            return "now — where do you spend these colors? let's check"
        case .tapFeedsTab:
            return "tap feeds"
        case .feedsExplain:
            return "this is the app you connected — it uses your colors to unlock"
        case .tapUnlockPill:
            return "it's locked right now. tap 10 min to open it"
        case .unlockSuccess:
            return "done. want more? tap + to add other apps"
        case .allSet:
            return "that's it. enjoy"
        }
    }

    var requiresSpotlight: Bool {
        switch self {
        case .categoryExplain, .canvasTrace, .goToFeeds, .allSet:
            return false
        default:
            return true
        }
    }

    var hasNextButton: Bool {
        switch self {
        case .colorBalance, .categoriesRevealed, .categoryExplain,
             .canvasTrace, .goToFeeds, .feedsExplain, .unlockSuccess, .allSet:
            return true
        default:
            return false
        }
    }

    var isSheetStep: Bool {
        switch self {
        case .spotlightFocusing, .tapAddToCanvas:
            return true
        default:
            return false
        }
    }
}

struct CoachMarkAnchor: Equatable {
    let step: CoachMarkStep
    let frame: CGRect
}

struct CoachMarkAnchorKey: PreferenceKey {
    static var defaultValue: [CoachMarkAnchor] = []
    static func reduce(value: inout [CoachMarkAnchor], nextValue: () -> [CoachMarkAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func coachMarkAnchor(_ step: CoachMarkStep) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CoachMarkAnchorKey.self,
                    value: [CoachMarkAnchor(step: step, frame: geo.frame(in: .global))]
                )
            }
        )
    }
}
#endif
