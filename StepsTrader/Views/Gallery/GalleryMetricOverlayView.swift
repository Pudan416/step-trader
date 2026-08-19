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

                Divider()
                    .overlay(Color.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 10) {
                    Text(explanation(for: kind))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(String(localized: "You can change your daily goals in Settings.",
                                comment: "MetricOverlay – where to adjust goals"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    Link(destination: researchURL(for: kind)) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Read the research",
                                        comment: "MetricOverlay – link to the source study"))
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    }
                    .accessibilityIdentifier("metric_research_link_\(kind.id)")
                }
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
        case .happenings: return String(localized: "Happenings", comment: "Daily happenings metric")
        }
    }

    @ViewBuilder
    private func overlayContent(for kind: MetricOverlayKind) -> some View {
        switch kind {
        case .steps:
            stepsOverlayBody
        case .sleep:
            sleepOverlayBody
        case .happenings:
            happeningsOverlayBody
        }
    }

    private var happeningsOverlayBody: some View {
        let maxPts = HappeningDefaults.happeningsMaxPoints
        let total = model.happeningPointsToday
        let titles = model.todayAdditions.map { model.resolveOptionTitle(for: $0.optionId) }
        let progress = Double(total) / Double(maxPts)
        let accent = AppColors.brandAccent

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
                Text(String(localized: "No happenings yet", comment: "Happenings overlay – empty hint"))
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

    /// What this metric contributes to the day, in one breath. The point is to
    /// answer "why is this number what it is", not to advise.
    private func explanation(for kind: MetricOverlayKind) -> String {
        switch kind {
        case .steps:
            return String(
                localized: "Steps fill up to \(EnergyDefaults.stepsMaxPoints) of the day's \(EnergyDefaults.maxBaseEnergy) colors, in proportion to your daily step goal.",
                comment: "MetricOverlay – how steps contribute"
            )
        case .sleep:
            return String(
                localized: "Sleep fills up to \(EnergyDefaults.sleepMaxPoints) of the day's \(EnergyDefaults.maxBaseEnergy) colors, in proportion to your sleep goal. A night without data is assumed rather than counted as zero.",
                comment: "MetricOverlay – how sleep contributes"
            )
        case .happenings:
            return String(
                localized: "Happenings fill up to \(HappeningDefaults.happeningsMaxPoints) of the day's \(EnergyDefaults.maxBaseEnergy) colors — the largest share, because they are the part of the day you choose. Each happening counts once per day.",
                comment: "MetricOverlay – how happenings contribute"
            )
        }
    }

    /// The study behind each metric's share of the day. Supplied by the
    /// product owner; force-unwrapped because these are compile-time literals
    /// and a malformed one should fail loudly in the first preview, not
    /// silently render a dead link.
    private func researchURL(for kind: MetricOverlayKind) -> URL {
        switch kind {
        case .steps:
            return URL(string: "https://pubmed.ncbi.nlm.nih.gov/24749966/")!
        case .sleep:
            return URL(string: "https://www.nature.com/articles/nrn2762")!
        case .happenings:
            return URL(string: "https://www.sciencedirect.com/science/article/pii/S0022103112000212")!
        }
    }
}
