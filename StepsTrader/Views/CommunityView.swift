import SwiftUI

struct CommunityView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text(loc(appLanguage, "Community", "Сообщество"))
                            .font(.title.bold())
                        
                        Text(loc(appLanguage, "Connect with other DOOM CTRL users", "Общайтесь с другими пользователями DOOM CTRL"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Coming soon card
                    VStack(spacing: 16) {
                        Image(systemName: "hammer.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        
                        Text(loc(appLanguage, "Coming Soon", "Скоро"))
                            .font(.headline)
                        
                        Text(loc(appLanguage, 
                            "We're building something amazing! Soon you'll be able to:",
                            "Мы работаем над чем-то крутым! Скоро вы сможете:"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            featureRow(icon: "trophy.fill", color: .yellow, 
                                text: loc(appLanguage, "Compete on leaderboards", "Соревноваться в рейтингах"))
                            featureRow(icon: "person.2.fill", color: .blue, 
                                text: loc(appLanguage, "Challenge friends", "Бросать вызов друзьям"))
                            featureRow(icon: "star.fill", color: .orange, 
                                text: loc(appLanguage, "Earn achievements", "Получать достижения"))
                            featureRow(icon: "bubble.left.and.bubble.right.fill", color: .green, 
                                text: loc(appLanguage, "Share tips & motivation", "Делиться советами"))
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                    
                    Spacer(minLength: 100)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    @ViewBuilder
    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

#Preview {
    CommunityView(model: DIContainer.shared.makeAppModel())
}

