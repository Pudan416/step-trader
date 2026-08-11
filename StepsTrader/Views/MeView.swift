import SwiftUI

// MARK: - Me tab
struct MeView: View {
    @ObservedObject var model: AppModel
    /// Opens the settings sheet. Owned by `MainTabView`, not by this view, so a
    /// feature-tip deep link works even if Me has never been on screen.
    var onOpenSettings: () -> Void = {}
    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var selectedDayKey: String? = nil
    @State private var showLogin = false
    @State private var showProfileEditor = false
    @State private var showPaywall = false
    @State private var cachedDayKeys: [String] = []
    @State private var hasLoadedSnapshots = false
    @State private var cachedTopApps: [(name: String, spent: Int)] = []
    @State private var cachedTxNames: [String: String] = [:]
    @State private var loadTask: Task<Void, Never>?
    @State private var serverFetchTask: Task<Void, Never>?

    // The week's snapshots and the numbers derived from them, computed once per
    // data load rather than per body pass — the aggregation is not free and must
    // stay off the SwiftUI hot path.
    @State private var cachedSnaps: [PastDaySnapshot] = []
    @State private var cachedSummary = MeWeekStats.Summary()

    var body: some View {
        NavigationStack {
            mainScrollContent
                .energyGradientBackground(model: model, showGrain: false)
                // No inset for the energy card: it is not drawn on Me, and
                // `\.topCardHeight` still reports the height it has on the other
                // tabs — reserving it here would leave an empty band.
                // Grain texture overlay — above content so it picks up rays beneath.
                .overlay {
                    if !reduceTransparency {
                        TextureOverlayView(texture: CanvasTexture.fromStored(canvasTextureRaw))
                            .allowsHitTesting(false)
                            .ignoresSafeArea()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .modifier(meLifecycle)
                .modifier(meSheets)
        }
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
                // The tab bar is an overlay, not a safe-area inset, so the last
                // row would otherwise scroll under the pill and stop there.
                .safeAreaPadding(.bottom, tabBarHeight)
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
            .safeAreaPadding(.bottom, tabBarHeight)
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
            selectedDayKey: $selectedDayKey,
            showPaywall: $showPaywall
        )
    }

    // MARK: - Content

    /// One-screen layout for default type sizes; scroll when accessibility sizes need more room.
    private var useTightMeLayout: Bool {
        dynamicTypeSize < .accessibility1
    }


    private var contentSection: some View {
        let sectionSpacing: CGFloat = useTightMeLayout ? 20 : 28

        return VStack(alignment: .leading, spacing: sectionSpacing) {

            // ── Greeting ──────────────────────────────────────────────────────
            // No subtitle: it claimed "the last 7 days" over a screen that now
            // ends in a calendar of every day ever recorded. Each section names
            // its own window instead.
            greetingRow
                .padding(.top, useTightMeLayout ? 18 : 24)

            // ── This week, in three numbers ───────────────────────────────────
            weekSummarySection(cachedSummary)

            // ── Connected apps ────────────────────────────────────────────────
            if !cachedTopApps.isEmpty {
                connectedAppsSection(apps: Array(cachedTopApps.prefix(5)))
            }

            // ── The calendar ──────────────────────────────────────────────────
            // `pastDays` is every persisted day, not just this week's window, so
            // the strip needs no loader of its own.
            MeCalendarStrip(
                model: model,
                pastDays: pastDays,
                onSelect: { selectedDayKey = $0 },
                onLocked: { showPaywall = true }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    // MARK: - This week, in three numbers
    //
    // Sleep, steps, happenings — the three things a day is made of, one reading
    // each. A reading with nothing behind it is omitted rather than shown as a
    // zero, so a quiet week reads as quiet instead of as failure.

    @ViewBuilder
    private func weekSummarySection(_ summary: MeWeekStats.Summary) -> some View {
        if summary.avgSleepHours > 0 || summary.avgSteps > 0 || !summary.topHappeningIds.isEmpty {
            VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 14) {
                sectionHeader(String(localized: "THIS WEEK", comment: "MeView – week summary section header"))

                if summary.avgSleepHours > 0 {
                    summaryRow(
                        icon: "moon.zzz.fill",
                        value: summary.avgSleepHours.formatted(.number.precision(.fractionLength(1))) + "h",
                        label: String(localized: "sleep a night", comment: "MeView – average sleep label")
                    )
                }

                if summary.avgSteps > 0 {
                    summaryRow(
                        icon: "figure.walk",
                        value: summary.avgSteps.formatted(),
                        label: String(localized: "steps a day", comment: "MeView – average steps label")
                    )
                }

                if !summary.topHappeningIds.isEmpty {
                    let titles = summary.topHappeningIds.map { model.resolveOptionTitle(for: $0) }
                    summaryRow(
                        icon: "sparkles",
                        value: titles.joined(separator: ", "),
                        label: String(localized: "came up most", comment: "MeView – frequent happenings label"),
                        monospaced: false
                    )
                }
            }
        }
    }

    private func summaryRow(
        icon: String,
        value: String,
        label: String,
        monospaced: Bool = true
    ) -> some View {
        // Digits line up column-wise; happening titles are prose and must not.
        let valueFont = Font.system(useTightMeLayout ? .title3 : .title2, design: .rounded)
            .weight(.semibold)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(monospaced ? valueFont.monospacedDigit() : valueFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value), \(label)")
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

            Spacer(minLength: 12)

            Button { onOpenSettings() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(theme.textPrimary.opacity(0.7))
                    // Same warning the Me tab icon carries — kept here so the
                    // trail from tab badge to the actual entry point is unbroken.
                    if model.hasPermissionIssues {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -2)
                    }
                }
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("me_settings_button")
            .accessibilityLabel(String(localized: "Settings", comment: "MeView – settings button VoiceOver label"))
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

    // MARK: - Connected apps
    //
    // Each connected app with the colors it cost this week. Bars are relative to
    // the heaviest app, so the ranking reads at a glance. The number is exact:
    // it comes from the per-day spend ledger, not from the payment log.

    private func connectedAppsSection(apps: [(name: String, spent: Int)]) -> some View {
        let maxSpent = max(1, apps.map(\.spent).max() ?? 1)
        return VStack(alignment: .leading, spacing: useTightMeLayout ? 8 : 12) {
            sectionHeader(String(localized: "CONNECTED APPS", comment: "MeView – connected apps section header"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 12) {
                ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                    appBarRow(name: app.name, spent: app.spent, maxSpent: maxSpent)
                }
            }
        }
    }

    private func appBarRow(name: String, spent: Int, maxSpent: Int) -> some View {
        // Minimum fraction so even tiny values are visible as a hint, not invisible.
        let fraction = max(0.04, CGFloat(spent) / CGFloat(maxSpent))
        let spentLabel = String(localized: "\(spent) colors", comment: "MeView – per-app color spend")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(useTightMeLayout ? .footnote : .subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(spentLabel)
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
            .accessibilityHidden(true)  // bar is decorative; the row already announces name + spend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(spentLabel)")
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



    static func computeDayKeys() -> [String] {
        let cal = Calendar.current
        let (endH, endM) = DayBoundary.storedDayEnd()
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: Date.now) ?? Date.now
            return DayBoundary.dayKey(for: d, dayEndHour: endH, dayEndMinute: endM)
        }
    }

    // MARK: - Data Loading

    /// Recomputes the cached week model from the current `pastDays` /
    /// `cachedDayKeys`. Call this whenever the snapshot set changes — NOT from
    /// `body` — so the per-frame render path only reads the cached results.
    private func rebuildWeekModel() {
        cachedSnaps = cachedDayKeys.compactMap { pastDays[$0] }
        cachedSummary = MeWeekStats.summary(snapshots: cachedSnaps)
    }

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
        rebuildWeekModel()

        loadTask = Task { @MainActor in
            // The payment log is read only for display names now — targets that
            // are no longer in a ticket group would otherwise show a raw key.
            let names = await Task.detached { Self.loadTransactionNameMap() }.value
            guard !Task.isCancelled else { return }
            cachedTxNames = names
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
                rebuildWeekModel()
                rebuildTopConsumers()
            }
        }
    }

    private func rebuildTopConsumers() {
        let allSpending = MeWeekStats.appSpend(
            byDay: model.appStepsSpentByDay,
            dayKeys: cachedDayKeys
        )

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

        cachedTopApps = results
            .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }
            .prefix(5)
            .map { (name: $0.name, spent: $0.spent) }
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
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
