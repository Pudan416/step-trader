import SwiftUI

/// User rating screen (placeholder for Outer World / map tab).
struct RatingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("User rating")
                        .font(AppFonts.headline)
                        .foregroundStyle(.secondary)
                    Text("Rating will be available soon.")
                        .font(AppFonts.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle("Rating")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    RatingView(model: DIContainer.shared.makeAppModel())
}
