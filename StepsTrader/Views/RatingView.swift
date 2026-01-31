import SwiftUI

/// Экран рейтинга пользователей (на месте таба «Outer World» / карты).
struct RatingView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(loc(appLanguage, "User rating"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(loc(appLanguage, "Rating will be available soon."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(loc(appLanguage, "Rating"))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    RatingView(model: DIContainer.shared.makeAppModel())
}
