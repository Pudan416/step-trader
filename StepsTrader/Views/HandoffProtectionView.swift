import SwiftUI

struct HandoffProtectionView: View {
    @ObservedObject var model: AppModel
    let token: HandoffToken
    let onContinue: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("🛡️")
                        .font(.systemSerif(60))
                        .accessibilityHidden(true)

                    Text(String(localized: "Protection Screen"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "You're about to open \(token.targetAppName)"))
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    let totalSteps = Int(model.stepsToday)
                    let spent = model.spentStepsToday
                    let cost = model.userEconomyStore.entryCostSteps
                    let available = max(0, totalSteps - spent)
                    let opensLeftText: String = {
                        if cost == 0 { return String(localized: "Unlimited") }
                        return "\(available / max(cost, 1))"
                    }()

                    Text(String(localized: "Entries left today: \(opensLeftText)"))
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            handoffCancelButton
                            handoffOpenButton
                        }
                        VStack(spacing: 12) {
                            handoffOpenButton
                            handoffCancelButton
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(30)
            .glassCard(cornerRadius: 20, style: .frosted)
            .padding(.horizontal, 24)
        }
        .onAppear {
            AppLogger.app.debug("🛡️ HandoffProtectionView appeared for \(token.targetAppName)")
            AppLogger.app.debug("🛡️ Token ID: \(token.tokenId), Created: \(token.createdAt)")
        }
    }

    private var handoffCancelButton: some View {
        Button(String(localized: "Cancel")) {
            onCancel()
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .font(.headline)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(String(localized: "Cancel opening \(token.targetAppName)", comment: "Handoff – cancel button accessibility"))
    }

    private var handoffOpenButton: some View {
        Button(String(localized: "Open \(token.targetAppName)")) {
            AppLogger.app.debug("🛡️ User clicked Continue button for \(token.targetAppName)")
            onContinue()
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color.blue)
        .foregroundColor(.white)
        .font(.headline)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(String(localized: "Open \(token.targetAppName)", comment: "Handoff – open button accessibility"))
        .accessibilityHint(String(localized: "Opens the app \(token.targetAppName) after confirming access", comment: "Handoff – open button accessibility hint"))
    }
}
