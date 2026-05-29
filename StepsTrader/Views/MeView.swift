import SwiftUI

// MARK: - Me tab
struct MeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var selectedDayKey: String? = nil
    @State private var showLogin = false
    @State private var showProfileEditor = false
    @State private var cachedDayKeys: [String] = []
    @State private var hasLoadedSnapshots = false
    @State private var cachedTopApps: [(name: String, spent: Int, minutes: Int)] = []
    @State private var cachedWeekMinutesByTarget: [String: Int] = [:]
    @State private var cachedTxNames: [String: String] = [:]
    @State private var loadTask: Task<Void, Never>?
    @State private var serverFetchTask: Task<Void, Never>?
    @State private var axisDetail: AxisDetailContext? = nil

    // Radar model — derived from snapshots once per data load, NOT per body pass.
    // The radar background, the tap overlay and the stats row all read these so
    // the (non-trivial) week-summary + axes computation runs once, off the
    // SwiftUI hot path.
    @State private var radarSnaps: [PastDaySnapshot] = []
    @State private var radarSummary = MeWeekSummary()
    @State private var radarAxes: [EnergySignatureView.Axis] = []
    // The radar canvas (in `.background`) and the tap circle (in `.overlay`) live
    // in two separate GeometryReaders whose `safeAreaInsets.top` can differ by
    // `topCardHeight` (the background sits before `.safeAreaInset`, the overlay
    // after). Hand-computing `centerY` independently in each therefore drifts
    // them apart vertically, so taps land at the wrong angle. The radar publishes
    // its true centre in GLOBAL coords; the tap circle anchors to that exact
    // point so the two can never diverge.
    @State private var radarCenterGlobalY: CGFloat? = nil

    var body: some View {
        NavigationStack {
            mainScrollContent
                // Radar sits behind the scroll content as a screen-spanning
                // canvas — rays bleed wherever they want, never clipped by a
                // layout frame.
                .background {
                    radarBackground
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
                .onPreferenceChange(RadarCenterKey.self) { radarCenterGlobalY = $0 }
                .energyGradientBackground(model: model, showGrain: false)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: topCardHeight)
                }
                // Grain texture overlay — above content so it picks up rays beneath.
                .overlay {
                    if !reduceTransparency {
                        TextureOverlayView(texture: CanvasTexture.fromStored(canvasTextureRaw))
                            .allowsHitTesting(false)
                            .ignoresSafeArea()
                    }
                }
                // Invisible tap target sitting exactly over the radar's label
                // ring — restores tap-to-open-AxisDetail without the radar
                // background swallowing taps on greeting / stats.
                .overlay {
                    radarTapOverlay
                        .ignoresSafeArea()
                }
                // Liquid Glass popover for axis detail (Steps / Sleep / etc.) —
                // presented in-place as a card with a close button, not as a
                // bottom sheet.
                .overlay {
                    axisDetailOverlay
                        .ignoresSafeArea()
                }
                .toolbar(.hidden, for: .navigationBar)
                .modifier(meLifecycle)
                .modifier(meSheets)
        }
    }

    // MARK: - Radar layout math
    //
    // Single source of truth for the Y position of the radar centre. Used by
    // both the visual background canvas and the invisible tap overlay so they
    // can never drift apart.
    // Published by the radar canvas, consumed by the tap circle, so both share
    // one source of truth for the centre (see `radarCenterGlobalY`).
    private struct RadarCenterKey: PreferenceKey {
        static let defaultValue: CGFloat? = nil
        static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
            value = nextValue() ?? value
        }
    }

    private struct RadarLayout {
        let centerY: CGFloat
        /// Outer radius of the tap band, in screen-width units. Slightly smaller
        /// than the canvas's outerR so the overlay never extends into the
        /// greeting (above) or stats (below).
        let tapOuterR: CGFloat
        /// Inner dead-zone — taps closer than this to centre are ignored.
        let tapInnerR: CGFloat
    }

    private func radarLayout(in proxy: GeometryProxy) -> RadarLayout {
        let W = proxy.size.width
        // Inside a `.background` / `.overlay` with `.ignoresSafeArea()` the
        // proxy reports the DEVICE safe area only — it does NOT include the
        // `.safeAreaInset(.top, topCardHeight)` we add for the energy bar. So
        // we have to add `topCardHeight` ourselves to line up with where the
        // foreground ScrollView actually starts laying out content.
        let safeTop = proxy.safeAreaInsets.top + topCardHeight
        let contentTopPad: CGFloat = useTightMeLayout ? 18 : 24
        let greetingBlock: CGFloat = 53   // greeting (~30) + spacing (6) + subtitle (~17)
        let secSpacing:    CGFloat = useTightMeLayout ? 20 : 28
        let radarReserve = W * 0.78
        // Visual nudge: labels are asymmetric — low-score axes (e.g. Body)
        // sit close to centre while high-score axes (e.g. Steps) sit at the
        // outer ring, which makes the geometric midpoint feel high. Push the
        // centre down a hair so the perceived middle of the radar matches the
        // empty space between the subtitle and the earned/spent row.
        let visualBalance: CGFloat = 60
        let centerY = safeTop
                    + contentTopPad
                    + greetingBlock
                    + secSpacing
                    + radarReserve / 2
                    + visualBalance
        return RadarLayout(
            centerY: centerY,
            tapOuterR: W * 0.40,   // covers labels w/ a tap-friendly margin
            tapInnerR: W * 0.08    // matches EnergySignatureView.handleTap
        )
    }

    // MARK: - Radar Background
    //
    // Full-screen Canvas hosting the rays + grid + labels. The radar is positioned
    // so its centre lands on the midpoint of the reserved gap between the
    // subtitle and the earned/spent row. The canvas itself still spans the full
    // screen so beams fade out in all directions without hitting a frame.

    @ViewBuilder
    private var radarBackground: some View {
        if !radarAxes.isEmpty {
            GeometryReader { proxy in
                let layout = radarLayout(in: proxy)
                let W = proxy.size.width
                let H = proxy.size.height
                // Where the radar's drawing centre actually lands on screen.
                let centerGlobalY = proxy.frame(in: .global).minY + layout.centerY

                EnergySignatureView(
                    axes: radarAxes,
                    canvasSize: W,
                    canvasHeight: H,
                    showSpotlights: true
                )
                .frame(width: W, height: H)
                .position(x: W / 2, y: layout.centerY)
                .preference(key: RadarCenterKey.self, value: centerGlobalY)
            }
        }
    }

    // MARK: - Radar Tap Overlay
    //
    // Tiny invisible circular hit zone, sized to the radar's label ring and
    // anchored to the radar centre. Taps outside the circle pass straight
    // through to whatever's underneath (greeting button, scroll view, etc.).
    // The circle's `onTapGesture` mirrors `EnergySignatureView.handleTap` to
    // pick the nearest axis and present `AxisDetail`.

    @ViewBuilder
    private var radarTapOverlay: some View {
        if !radarAxes.isEmpty {
            let snaps = radarSnaps
            let summary = radarSummary
            let axes = radarAxes
            GeometryReader { proxy in
                let layout = radarLayout(in: proxy)
                let diameter = layout.tapOuterR * 2
                // Anchor to the radar's published centre (global → this overlay's
                // local space) so the tap circle sits exactly over the labels,
                // regardless of any safe-area difference between the two readers.
                let centerY: CGFloat = radarCenterGlobalY.map {
                    $0 - proxy.frame(in: .global).minY
                } ?? layout.centerY

                Color.clear
                    .frame(width: diameter, height: diameter)
                    .contentShape(Circle())
                    // Tap gesture must be attached BEFORE `.position` — `.position`
                    // stretches the view to fill the parent, which would make
                    // `location` arrive in full-screen coords instead of this
                    // circle's local space. Here `location` is local to the
                    // diameter×diameter frame, so centre = (tapOuterR, tapOuterR).
                    .onTapGesture { location in
                        let dx = Double(location.x - layout.tapOuterR)
                        let dy = Double(location.y - layout.tapOuterR)
                        let dist = sqrt(dx * dx + dy * dy)
                        guard dist > Double(layout.tapInnerR) else { return }

                        // Subtract current canvas rotation (1°/s) so the tap
                        // angle is compared against axes' base angles.
                        let rotationSpeed: Double = 1.0 * .pi / 180
                        let now = Date.now.timeIntervalSinceReferenceDate
                        let tapAngle = atan2(dy, dx) - now * rotationSpeed

                        if let best = axes.min(by: {
                            Self.angularDist($0.angle, tapAngle)
                                < Self.angularDist($1.angle, tapAngle)
                        }) {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                axisDetail = AxisDetailContext(
                                    axis: best,
                                    snaps: snaps,
                                    avgSteps: summary.avgSteps,
                                    avgSleep: summary.avgSleep
                                )
                            }
                        }
                    }
                    .position(x: proxy.size.width / 2, y: centerY)
            }
        }
    }

    private static func angularDist(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d < 0 { d += 2 * .pi }
        return min(d, 2 * .pi - d)
    }


    @ViewBuilder
    private var mainScrollContent: some View {
        if useTightMeLayout {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        contentSection
                            .padding(.bottom, 40)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: geo.size.width)
                    .frame(minHeight: geo.size.height, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    contentSection
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var meLifecycle: MeLifecycleModifier {
        MeLifecycleModifier(
            model: model,
            cachedDayKeys: $cachedDayKeys,
            hasLoadedSnapshots: $hasLoadedSnapshots,
            loadTask: $loadTask,
            serverFetchTask: $serverFetchTask,
            onLoad: { loadAllSnapshots() },
            onDayEndChange: { refreshDayKeysAndReload() },
            onTopConsumersChange: { rebuildTopConsumers() }
        )
    }

    private var meSheets: MeSheetsModifier {
        MeSheetsModifier(
            model: model,
            authService: authService,
            showLogin: $showLogin,
            showProfileEditor: $showProfileEditor,
            selectedDayKey: $selectedDayKey
        )
    }

    // MARK: - Content

    /// One-screen layout for default type sizes; scroll when accessibility sizes need more room.
    private var useTightMeLayout: Bool {
        dynamicTypeSize < .accessibility1
    }

    private var meProse: Font {
        useTightMeLayout ? .subheadline : .body
    }

    private var weekRingOuter: CGFloat { useTightMeLayout ? 32 : 40 }
    private var weekRingInner: CGFloat { useTightMeLayout ? 29 : 37 }
    private var weekDayLabelSize: CGFloat { useTightMeLayout ? 8 : 9 }

    private var contentSection: some View {
        let snaps = radarSnaps
        let weekEarned = snaps.reduce(0) { $0 + $1.inkEarned }
        let weekSpent = snaps.reduce(0) { $0 + $1.inkSpent }
        let sectionSpacing: CGFloat = useTightMeLayout ? 20 : 28
        // Reserved vertical space where the radar grid is visible behind the
        // foreground content. The radar itself lives in `radarBackground` and
        // spans the full screen — this just keeps the stats from landing on
        // top of the radar's labels.
        let radarReserve: CGFloat = UIScreen.main.bounds.width * 0.78

        return VStack(alignment: .leading, spacing: sectionSpacing) {

            // ── Greeting + subtitle ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                greetingRow
                Text(String(localized: "Statistics for the last 7 days",
                            comment: "MeView – weekly overview subtitle"))
                    .font(.system(size: useTightMeLayout ? 12 : 13))
                    .foregroundStyle(theme.textSecondary.opacity(0.50))
            }
            .padding(.top, useTightMeLayout ? 18 : 24)

            // ── Reserved space so the radar circle sits visually between
            //    greeting (above) and stats (below).
            if !snaps.isEmpty {
                Color.clear.frame(height: radarReserve)
            }

            // ── Stats below the radar ────────────────────────────────────────
            if weekEarned > 0 || weekSpent > 0 || !cachedTopApps.isEmpty {
                if weekEarned > 0 || weekSpent > 0 {
                    compactColorsRow(earned: weekEarned, spent: weekSpent)
                }
                if !cachedTopApps.isEmpty {
                    topAppsSection(apps: Array(cachedTopApps.prefix(3)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Axis Detail Overlay (Liquid Glass)

    @ViewBuilder
    private var axisDetailOverlay: some View {
        ZStack {
            if let ctx = axisDetail {
                // Dimmed backdrop — tap to dismiss.
                Color.black.opacity(0.40)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissAxisDetail() }
                    .transition(.opacity)

                // Glass card hosting the AxisDetailView. The X lives inside
                // the header (AxisDetailView wires it up via onClose). The
                // card height is content-driven — `.fixedSize` on the inner
                // VStack makes the card hug its data so there's no empty
                // space below the last row.
                AxisDetailView(context: ctx, model: model, onClose: dismissAxisDetail)
                    .frame(maxWidth: 360)
                    .glassCard(cornerRadius: 26, style: .frosted)
                    .padding(.horizontal, 20)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: axisDetail?.id)
    }

    private func dismissAxisDetail() {
        withAnimation(.easeOut(duration: 0.22)) {
            axisDetail = nil
        }
    }

    // MARK: - Greeting

    /// Greeting is the page anchor: muted salutation, bolder name. One clear focal point above the canvas.
    private var greetingFont: Font {
        useTightMeLayout ? .headline : .title3
    }

    private var greetingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(greetingString + ",")
                .font(greetingFont)
                .foregroundStyle(theme.textPrimary.opacity(0.55))
            Button {
                if authService.hasAppleAccount { showProfileEditor = true }
                else { showLogin = true }
            } label: {
                Text(userName)
                    .font(greetingFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Profile, \(userName). Double tap to edit.", comment: "MeView – profile pill VoiceOver label"))
        }
    }

    // MARK: - Section Header

    /// Soft, modern section title — keeps the localized key (which may be uppercased in source)
    /// but renders without heavy tracking so it recedes behind the data.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: useTightMeLayout ? 11 : 12, weight: .medium))
            .foregroundStyle(theme.textSecondary.opacity(0.55))
            .tracking(0.6)
    }

    // MARK: - Compact Colors Row

    /// Two-stat row: colored dot + big rounded number + small label below.
    /// Drops redundant `+`/`−` prefixes (the label already says "earned" / "spent")
    /// and gives each value its own visual block so the eye can grab one at a time.
    private func compactColorsRow(earned: Int, spent: Int) -> some View {
        HStack(alignment: .top, spacing: 28) {
            statPair(
                value: earned,
                label: String(localized: "earned"),
                accent: theme.accentColor
            )
            statPair(
                value: spent,
                label: String(localized: "spent"),
                accent: theme.textSecondary.opacity(0.45)
            )
            Spacer(minLength: 0)
        }
    }

    private func statPair(value: Int, label: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .padding(.top, useTightMeLayout ? 8 : 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(value.formatted())
                    .font(.system(useTightMeLayout ? .title3 : .title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Colors Earned / Spent (legacy — kept for reference)

    private func colorsSection(earned: Int, spent: Int) -> some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 6 : 10) {
            sectionHeader(String(localized: "THIS WEEK"))

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(earned)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                    Text(String(localized: "earned"))
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("−\(spent)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                    Text(String(localized: "spent"))
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Averages

    private func averagesSection(summary: MeWeekSummary) -> some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 6 : 10) {
            sectionHeader(String(localized: "AVERAGES"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 4 : 8) {
                if summary.avgSteps > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 18, alignment: .center)
                        Text(formatCompactNumber(summary.avgSteps))
                            .font(meProse.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                        Text(String(localized: "steps/day"))
                            .font(useTightMeLayout ? .caption : .subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                if summary.avgSleep > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 18, alignment: .center)
                        Text(summary.avgSleep.formatted(.number.precision(.fractionLength(1))) + "h")
                            .font(meProse.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                        Text(String(localized: "sleep/day"))
                            .font(useTightMeLayout ? .caption : .subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Activities

    private func activitiesSection(summary: MeWeekSummary) -> some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 6 : 10) {
            sectionHeader(String(localized: "ACTIVITIES"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 4 : 8) {
                if !summary.topBody.isEmpty {
                    activityRow(icon: "flame.fill", items: summary.topBody)
                }
                if !summary.topMind.isEmpty {
                    activityRow(icon: "brain.head.profile.fill", items: summary.topMind)
                }
                if !summary.topHeart.isEmpty {
                    activityRow(icon: "heart.fill", items: summary.topHeart)
                }
            }
        }
    }

    private func activityRow(icon: String, items: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, alignment: .center)
            Text(items.joined(separator: ", "))
                .font(useTightMeLayout ? .caption : .subheadline)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
        }
    }

    // MARK: - Top Apps

    /// Top apps as proportional bars: ranking is visible at a glance instead of read off the numbers.
    /// The longest bar is the heaviest app this week; everything else scales relative to it.
    private func topAppsSection(apps: [(name: String, spent: Int, minutes: Int)]) -> some View {
        let maxMinutes = max(1, apps.map(\.minutes).max() ?? 1)
        return VStack(alignment: .leading, spacing: useTightMeLayout ? 8 : 12) {
            sectionHeader(String(localized: "TOP APPS"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 12) {
                ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                    appBarRow(name: app.name, minutes: app.minutes, maxMinutes: maxMinutes)
                }
            }
        }
    }

    private func appBarRow(name: String, minutes: Int, maxMinutes: Int) -> some View {
        // Minimum fraction so even tiny values are visible as a hint, not invisible.
        let fraction = max(0.04, CGFloat(minutes) / CGFloat(maxMinutes))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(useTightMeLayout ? .footnote : .subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(formatAppTime(minutes))
                    .font((useTightMeLayout ? Font.footnote : Font.subheadline).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.textPrimary.opacity(0.08))
                    Capsule()
                        .fill(theme.accentColor.opacity(0.75))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)  // bar is decorative; the row already announces name + time
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(formatAppTime(minutes))")
    }

    private func formatAppTime(_ totalMinutes: Int) -> String {
        if totalMinutes <= 0 { return "—" }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    // MARK: - Helpers

    private var greetingString: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 5..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        case 17..<22: return String(localized: "Good evening")
        default: return String(localized: "Good night")
        }
    }

    private var userName: String {
        if authService.hasAppleAccount, let user = authService.currentUser {
            return user.displayName
        }
        return String(localized: "someone")
    }

    /// Recomputes the cached radar model (snapshots → week summary → axes) from
    /// the current `pastDays` / `cachedDayKeys`. Call this whenever the snapshot
    /// set changes — NOT from `body` — so the per-frame render path only reads
    /// the cached results.
    private func rebuildRadarModel() {
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        radarSnaps = snaps
        guard !snaps.isEmpty else {
            radarSummary = MeWeekSummary()
            radarAxes = []
            return
        }
        let summary = computeWeekSummary(from: snaps)
        radarSummary = summary
        radarAxes = EnergySignatureView.makeAxes(
            from: snaps, avgSteps: summary.avgSteps, avgSleep: summary.avgSleep
        )
    }

    private func computeWeekSummary(from snapshots: [PastDaySnapshot]) -> MeWeekSummary {
        guard !snapshots.isEmpty else { return MeWeekSummary() }
        let count = snapshots.count

        let totalSteps = snapshots.reduce(0) { $0 + $1.steps }
        let totalSleep = snapshots.reduce(0.0) { $0 + $1.sleepHours }

        // topBody/topMind/topHeart are intentionally left at their defaults: the
        // only consumer (`activitiesSection`) isn't wired into the current layout,
        // so computing them — flatMap over the week × `model.resolveOptionTitle`
        // on every data load — was wasted work. The radar and AxisDetail need only
        // the averages below.
        return MeWeekSummary(
            avgSteps: totalSteps / count,
            avgSleep: totalSleep / Double(count)
        )
    }

    // MARK: - Week Row

    private var weekRow: some View {
        HStack(spacing: 0) {
            ForEach(cachedDayKeys, id: \.self) { dayKey in
                dayRing(dayKey: dayKey).frame(maxWidth: .infinity)
            }
        }
    }

    private func dayRing(dayKey: String) -> some View {
        let today = isToday(dayKey)
        return Button { selectedDayKey = dayKey } label: {
            let snapshot = pastDays[dayKey]
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(theme.stroke.opacity(theme.strokeOpacity * 0.4), lineWidth: 0.5)
                        .frame(width: weekRingOuter, height: weekRingOuter)

                    if let snap = snapshot {
                        let maxE = 100.0
                        let gained = min(1.0, Double(snap.inkEarned) / maxE)
                        let remaining = min(1.0, Double(max(0, snap.inkEarned - snap.inkSpent)) / maxE)
                        let ringLine: CGFloat = useTightMeLayout ? 2 : 2.5

                        Circle()
                            .trim(from: 0, to: remaining)
                            .stroke(theme.accentColor, lineWidth: ringLine)
                            .frame(width: weekRingInner, height: weekRingInner)
                            .rotationEffect(.degrees(-90))

                        if gained > remaining {
                            Circle()
                                .trim(from: remaining, to: gained)
                                .stroke(theme.accentColor.opacity(0.2), lineWidth: ringLine)
                                .frame(width: weekRingInner, height: weekRingInner)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                }

                Text(shortDayLabel(dayKey))
                    .font(.system(size: weekDayLabelSize, weight: today ? .bold : .regular))
                    .foregroundStyle(today ? theme.textPrimary : theme.adaptiveSecondaryText)

                Circle()
                    .fill(today ? theme.accentColor : .clear)
                    .frame(width: useTightMeLayout ? 2.5 : 3, height: useTightMeLayout ? 2.5 : 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayRingAccessibilityLabel(dayKey: dayKey))
    }

    private func dayRingAccessibilityLabel(dayKey: String) -> String {
        guard let date = CachedFormatters.dayKey.date(from: dayKey) else { return dayKey }
        let dayName = CachedFormatters.shortWeekday.string(from: date)
        guard let snap = pastDays[dayKey] else { return String(localized: "\(dayName), no data") }
        let remaining = max(0, snap.inkEarned - snap.inkSpent)
        return String(localized: "\(dayName), \(snap.inkEarned) earned, \(remaining) remaining")
    }

    private func shortDayLabel(_ dayKey: String) -> String {
        guard let date = CachedFormatters.dayKey.date(from: dayKey) else { return "" }
        return String(CachedFormatters.shortWeekday.string(from: date).prefix(2))
    }

    private func isToday(_ dayKey: String) -> Bool {
        dayKey == AppModel.dayKey(for: Date.now)
    }

    static func computeDayKeys() -> [String] {
        let cal = Calendar.current
        let (endH, endM) = DayBoundary.storedDayEnd()
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: Date.now) ?? Date.now
            return DayBoundary.dayKey(for: d, dayEndHour: endH, dayEndMinute: endM)
        }
    }

    // MARK: - Data Loading

    private func refreshDayKeysAndReload() {
        let newKeys = Self.computeDayKeys()
        guard newKeys != cachedDayKeys else { return }
        cachedDayKeys = newKeys
        loadAllSnapshots()
    }

    private func loadAllSnapshots() {
        loadTask?.cancel()
        serverFetchTask?.cancel()

        pastDays = model.loadPastDaySnapshots()
        rebuildRadarModel()

        loadTask = Task { @MainActor in
            let dayKeySet = Set(cachedDayKeys)
            let (names, minutes) = await Task.detached {
                let n = Self.loadTransactionNameMap()
                let m = Self.loadWeeklyMinutesByTarget(dayKeys: dayKeySet)
                return (n, m)
            }.value
            guard !Task.isCancelled else { return }
            cachedTxNames = names
            cachedWeekMinutesByTarget = minutes
            rebuildTopConsumers()
        }

        serverFetchTask = Task { @MainActor in
            let server = await SupabaseSyncService.shared.loadHistoricalSnapshots()
            guard !Task.isCancelled else { return }
            var changed = false
            for (key, snap) in server where pastDays[key] == nil {
                pastDays[key] = snap
                changed = true
            }
            if changed {
                rebuildRadarModel()
                rebuildTopConsumers()
            }
        }
    }

    private func rebuildTopConsumers() {
        var allSpending: [String: Int] = [:]
        for dayKey in cachedDayKeys {
            if let perApp = model.appStepsSpentByDay[dayKey] {
                for (key, value) in perApp {
                    allSpending[key, default: 0] += value
                }
            }
        }

        var results: [(name: String, spent: Int, key: String)] = []
        var claimedKeys: Set<String> = []

        for group in model.ticketGroups {
            let groupKey = "group_\(group.id)"
            var total = allSpending[groupKey] ?? 0
            if total > 0 { claimedKeys.insert(groupKey) }
            if let raw = allSpending[group.id] {
                total += raw
                claimedKeys.insert(group.id)
            }
            if total > 0 { results.append((name: group.name, spent: total, key: groupKey)) }
        }

        let txNames = cachedTxNames
        for (key, value) in allSpending.sorted(by: { $0.key < $1.key }) where !claimedKeys.contains(key) {
            let name: String
            if key.hasPrefix("group_") {
                guard let n = txNames[key] ?? txNames[String(key.dropFirst(6))], !n.isEmpty else {
                    continue
                }
                name = n
            } else {
                name = txNames[key] ?? TargetResolver.displayName(for: key)
            }
            results.append((name: name, spent: value, key: key))
        }

        let weekMinutes = cachedWeekMinutesByTarget
        cachedTopApps = results
            .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }
            .prefix(5)
            .map { entry in
                let mins = weekMinutes[entry.key]
                    ?? weekMinutes[String(entry.key.dropFirst(6))]
                    ?? 0
                return (name: entry.name, spent: entry.spent, minutes: mins)
            }
    }

    private nonisolated static func loadTransactionNameMap() -> [String: String] {
        let url = PersistenceManager.paymentTransactionsFileURL
        guard let data = try? Data(contentsOf: url),
              let txs = try? JSONDecoder().decode([TransactionNameEntry].self, from: data)
        else { return [:] }
        var map: [String: String] = [:]
        for tx in txs {
            if let name = tx.targetName, !name.isEmpty { map[tx.target] = name }
        }
        return map
    }

    private struct TransactionNameEntry: Decodable {
        let target: String
        let targetName: String?
    }

    private struct WeekTransactionEntry: Decodable {
        let timestamp: Date
        let target: String
        let window: String?
        let minutes: Int?
    }

    private nonisolated static func loadWeeklyMinutesByTarget(dayKeys: Set<String>) -> [String: Int] {
        let url = PersistenceManager.paymentTransactionsFileURL
        guard let data = try? Data(contentsOf: url),
              let txs = try? JSONDecoder().decode([WeekTransactionEntry].self, from: data)
        else { return [:] }

        var minutesByTarget: [String: Int] = [:]
        for tx in txs {
            let txKey = AppModel.dayKey(for: tx.timestamp)
            guard dayKeys.contains(txKey) else { continue }
            let resolved: Int
            if let m = tx.minutes, m > 0 {
                resolved = m
            } else {
                switch tx.window {
                case "minutes10": resolved = 10
                case "minutes30": resolved = 30
                case "hour1": resolved = 60
                default: continue
                }
            }
            minutesByTarget[tx.target, default: 0] += resolved
        }
        return minutesByTarget
    }
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
