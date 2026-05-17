import SwiftUI

struct CanvasShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct CanvasDayDetailSheet: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let snapshot: PastDaySnapshot?
    let onDismiss: () -> Void
    @Environment(\.appTheme) private var theme

    private var dayLabel: String {
        guard let d = date(from: dayKey) else { return dayKey }
        return CachedFormatters.longDate.string(from: d)
    }

    private func date(from key: String) -> Date? {
        CachedFormatters.dayKey.date(from: key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let s = snapshot {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statCard(icon: "figure.walk", value: "\(s.steps)", label: String(localized: "Steps"), color: .green)
                            statCard(icon: "bed.double.fill", value: String(format: "%.1f", s.sleepHours), label: String(localized: "Sleep hours"), color: .indigo)
                            statCard(icon: "plus.circle.fill", value: "\(s.inkEarned)", label: String(localized: "Gained"), color: .blue)
                            statCard(icon: "minus.circle.fill", value: "\(s.inkSpent)", label: String(localized: "Spent"), color: .orange)
                        }
                        canvasSection(s)
                    } else {
                        Text(String(localized: "No data for this day."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundColor)
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func canvasSection(_ s: PastDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            canvasRow(title: String(localized: "Body", comment: "Energy category"), ids: s.bodyIds, color: theme.bodyColor)
            canvasRow(title: String(localized: "Mind", comment: "Energy category"), ids: s.mindIds, color: theme.mindColor)
            canvasRow(title: String(localized: "Heart", comment: "Energy category"), ids: s.heartIds, color: theme.heartColor)
        }
    }

    private func canvasRow(title: String, ids: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            if ids.isEmpty {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        Text(model.resolveOptionTitle(for: id))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.15)))
                            .foregroundColor(color)
                    }
                }
            }
        }
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
