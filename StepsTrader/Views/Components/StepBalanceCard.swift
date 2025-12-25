import SwiftUI
import Foundation

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(loc(appLanguage, "Step balance", "Баланс шагов"))
                    .font(.headline)
                Spacer()
                Text("\(remainingSteps)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            ProgressView(
                value: Double(remainingSteps),
                total: max(1.0, Double(totalSteps))
            )
            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
}
