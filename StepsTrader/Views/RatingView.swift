import SwiftUI

/// Экран рейтинга пользователей (на месте таба «Outer World» / карты).
struct RatingView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(loc(appLanguage, "User rating"))
                        .font(AppFonts.headline)
                        .foregroundStyle(.secondary)
                    Text(loc(appLanguage, "Rating will be available soon."))
                        .font(AppFonts.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle(loc(appLanguage, "Rating"))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    RatingView(model: DIContainer.shared.makeAppModel())
}
