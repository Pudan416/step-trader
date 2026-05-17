import SwiftUI

#if DEBUG
struct QuickStatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.green.opacity(0.1), .blue.opacity(0.2)], startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("📊")
                        .font(.systemSerif(60))

                    Text(String(localized: "Quick Status", comment: "QuickStatus – title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(String(localized: "My progress overview", comment: "QuickStatus – subtitle"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    HStack {
                        Text(String(localized: "Steps today:", comment: "QuickStatus – steps label"))
                            .font(.title2)
                        Spacer()
                        Text("\(Int(model.stepsToday))")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .glassCard(cornerRadius: 16, style: .frosted)

                    HStack {
                        Text(String(localized: "Entry balance:", comment: "QuickStatus – balance label"))
                            .font(.title2)
                        Spacer()
                        Text(String(localized: "\(model.userEconomyStore.totalStepsBalance) steps", comment: "QuickStatus – balance value"))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(
                                model.userEconomyStore.totalStepsBalance >= model.userEconomyStore.entryCostSteps ? .green : .red)
                    }
                    .padding()
                    .glassCard(cornerRadius: 16, style: .frosted)
                }
                .padding(.horizontal, 20)

                Button(String(localized: "Close", comment: "QuickStatus – dismiss button")) {
                    model.showQuickStatusPage = false
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .font(.headline)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .accessibilityLabel(String(localized: "Close quick status", comment: "QuickStatus – close VoiceOver label"))
                .accessibilityHint(String(localized: "Closes the quick status view", comment: "QuickStatus – close VoiceOver hint"))
            }
        }
    }
}
#endif
