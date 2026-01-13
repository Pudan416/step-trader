import SwiftUI

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    let spentSteps: Int
    let showDetails: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Energy bar")
                    .font(.headline)
                Spacer()
                Text("\(totalSteps)")
                    .font(.headline)
                    .foregroundColor(pink)
            }

            ProgressView(
                value: Double(remainingSteps),
                total: max(1.0, Double(totalSteps))
            )
            .progressViewStyle(
                LinearProgressViewStyle(tint: pink)
            )
            .scaleEffect(x: 1, y: 2, anchor: .center)
            .background(
                GeometryReader { proxy in
                    let remainingRatio = max(0, min(1, totalSteps == 0 ? 0 : Double(remainingSteps) / Double(max(1, totalSteps))))
                    let remainingWidth = proxy.size.width * remainingRatio
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.25))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(pink)
                            .frame(width: remainingWidth)
                    }
                }
            )

            if showDetails {
                HStack(spacing: 12) {
                    summaryBox(
                        title: "Left",
                        value: "\(remainingSteps)",
                        color: pink
                    )
                    summaryBox(
                        title: "Spent",
                        value: "\(spentSteps)",
                        color: .secondary
                    )
                }
                .transition(.move(edge: .top))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        // При выключении таба скрываем детали мгновенно, при показе — мягкая анимация.
        .animation(.easeInOut(duration: showDetails ? 0.3 : 0.0), value: showDetails)
    }

    private var pink: Color { Color(red: 224/255, green: 130/255, blue: 217/255) }
    
    private var dateString: String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM"
        return df.string(from: Date())
    }
    
    private func summaryBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
}
