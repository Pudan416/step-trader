import SwiftUI

/// Factory view that renders the canvas wrapped in the selected poster style.
/// All three designs share the same metadata inputs; only the visual layout differs.
struct CanvasPosterView<Content: View>: View {
    let style: PosterStyle
    let date: Date
    let userName: String?
    let steps: Int?
    let sleepHours: Double?
    let inkEarned: Int?
    var inkSpent: Int?
    let content: Content

    init(
        style: PosterStyle,
        date: Date,
        userName: String? = nil,
        steps: Int? = nil,
        sleepHours: Double? = nil,
        inkEarned: Int? = nil,
        inkSpent: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.date = date
        self.userName = userName
        self.steps = steps
        self.sleepHours = sleepHours
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
        self.content = content()
    }

    var body: some View {
        switch style {
        case .museum:
            CanvasFrameView(
                date: date,
                userName: userName,
                steps: steps,
                sleepHours: sleepHours,
                inkEarned: inkEarned,
                inkSpent: inkSpent
            ) { content }

        case .fullBleed:
            CanvasFullBleedPoster(
                date: date,
                userName: userName,
                steps: steps,
                sleepHours: sleepHours,
                inkEarned: inkEarned,
                inkSpent: inkSpent
            ) { content }

        case .framedDark:
            CanvasFramedDarkPoster(
                date: date,
                userName: userName,
                steps: steps,
                sleepHours: sleepHours,
                inkEarned: inkEarned,
                inkSpent: inkSpent
            ) { content }
        }
    }
}
