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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var recentHealthByDay: [String: MeDayHealth] = [:]
    @State private var selectedPosterDayKey = AppModel.dayKey(for: .now)
    @State private var selectedDayKey: String? = nil
    @State private var showLogin = false
    @State private var showProfileEditor = false
    @State private var showFullCalendar = false
    @State private var cachedDayKeys: [String] = []
    @State private var hasLoadedSnapshots = false
    @State private var cachedTopApps: [(name: String, spent: Int)] = []
    @State private var cachedTxNames: [String: String] = [:]
    @State private var unlockRecords: [MePosterUnlockRecord] = []
    @State private var selectedPosterCanShare = false
    @State private var shareRequestID = 0
    @State private var posterPagingDirection: MePosterPaging.Direction = .newer
    @GestureState private var posterDragTranslation: CGFloat = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var serverFetchTask: Task<Void, Never>?

    // The week's snapshots and the numbers derived from them, computed once per
    // data load rather than per body pass — the aggregation is not free and must
    // stay off the SwiftUI hot path.
    @State private var cachedSnaps: [PastDaySnapshot] = []
    @State private var cachedSummary = MeWeekStats.Summary()
    @State private var cachedComparison = MeWeekStats.Comparison(
        sleepHoursDelta: nil,
        stepsPercentDelta: nil
    )

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
        ScrollView(.vertical) {
            contentSection
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.top)
        .safeAreaPadding(.bottom, tabBarHeight)
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
            showFullCalendar: $showFullCalendar,
            selectedDayKey: $selectedDayKey,
            pastDays: pastDays
        )
    }

    // MARK: - Content

    /// One-screen layout for default type sizes; scroll when accessibility sizes need more room.
    private var useTightMeLayout: Bool {
        dynamicTypeSize < .accessibility1
    }


    private var contentSection: some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 14 : 24) {
            greetingRow
                .padding(.top, useTightMeLayout ? 14 : 22)

            ZStack {
                MeSelectedDayPoster(
                    model: model,
                    dayKey: selectedPosterDayKey,
                    snapshot: pastDays[selectedPosterDayKey],
                    health: recentHealthByDay[selectedPosterDayKey],
                    unlockRecords: unlockRecords,
                    shareRequestID: shareRequestID,
                    onShareAvailabilityChange: { selectedPosterCanShare = $0 }
                )
                .id(selectedPosterDayKey)
                .offset(x: posterDragTranslation)
                .transition(posterPagingTransition)
            }
            .clipped()
            // Keep the seven-day gallery rail clear of the floating tab bar on
            // shorter iPhones. Because this is an inset rather than a fixed
            // width, the poster still grows naturally on Pro Max layouts.
            .padding(.horizontal, 21)
            .contentShape(Rectangle())
            .simultaneousGesture(posterPagingGesture)

            calendarSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendarSection: some View {
        MeCalendarStrip(
            pastDays: pastDays,
            recentHealthByDay: recentHealthByDay,
            selectedDayKey: selectedPosterDayKey,
            onSelect: { key in
                selectPosterDay(key)
            },
            posterCount: pastDays.count,
            onOpenArchive: { showFullCalendar = true }
        )
    }

    private var posterPagingGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($posterDragTranslation) { value, translation, _ in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                translation = MePosterPagingMotion.permittedDragTranslation(
                    horizontal,
                    from: selectedPosterDayKey,
                    dayKeys: posterDayKeys,
                    reduceMotion: reduceMotion
                )
            }
            .onEnded { value in
                let horizontal = value.predictedEndTranslation.width
                let vertical = value.predictedEndTranslation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) >= 44 else { return }

                let direction: MePosterPaging.Direction = horizontal < 0 ? .newer : .older
                guard let destination = MePosterPaging.destination(
                    from: selectedPosterDayKey,
                    direction: direction,
                    dayKeys: posterDayKeys
                ) else { return }
                selectPosterDay(destination, direction: direction)
            }
    }

    private var posterDayKeys: [String] {
        cachedDayKeys.isEmpty ? Self.computeDayKeys() : cachedDayKeys
    }

    private var posterPagingTransition: AnyTransition {
        let spec = MePosterPagingMotion.transition(
            for: posterPagingDirection,
            reduceMotion: reduceMotion
        )
        guard let insertion = spec.insertionEdge,
              let removal = spec.removalEdge
        else { return .opacity }

        return .asymmetric(
            insertion: .move(edge: swiftUIEdge(insertion)),
            removal: .move(edge: swiftUIEdge(removal))
        )
    }

    private func swiftUIEdge(_ edge: MePosterPagingMotion.HorizontalEdge) -> Edge {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private func selectPosterDay(
        _ key: String,
        direction explicitDirection: MePosterPaging.Direction? = nil
    ) {
        guard key != selectedPosterDayKey else { return }
        let direction = explicitDirection ?? inferredPagingDirection(to: key)
        let motion = MePosterPagingMotion.transition(
            for: direction,
            reduceMotion: reduceMotion
        )
        posterPagingDirection = direction
        selectedPosterCanShare = false
        withAnimation(.easeInOut(duration: motion.duration)) {
            selectedPosterDayKey = key
        }
    }

    private func inferredPagingDirection(to destination: String) -> MePosterPaging.Direction {
        guard let currentIndex = posterDayKeys.firstIndex(of: selectedPosterDayKey),
              let destinationIndex = posterDayKeys.firstIndex(of: destination)
        else { return destination > selectedPosterDayKey ? .newer : .older }
        return destinationIndex > currentIndex ? .newer : .older
    }


    // MARK: - This week, in three numbers
    //
    // Sleep and steps stay visible before HealthKit has delivered data;
    // happenings form a compact visual frequency field beneath them.

    @ViewBuilder
    private func weekSummarySection(_ summary: MeWeekStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 14) {
            sectionHeader(String(localized: "THIS WEEK", comment: "MeView – week summary section header"))

            summaryRow(
                icon: "moon.zzz.fill",
                value: summary.avgSleepHours.formatted(.number.precision(.fractionLength(1))) + "h",
                label: String(localized: "sleep a night", comment: "MeView – average sleep label"),
                trend: cachedComparison.sleepHoursDelta.map { String(format: "%+.1fh", $0) },
                accessibilityIdentifier: "me_week_sleep_average"
            )

            summaryRow(
                icon: "figure.walk",
                value: summary.avgSteps.formatted(),
                label: String(localized: "steps a day", comment: "MeView – average steps label"),
                trend: cachedComparison.stepsPercentDelta.map { String(format: "%+d%%", $0) },
                accessibilityIdentifier: "me_week_steps_average"
            )

            if !summary.topHappenings.isEmpty {
                Divider()
                    .overlay(theme.stroke.opacity(theme.strokeOpacity))

                MeWeekHappeningsView(
                    happenings: summary.topHappenings,
                    resolveTitle: { model.resolveOptionTitle(for: $0) }
                )
            }
        }
    }

    private func summaryRow(
        icon: String,
        value: String,
        label: String,
        trend: String?,
        accessibilityIdentifier: String
    ) -> some View {
        // Digits line up column-wise; happening titles are prose and must not.
        let valueFont = Font.geist(useTightMeLayout ? .title3 : .title2, design: .rounded)
            .weight(.semibold)
        let trendAccessibilityLabel = trend.map {
            $0 + ", " + String(localized: "vs last week", comment: "MeView – comparison period")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.geist(size: 13))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(theme.textPrimary.opacity(0.055), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(valueFont.monospacedDigit())
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(label)
                    .font(.geist(.caption))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            }

            if let trend {
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(trend)
                        .font(.geist(.subheadline).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accentColor.opacity(0.9))
                    Text(String(localized: "vs last week", comment: "MeView – comparison period"))
                        .font(.geist(.caption2))
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(
            [
                value,
                label,
                trendAccessibilityLabel
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    // MARK: - Greeting

    /// Greeting is the page anchor: muted salutation, bolder name. One clear focal point above the canvas.
    private var greetingFont: Font {
        .geist(useTightMeLayout ? .headline : .title3)
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

            Button { shareRequestID &+= 1 } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.geist(size: 17, weight: .regular))
                    .foregroundStyle(theme.textPrimary.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!selectedPosterCanShare)
            .opacity(selectedPosterCanShare ? 1 : 0.28)
            .accessibilityIdentifier("me_share_selected_day")
            .accessibilityLabel(String(localized: "Share this day", comment: "Me poster – share action"))

            Button { onOpenSettings() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.geist(size: 18, weight: .regular))
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
            .font(.geist(size: useTightMeLayout ? 11 : 12, weight: .medium))
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
            sectionHeader(String(localized: "COLORS SPENT THIS WEEK", comment: "MeView – connected apps section header"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 12) {
                ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                    appResourceRow(
                        name: app.name,
                        spent: app.spent,
                        maxSpent: maxSpent,
                        variant: index
                    )
                }
            }
        }
    }

    private func appResourceRow(
        name: String,
        spent: Int,
        maxSpent: Int,
        variant: Int
    ) -> some View {
        let fraction = MeConnectedAppFill.fraction(
            spent: spent,
            maximumSpent: maxSpent
        )
        let spentLabel = String(localized: "\(spent) colors", comment: "MeView – per-app color spend")
        let shape = ResourcePebbleShape(variant: variant)

        return ZStack {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.14)))

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ResourceGradientFill()
                        .frame(width: geometry.size.width * fraction)
                    Spacer(minLength: 0)
                }
            }
            .clipShape(shape)
            .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.26), location: 0),
                    .init(color: .black.opacity(0.08), location: 0.62),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(shape)
            .allowsHitTesting(false)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.geist(useTightMeLayout ? .footnote : .subheadline))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(spentLabel)
                    .font(
                        Font.geist(useTightMeLayout ? .footnote : .subheadline)
                            .weight(.semibold)
                    )
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: useTightMeLayout ? 54 : 62)
        .overlay(shape.stroke(theme.textPrimary.opacity(0.14), lineWidth: 0.75))
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

        let previousKeys: [String]
        if let firstKey = cachedDayKeys.first,
           let firstDate = CachedFormatters.dayKey.date(from: firstKey) {
            previousKeys = (1...7).reversed().compactMap { offset in
                Calendar.current.date(byAdding: .day, value: -offset, to: firstDate)
                    .map { CachedFormatters.dayKey.string(from: $0) }
            }
        } else {
            previousKeys = []
        }
        let previousSummary = MeWeekStats.summary(
            snapshots: previousKeys.compactMap { pastDays[$0] }
        )
        cachedComparison = MeWeekStats.comparison(
            current: cachedSummary,
            previous: previousSummary
        )
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
        recentHealthByDay = pastDays.mapValues(MeDayHealth.init(snapshot:))
        rebuildWeekModel()

        loadTask = Task { @MainActor in
            // The payment log is read only for display names now — targets that
            // are no longer in a ticket group would otherwise show a raw key.
            let paymentData = await Task.detached {
                (
                    Self.loadTransactionNameMap(),
                    Self.loadUnlockRecords()
                )
            }.value
            let healthData = await loadRecentHealth(dayKeys: cachedDayKeys)
            guard !Task.isCancelled else { return }
            cachedTxNames = paymentData.0
            unlockRecords = paymentData.1
            recentHealthByDay.merge(healthData) { _, refreshed in refreshed }
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

    private func loadRecentHealth(dayKeys: [String]) async -> [String: MeDayHealth] {
        let keys = dayKeys.isEmpty ? Self.computeDayKeys() : dayKeys
        let todayKey = AppModel.dayKey(for: .now)
        let boundary = AppModel.storedDayEnd()
        let calendar = Calendar.current
        var result: [String: MeDayHealth] = [:]

        for key in keys {
            guard !Task.isCancelled else { break }
            if key == todayKey {
                result[key] = MeDayHealth(
                    steps: model.hasStepsData ? Int(model.stepsToday) : nil,
                    sleepHours: model.hasSleepData ? model.dailySleepHours : nil
                )
                continue
            }

            guard let date = CachedFormatters.dayKey.date(from: key),
                  let start = calendar.date(
                    bySettingHour: boundary.hour,
                    minute: boundary.minute,
                    second: 0,
                    of: date
                  ),
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { continue }

            async let stepsResult = try? model.healthKitService.fetchSteps(from: start, to: end)
            async let sleepResult = try? model.healthKitService.fetchSleep(from: start, to: end)
            let (steps, sleep) = await (stepsResult, sleepResult)

            if steps != nil || sleep != nil {
                result[key] = MeDayHealth(
                    steps: steps.map { Int($0) },
                    sleepHours: sleep
                )
            }
        }
        return result
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

    private nonisolated static func loadUnlockRecords() -> [MePosterUnlockRecord] {
        let url = PersistenceManager.paymentTransactionsFileURL
        if let data = try? Data(contentsOf: url),
           let records = try? JSONDecoder().decode([MePosterUnlockRecord].self, from: data) {
            return records
        }

        let defaults = UserDefaults.stepsTrader()
        guard let data = defaults.data(forKey: "paymentTransactions_v1"),
              let records = try? JSONDecoder().decode([MePosterUnlockRecord].self, from: data)
        else { return [] }
        return records
    }

    private struct TransactionNameEntry: Decodable {
        let target: String
        let targetName: String?
    }
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
