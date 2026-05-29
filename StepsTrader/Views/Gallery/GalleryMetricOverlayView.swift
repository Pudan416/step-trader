import SwiftUI

// MARK: - Metric Popover Overlay
//
// Extracted from `GalleryView.swift` (§9.2). The Liquid Glass popover shown
// when the user taps a metric chip (steps / sleep / a Body·Mind·Heart
// category) on the canvas. Self-contained: it reads `model` + the daily-goal
// AppStorage targets and reports dismissal through `onClose`.

struct GalleryMetricOverlayView: View {
    let model: AppModel
    let kind: MetricOverlayKind
    let onClose: () -> Void

    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var userStepsTarget: Double = 10_000
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var userSleepTarget: Double = 8.0

    var body: some View {
        ZStack {
            // Same dim backdrop as the radar AxisDetail overlay in MeView.
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityHidden(true)

            // Liquid Glass card — header (title + close) over content. Hugs
            // its content vertically so there's no empty space below.
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(overlayTitle(for: kind))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Close",
                        comment: "MetricOverlay – close button"))
                }

                overlayContent(for: kind)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
            .glassCard(cornerRadius: 26, style: .frosted)
            .padding(.horizontal, 20)
        }
    }

    private func overlayTitle(for kind: MetricOverlayKind) -> String {
        switch kind {
        case .steps: return String(localized: "Steps")
        case .sleep: return String(localized: "Sleep")
        case .category(let c):
            switch c {
            case .body: return String(localized: "Body", comment: "Energy category")
            case .mind: return String(localized: "Mind", comment: "Energy category")
            case .heart: return String(localized: "Heart", comment: "Energy category")
            }
        }
    }

    @ViewBuilder
    private func overlayContent(for kind: MetricOverlayKind) -> some View {
        switch kind {
        case .steps:
            stepsOverlayBody
        case .sleep:
            sleepOverlayBody
        case .category(let c):
            categoryOverlayBody(for: c)
        }
    }

    private func categoryAccentColor(_ category: EnergyCategory) -> Color {
        switch category {
        case .body:  return .orange
        case .mind:  return .purple
        case .heart: return .pink
        }
    }

    private func categoryOverlayBody(for category: EnergyCategory) -> some View {
        let maxPts = EnergyDefaults.maxSelectionsPerCategory * EnergyDefaults.selectionPoints
        let total: Int = {
            switch category {
            case .body: return model.bodyPointsToday
            case .mind: return model.mindPointsToday
            case .heart: return model.heartPointsToday
            }
        }()
        let titles = selectionTitles(for: category)
        let progress = maxPts > 0 ? Double(total) / Double(maxPts) : 0
        let accent = categoryAccentColor(category)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(total)")
                    .font(.title2.bold())
                Text("/\(maxPts)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "colors", comment: "Category overlay – unit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent)
                        .frame(width: max(4, w * progress), height: 8)
                }
            }
            .frame(height: 8)

            if titles.isEmpty {
                Text(String(localized: "No activities selected yet", comment: "Category overlay – empty hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(titles, id: \.self) { title in
                        Text(title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(accent.opacity(0.12)))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
    }

    private var stepsOverlayBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCompactNumber(Int(model.healthStore.stepsToday)))
                        .font(.title2.bold())
                    Text(String(localized: "steps today"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.stepsPointsToday)/\(EnergyDefaults.stepsMaxPoints)")
                        .font(.title3.bold())
                    Text(String(localized: "colors"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(String(localized: "Target: \(formatCompactNumber(Int(userStepsTarget))) steps"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sleepOverlayBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isSleepAssumed {
                HStack {
                    Text(String(localized: "Sleep: \(EnergyDefaults.assumedSleepPoints) colors", comment: "Sleep overlay – assumed sleep header"))
                        .font(.title3.bold())
                    Spacer()
                    Image(systemName: "gift.fill")
                        .foregroundStyle(AppColors.brandAccent)
                }
                Text(String(localized: "sleep_assumed_message", comment: "Sleep overlay – warm message when no sleep data"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.healthStore.dailySleepHours.formatted(.number.precision(.fractionLength(1))))h")
                            .font(.title2.bold())
                        Text(String(localized: "hours slept"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(model.sleepPointsToday)/\(EnergyDefaults.sleepMaxPoints)")
                            .font(.title3.bold())
                        Text(String(localized: "colors"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(String(localized: "Target: \(userSleepTarget.formatted(.number.precision(.fractionLength(1))))h"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func breakdownText(for category: EnergyCategory) -> String {
        let maxPts = EnergyDefaults.maxSelectionsPerCategory * EnergyDefaults.selectionPoints
        switch category {
        case .body:
            let extras = selectionTitles(for: .body)
            let total = model.bodyPointsToday
            if extras.isEmpty {
                return String(localized: "Body tracks movement and exercise. Pick up to 4 cards for \(maxPts) colors (\(total) colors today).")
            }
            return String(localized: "Body tracks movement and exercise. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) colors for my body.")
        case .mind:
            let extras = selectionTitles(for: .mind)
            let total = model.mindPointsToday
            if extras.isEmpty {
                return String(localized: "Mind tracks rest and attention. Pick up to 4 cards for \(maxPts) colors (\(total) colors today).")
            }
            return String(localized: "Mind tracks rest and attention. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) colors for my mind.")
        case .heart:
            let extras = selectionTitles(for: .heart)
            let total = model.heartPointsToday
            if extras.isEmpty {
                return String(localized: "Heart tracks things that make you feel alive. Pick up to 4 cards for \(maxPts) colors (\(total) colors today).")
            }
            return String(localized: "Heart tracks what makes you feel alive. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) colors for my heart.")
        }
    }

    private func selectionTitles(for category: EnergyCategory) -> [String] {
        let ids: [String]
        switch category {
        case .body: ids = model.dailyBodySelections
        case .mind: ids = model.dailyRestSelections
        case .heart: ids = model.dailyHeartSelections
        }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return ids.map { id in
            EnergyDefaults.options.first(where: { $0.id == id })?.title(for: lang)
                ?? model.customOptionTitle(for: id, lang: lang)
                ?? id
        }
    }
}
