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
    /// Whether to cap-and-scroll instead of hugging content, decided from the
    /// environment rather than a measured height. This screen's canvas
    /// redraws continuously (the generative animation), which reconstructs
    /// this view on every frame and was found — empirically, via logging —
    /// to reset any `@State` used to remember a `GeometryReader`-measured
    /// content height back to its default before `onPreferenceChange` ever
    /// got a chance to persist the real value. `dynamicTypeSize` carries no
    /// such risk: it's read fresh from the environment every render, so
    /// there's nothing to lose between renders.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The app's own custom tab bar (Canvas / Feeds / Me), threaded down from
    /// `MainTabView`. It sits *above* the system home-indicator safe area, so
    /// `windowSafeAreaInsets.bottom` alone understates how much of the bottom
    /// of the screen is actually occupied — without this, the card's cap left
    /// room for the home indicator but the card still rendered underneath the
    /// tab bar itself.
    @Environment(\.tabBarHeight) private var tabBarHeight

    /// The real device safe-area insets, read from the key window rather than
    /// a nested `GeometryReader`'s `safeAreaInsets`. This view sits under a
    /// backdrop that calls `.ignoresSafeArea()`, and — per the same failure
    /// mode documented on `GalleryView.deviceTopSafeAreaInset` — a
    /// `GeometryReader` this deep in an `.overlay` stack with an
    /// `.ignoresSafeArea()` ancestor reads unreliably small.
    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    /// Room reserved above the card: the status bar / Dynamic Island, plus a
    /// little breathing room.
    private var topReserve: CGFloat { windowSafeAreaInsets.top + 16 }

    /// Room reserved below the card: the home indicator *and* the custom tab
    /// bar (Canvas / Feeds / Me), plus a little breathing room. Without
    /// `tabBarHeight`, the safe-area inset alone only accounts for the home
    /// indicator — the tab bar sits above that, so the card would still
    /// render underneath it.
    private var bottomReserve: CGFloat { windowSafeAreaInsets.bottom + tabBarHeight + 16 }

    /// The tallest the card may grow before its content must scroll instead.
    /// At default text sizes the content's ideal height is always
    /// comfortably under this, so the cap never engages.
    private func cardHeightCap(availableHeight: CGFloat) -> CGFloat {
        max(280, availableHeight - topReserve - bottomReserve)
    }

    var body: some View {
        GeometryReader { proxy in
            let cap = cardHeightCap(availableHeight: proxy.size.height)

            ZStack {
                // Same dim backdrop as the radar AxisDetail overlay in MeView.
                Color.black.opacity(0.40)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }
                    .accessibilityHidden(true)

                // Liquid Glass card. At every ordinary Dynamic Type size —
                // including the largest non-accessibility size, xxxLarge —
                // this renders as a plain (non-scrolling) stack, sized to its
                // content and centered exactly as it always was: pixel-
                // identical to how this card always looked.
                //
                // Only once the type size crosses into the accessibility
                // range (AX1–AX5) does it switch to a header pinned above a
                // `ScrollView` capped at `cap`, so the rest — including the
                // research link — stays reachable by scrolling instead of
                // running off both edges of the screen. The header (title +
                // close button) stays *outside* the `ScrollView` rather than
                // scrolling with the content: a plain `VStack` given a fixed
                // `frame(maxHeight:)` hands each child its own ideal size
                // first — the header gets exactly what it needs — and lets
                // the one flexible child (the `ScrollView`) fill whatever's
                // left, so there's no need to measure the header's height by
                // hand. It also means the close button — and the backdrop
                // tap, which is always available regardless — stay reachable
                // no matter how far the user has scrolled.
                //
                // That branch positions the card with two
                // `Spacer(minLength:)`s rather than relying on the `ZStack`'s
                // own centering: given a fixed `frame(maxHeight:)`, this
                // header+ScrollView pair always renders at exactly `cap`
                // (the ScrollView is what absorbs any slack, and it never
                // reports back less than it's given), so the card's height
                // here is deterministically `cap` — meaning the two
                // `Spacer`s land on exactly `topReserve` and `bottomReserve`
                // with nothing left over to redistribute, unlike plain
                // `ZStack` centering, which would only split the *average*
                // of the two reserves and could still let the card creep
                // under the (much taller) bottom chrome.
                // `scrollBounceBehavior(.basedOnSize)` keeps that ScrollView
                // inert (no bounce, no indicator) whenever its content
                // doesn't actually need to scroll.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        Spacer(minLength: topReserve)
                        VStack(spacing: 0) {
                            header
                                .padding(.horizontal, 20)
                                .padding(.top, 22)
                                .padding(.bottom, 16)
                            ScrollView {
                                scrollableBody
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 22)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                        .frame(maxHeight: cap)
                        .frame(maxWidth: 360)
                        .glassCard(cornerRadius: 26, style: .frosted)
                        .padding(.horizontal, 20)
                        Spacer(minLength: bottomReserve)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        scrollableBody
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 360)
                    .glassCard(cornerRadius: 26, style: .frosted)
                    .padding(.horizontal, 20)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var header: some View {
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
    }

    private var scrollableBody: some View {
        VStack(alignment: .leading, spacing: 16) {
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
