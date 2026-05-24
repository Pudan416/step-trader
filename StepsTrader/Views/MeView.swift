import SwiftUI

// MARK: - Me tab
struct MeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    var body: some View {
        NavigationStack {
            mainScrollContent
                .energyGradientBackground(model: model, showGrain: false)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: topCardHeight)
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
                        weekRow
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        contentSection
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
                    weekRow
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                    contentSection
                        .padding(.bottom, 24)
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
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        let weekEarned = snaps.reduce(0) { $0 + $1.inkEarned }
        let weekSpent = snaps.reduce(0) { $0 + $1.inkSpent }
        let summary = computeWeekSummary(from: snaps)
        let sectionSpacing: CGFloat = useTightMeLayout ? 16 : 24

        return VStack(alignment: .leading, spacing: sectionSpacing) {

            // Greeting
            greetingRow

            if !snaps.isEmpty && (weekEarned > 0 || weekSpent > 0 || !cachedTopApps.isEmpty) {

                // Earned / Spent
                colorsSection(earned: weekEarned, spent: weekSpent)

                // Averages
                if summary.avgSteps > 0 || summary.avgSleep > 0 {
                    averagesSection(summary: summary)
                }

                // Activities
                if !summary.topBody.isEmpty || !summary.topMind.isEmpty || !summary.topHeart.isEmpty {
                    activitiesSection(summary: summary)
                }

                // Top apps
                if !cachedTopApps.isEmpty {
                    topAppsSection(apps: Array(cachedTopApps.prefix(3)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Greeting

    private var greetingRow: some View {
        HStack(spacing: 0) {
            Text(greetingString + ", ")
                .font(meProse)
                .foregroundStyle(theme.textPrimary)
            Button {
                if authService.hasAppleAccount { showProfileEditor = true }
                else { showLogin = true }
            } label: {
                Text(userName)
                    .font(meProse.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .underline(color: theme.textPrimary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Profile, \(userName). Double tap to edit.", comment: "MeView – profile pill VoiceOver label"))
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: useTightMeLayout ? 10 : 11, weight: .semibold))
            .foregroundStyle(theme.textSecondary.opacity(0.7))
            .tracking(1.5)
    }

    // MARK: - Colors Earned / Spent

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

    private func topAppsSection(apps: [(name: String, spent: Int, minutes: Int)]) -> some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 6 : 10) {
            sectionHeader(String(localized: "TOP APPS"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 4 : 8) {
                ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                    HStack {
                        Text(app.name)
                            .font(useTightMeLayout ? .caption : .subheadline)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(formatAppTime(app.minutes))
                            .font(meProse.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                }
            }
        }
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

    private func computeWeekSummary(from snapshots: [PastDaySnapshot]) -> MeWeekSummary {
        guard !snapshots.isEmpty else { return MeWeekSummary() }
        let count = snapshots.count

        let totalSteps = snapshots.reduce(0) { $0 + $1.steps }
        let totalSleep = snapshots.reduce(0.0) { $0 + $1.sleepHours }

        func topNames(for ids: [String]) -> [String] {
            var counts: [String: Int] = [:]
            for id in ids { counts[id, default: 0] += 1 }
            return counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(3)
                .map { model.resolveOptionTitle(for: $0.key) }
        }

        let allBody = snapshots.flatMap(\.bodyIds)
        let allMind = snapshots.flatMap(\.mindIds)
        let allHeart = snapshots.flatMap(\.heartIds)

        return MeWeekSummary(
            avgSteps: totalSteps / count,
            avgSleep: totalSleep / Double(count),
            topBody: topNames(for: allBody),
            topMind: topNames(for: allMind),
            topHeart: topNames(for: allHeart)
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

    fileprivate static func computeDayKeys() -> [String] {
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
            if changed { rebuildTopConsumers() }
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

private struct MeWeekSummary {
    var avgSteps: Int = 0
    var avgSleep: Double = 0
    var topBody: [String] = []
    var topMind: [String] = []
    var topHeart: [String] = []
}

private struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

private struct MeLifecycleModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @Binding var cachedDayKeys: [String]
    @Binding var hasLoadedSnapshots: Bool
    @Binding var loadTask: Task<Void, Never>?
    @Binding var serverFetchTask: Task<Void, Never>?
    let onLoad: () -> Void
    let onDayEndChange: () -> Void
    let onTopConsumersChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasLoadedSnapshots else { return }
                hasLoadedSnapshots = true
                cachedDayKeys = MeView.computeDayKeys()
                onLoad()
            }
            .onChange(of: model.baseEnergyToday) { _, _ in
                let newKeys = MeView.computeDayKeys()
                if newKeys != cachedDayKeys {
                    cachedDayKeys = newKeys
                    onLoad()
                }
            }
            .onChange(of: model.dayEndHour) { _, _ in onDayEndChange() }
            .onChange(of: model.dayEndMinute) { _, _ in onDayEndChange() }
            .onChange(of: model.appStepsSpentByDay) { _, _ in onTopConsumersChange() }
            .onChange(of: model.ticketGroups.map(\.id)) { _, _ in onTopConsumersChange() }
            .onDisappear {
                loadTask?.cancel()
                serverFetchTask?.cancel()
            }
    }
}

private struct MeSheetsModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @Binding var showLogin: Bool
    @Binding var showProfileEditor: Bool
    @Binding var selectedDayKey: String?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService, model: model)
            }
            .fullScreenCover(item: Binding(
                get: { selectedDayKey.map { MeDayKeyWrapper(key: $0) } },
                set: { selectedDayKey = $0?.key }
            )) { wrapper in
                DayCanvasViewerView(model: model, dayKey: wrapper.key)
            }
    }
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
