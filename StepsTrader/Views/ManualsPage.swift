import SwiftUI

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight

    var body: some View {
        NavigationStack {
            ZStack {
                EnergyGradientBackground(
                    sleepPoints: model.sleepPointsToday,
                    stepsPoints: model.stepsPointsToday
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        
                        ForEach(guides) { guide in
                            guideCard(guide)
                        }
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("guides")
                .font(.system(size: 22, weight: .semibold))
                .themedPrimary(theme)
            
            Text("short wall texts for the gallery.")
                .font(.system(size: 13, weight: .regular))
                .themedSecondary(theme)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func guideCard(_ guide: GuideEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.title)
                .font(.system(size: 14, weight: .semibold))
                .themedPrimary(theme)
            
            Text(guide.body)
                .font(.system(size: 14, weight: .regular))
                .themedSecondary(theme)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .themedBorder(theme)
    }
    
    private var guides: [GuideEntry] {
        [
            GuideEntry(
                title: "on proof",
                body: "Proof is not self-improvement. It is a record of what you chose to trade. The day leaves marks. The screen is just one of them."
            ),
            GuideEntry(
                title: "on the three rooms",
                body: "Body, mind, heart. Three rooms where the day leaves its traces. You do not rank them. You notice them."
            ),
            GuideEntry(
                title: "on the threshold",
                body: "Tickets are thresholds, not punishments. You pause. You decide if the screen is worth the experience."
            )
        ]
    }
}

private struct GuideEntry: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}
