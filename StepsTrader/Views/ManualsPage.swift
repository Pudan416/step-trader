import SwiftUI

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {}
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .background(theme.backgroundColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }
}
