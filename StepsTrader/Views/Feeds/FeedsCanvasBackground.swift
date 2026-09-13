import SwiftUI

/// Compatibility wrapper; all app surfaces share the same current-day image.
struct FeedsCanvasBackground: View {
    var body: some View { TodayCanvasBackground() }
}
