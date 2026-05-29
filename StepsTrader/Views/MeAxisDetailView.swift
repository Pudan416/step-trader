import SwiftUI

// MARK: - Axis detail popup
//
// Extracted from `MeView.swift` (§9.2). `AxisDetailContext` carries the tapped
// radar axis plus the week's snapshots into `AxisDetailView`, the Liquid Glass
// card MeView presents in its `axisDetailOverlay`.

struct AxisDetailContext: Identifiable {
    let axis: EnergySignatureView.Axis
    let snaps: [PastDaySnapshot]
    let avgSteps: Int
    let avgSleep: Double
    var id: String { axis.id }
}

struct AxisDetailView: View {
    let context: AxisDetailContext
    let model: AppModel
    /// When non-nil, a close (×) button is rendered in the header. Used by the
    /// Liquid Glass overlay in MeView; nil-by-default keeps callers that
    /// present the view in another container (e.g. as a sheet) unaffected.
    var onClose: (() -> Void)? = nil

    private var axis: EnergySignatureView.Axis { context.axis }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header — label + score description on the left, score arc and
            // optional close button on the right. No emoji icon.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(axis.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(scoreDescription)
                        .font(.subheadline)
                        .foregroundStyle(axis.color)
                }
                Spacer(minLength: 8)
                // Score arc
                ZStack {
                    Circle()
                        .stroke(axis.color.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(axis.score / 20))
                        .stroke(axis.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f", axis.score))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel(String(localized: "Close",
                        comment: "AxisDetail – close button"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.horizontal, 20)

            // Content
            detailContent
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        // Hug the content — the card height equals whatever the VStack needs.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch axis.id {
        case "steps":
            stepsDetail
        case "sleep":
            sleepDetail
        case "body":
            activityDetail(ids: context.snaps.flatMap(\.bodyIds), label: "body")
        case "mind":
            activityDetail(ids: context.snaps.flatMap(\.mindIds), label: "mind")
        case "heart":
            activityDetail(ids: context.snaps.flatMap(\.heartIds), label: "heart")
        default:
            EmptyView()
        }
    }

    // MARK: Steps
    private var stepsDetail: some View {
        let target = context.snaps.first?.stepsTarget ?? Double(EnergyDefaults.stepsTarget)
        let pct = Int(min(100, Double(context.avgSteps) / max(1, target) * 100))
        let weekTotal = context.snaps.reduce(0) { $0 + $1.steps }
        return VStack(alignment: .leading, spacing: 14) {
            statRow(label: "Daily average", value: context.avgSteps.formatted())
            statRow(label: "Daily goal", value: Int(target).formatted())
            statRow(label: "Goal %", value: "\(pct)%")
            statRow(label: "Week total", value: weekTotal.formatted())
        }
    }

    // MARK: Sleep
    private var sleepDetail: some View {
        let target = context.snaps.first?.sleepTargetHours ?? EnergyDefaults.sleepTargetHours
        let pct = Int(min(100, context.avgSleep / max(0.1, target) * 100))
        let h = Int(context.avgSleep)
        let m = Int((context.avgSleep - Double(h)) * 60)
        return VStack(alignment: .leading, spacing: 14) {
            statRow(label: "Daily average", value: "\(h)h \(m)m")
            statRow(label: "Nightly goal", value: String(format: "%.1f h", target))
            statRow(label: "Goal %", value: "\(pct)%")
        }
    }

    // MARK: Activities
    private func activityDetail(ids: [String], label: String) -> some View {
        var counts: [String: Int] = [:]
        for id in ids { counts[id, default: 0] += 1 }
        let sorted = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let days = max(1, context.snaps.count)

        return VStack(alignment: .leading, spacing: 0) {
            if sorted.isEmpty {
                Text("No \(label) activities logged this week.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(sorted, id: \.key) { entry in
                    HStack {
                        Text(model.resolveOptionTitle(for: entry.key))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.90))
                        Spacer()
                        Text("\(entry.value)×")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(axis.color.opacity(0.85))
                        // mini bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(axis.color.opacity(0.55))
                            .frame(width: CGFloat(entry.value) / CGFloat(days) * 40, height: 6)
                            .frame(width: 40, alignment: .leading)
                    }
                    .padding(.vertical, 9)
                    Divider().background(Color.white.opacity(0.07))
                }
            }
        }
    }

    // MARK: Helpers

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.50))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var scoreDescription: String {
        let pct = Int(axis.score / 20 * 100)
        switch pct {
        case 0..<30:   return "Needs attention · \(pct)%"
        case 30..<60:  return "Building momentum · \(pct)%"
        case 60..<85:  return "On track · \(pct)%"
        default:       return "Thriving · \(pct)%"
        }
    }
}
