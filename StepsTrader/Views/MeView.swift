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
    @State private var showTargetsEditor = false
    @State private var showDayEndSettings = false
    @State private var cachedDayKeys: [String] = []
    @State private var hasLoadedSnapshots = false
    @State private var cachedTopConsumers: [(name: String, spent: Int)] = []
    @State private var cachedTxNames: [String: String] = [:]

    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader())
    private var stepsTarget: Double = EnergyDefaults.stepsTarget
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader())
    private var sleepTarget: Double = EnergyDefaults.sleepTargetHours

    var body: some View {
        NavigationStack {
            Group {
                if useTightMeLayout {
                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 0) {
                            weekRow
                                .padding(.top, 2)
                                .padding(.bottom, 6)
                            contentSection
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            weekRow
                                .padding(.top, 8)
                                .padding(.bottom, 20)
                            contentSection
                                .padding(.bottom, 24)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .energyGradientBackground(model: model)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                guard !hasLoadedSnapshots else { return }
                hasLoadedSnapshots = true
                cachedDayKeys = Self.computeDayKeys()
                loadAllSnapshots()
            }
            .onChange(of: model.baseEnergyToday) { _, _ in
                let newKeys = Self.computeDayKeys()
                if newKeys != cachedDayKeys {
                    cachedDayKeys = newKeys
                    loadAllSnapshots()
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
            .sheet(isPresented: $showTargetsEditor) {
                MeTargetsSheet(
                    model: model,
                    stepsTarget: $stepsTarget,
                    sleepTarget: $sleepTarget
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showDayEndSettings) {
                NavigationStack {
                    DayEndSettingsView(model: model)
                }
                .presentationDetents([.medium])
            }
            .sheet(item: Binding(
                get: { selectedDayKey.map { MeDayKeyWrapper(key: $0) } },
                set: { selectedDayKey = $0?.key }
            )) { wrapper in
                CanvasDayDetailSheet(
                    model: model,
                    dayKey: wrapper.key,
                    snapshot: pastDays[wrapper.key],
                    onDismiss: { selectedDayKey = nil }
                )
            }
        }
    }

    // MARK: - Content

    /// One-screen layout for default type sizes; scroll when accessibility sizes need more room.
    private var useTightMeLayout: Bool {
        dynamicTypeSize < .accessibility1
    }

    private var meProse: Font {
        useTightMeLayout ? .subheadline : .body
    }

    private var meNumberProse: Font {
        (useTightMeLayout ? Font.subheadline : Font.body).weight(.semibold)
    }

    private var weekRingOuter: CGFloat { useTightMeLayout ? 32 : 40 }
    private var weekRingInner: CGFloat { useTightMeLayout ? 29 : 37 }
    private var weekDayLabelSize: CGFloat { useTightMeLayout ? 8 : 9 }

    private var contentSection: some View {
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        let topActivities = topActivityNames(from: snaps)
        let weekEarned = snaps.reduce(0) { $0 + $1.inkEarned }
        let weekSpent = snaps.reduce(0) { $0 + $1.inkSpent }
        let dayCount = max(snaps.count, 1)
        let avgSleep = snaps.reduce(0.0) { $0 + $1.sleepHours } / Double(dayCount)
        let avgSteps = snaps.reduce(0) { $0 + $1.steps } / dayCount
        let topConsumerNames = cachedTopConsumers.prefix(3).map(\.name)

        let sleepStr = sleepTarget.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(sleepTarget))" : String(format: "%.1f", sleepTarget)

        let greetingLineSpacing: CGFloat = useTightMeLayout ? 5 : 8

        return VStack(alignment: .leading, spacing: useTightMeLayout ? CGFloat(10) : CGFloat(20)) {

            // Four fixed lines so "and … sleep" never wraps with a lone "and" at line end.
            VStack(alignment: .leading, spacing: greetingLineSpacing) {
                MeFlowLayout(spacing: 4, lineSpacing: greetingLineSpacing) {
                    label(greetingString + ",")
                    valuePill("person.fill", userName) {
                        if authService.isAuthenticated { showProfileEditor = true }
                        else { showLogin = true }
                    }
                }
                MeFlowLayout(spacing: 4, lineSpacing: greetingLineSpacing) {
                    label(String(localized: "You are aiming for"))
                    valuePill("figure.walk", formatCompactNumber(Int(stepsTarget))) {
                        showTargetsEditor = true
                    }
                    label(String(localized: "steps"))
                }
                MeFlowLayout(spacing: 4, lineSpacing: greetingLineSpacing) {
                    label(String(localized: "and"))
                    valuePill("moon.zzz.fill", sleepStr + "h") {
                        showTargetsEditor = true
                    }
                    label(String(localized: "sleep."))
                }
                MeFlowLayout(spacing: 4, lineSpacing: greetingLineSpacing) {
                    label(String(localized: "Your day resets at"))
                    valuePill("clock", formattedDayEnd) {
                        showDayEndSettings = true
                    }
                }
            }

            // This week card
            if !snaps.isEmpty {
                let hasData = weekEarned > 0 || weekSpent > 0 || avgSteps > 0 || !topActivities.isEmpty || !topConsumerNames.isEmpty

                if hasData {
                    let sleepAvg = String(format: "%.1f", avgSleep)
                    let stepsAvg = formatCompactNumber(avgSteps)
                    let showHealthLine = avgSteps > 0 || avgSleep > 0
                    let showEarnSection = weekEarned > 0 || !topActivities.isEmpty || showHealthLine
                    let showSpentSection = weekSpent > 0 || !topConsumerNames.isEmpty

                    VStack(alignment: .leading, spacing: useTightMeLayout ? 7 : 14) {
                        Text(String(localized: "THIS WEEK"))
                            .font(.system(size: useTightMeLayout ? 10 : 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        if weekEarned > 0 {
                            MeFlowLayout(spacing: 4, lineSpacing: useTightMeLayout ? 5 : 8) {
                                label(String(localized: "This week you earned"))
                                weekSummaryNumber(weekEarned)
                                label(String(localized: "colors"))
                            }
                        }

                        if !topActivities.isEmpty {
                            MeFlowLayout(spacing: 4, lineSpacing: useTightMeLayout ? 5 : 8) {
                                label(String(localized: "Mostly from"))
                                inlinePillList(topActivities, icon: "paintpalette")
                            }
                        }

                        if showHealthLine {
                            MeFlowLayout(spacing: 4, lineSpacing: useTightMeLayout ? 5 : 8) {
                                label(String(localized: "and also"))
                                dataPill("moon.zzz.fill", sleepAvg + "h")
                                label(String(localized: "sleep and"))
                                dataPill("figure.walk", stepsAvg)
                                label(String(localized: "steps a day."))
                            }
                        }

                        if showEarnSection && showSpentSection {
                            Spacer().frame(height: useTightMeLayout ? 2 : 4)
                        }

                        if weekSpent > 0 {
                            MeFlowLayout(spacing: 4, lineSpacing: useTightMeLayout ? 5 : 8) {
                                label(String(localized: "This week you spent"))
                                weekSummaryNumber(weekSpent)
                                label(String(localized: "colors"))
                            }
                        }

                        if !topConsumerNames.isEmpty {
                            MeFlowLayout(spacing: 4, lineSpacing: useTightMeLayout ? 5 : 8) {
                                label(String(localized: "Mostly on"))
                                inlinePillList(topConsumerNames, icon: "play.fill")
                            }
                        }
                    }
                    .padding(useTightMeLayout ? 12 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.thinMaterial)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Components

    private func label(_ text: String) -> some View {
        Text(text)
            .font(meProse)
            .foregroundStyle(theme.textPrimary)
    }

    private func valuePill(_ icon: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(text)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.4)
            }
            .font(meProse)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.backgroundSecondary)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(theme.stroke.opacity(0.45), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Double tap to change", comment: "MeView – interactive pill VoiceOver hint"))
    }

    private func dataPill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Text(text)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(theme.textPrimary)
        }
        .font(meProse)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(theme.stroke.opacity(0.35), lineWidth: 0.5)
                )
        )
    }

    private func weekSummaryNumber(_ value: Int) -> some View {
        Text("\(value)")
            .font(meNumberProse)
            .foregroundStyle(theme.textPrimary)
            .monospacedDigit()
    }

    @ViewBuilder
    private func inlinePillList(_ items: [String], icon: String) -> some View {
        let count = items.count
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            if index > 0 && index == count - 1 {
                label("and")
            }
            dataPill(icon, item + (index < count - 2 ? "," : ""))
        }
    }

    // MARK: - Helpers

    private var greetingString: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        case 17..<22: return String(localized: "Good evening")
        default: return String(localized: "Good night")
        }
    }

    private var userName: String {
        if authService.isAuthenticated, let user = authService.currentUser {
            return user.displayName
        }
        return String(localized: "someone")
    }

    private var formattedDayEnd: String {
        if model.dayEndHour == 0 && model.dayEndMinute == 0 {
            return String(localized: "midnight")
        }
        var comps = DateComponents()
        comps.hour = model.dayEndHour
        comps.minute = model.dayEndMinute
        guard let date = Calendar.current.date(from: comps) else {
            return "\(model.dayEndHour):\(String(format: "%02d", model.dayEndMinute))"
        }
        return CachedFormatters.hourMinute.string(from: date)
    }

    private func topActivityNames(from snapshots: [PastDaySnapshot]) -> [String] {
        var counts: [String: Int] = [:]
        for snap in snapshots {
            for id in snap.bodyIds + snap.mindIds + snap.heartIds {
                counts[id, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return [] }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map { model.resolveOptionTitle(for: $0.key) }
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
        dayKey == AppModel.dayKey(for: Date())
    }

    private static func computeDayKeys() -> [String] {
        let cal = Calendar.current
        let (endH, endM) = DayBoundary.storedDayEnd()
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return DayBoundary.dayKey(for: d, dayEndHour: endH, dayEndMinute: endM)
        }
    }

    // MARK: - Data Loading

    private func loadAllSnapshots() {
        pastDays = model.loadPastDaySnapshots()
        Task.detached {
            let names = Self.loadTransactionNameMap()
            await MainActor.run { cachedTxNames = names }
        }
        rebuildTopConsumers()
        Task {
            let server = await SupabaseSyncService.shared.loadHistoricalSnapshots()
            await MainActor.run {
                var changed = false
                for (key, snap) in server where pastDays[key] == nil {
                    pastDays[key] = snap
                    changed = true
                }
                if changed { rebuildTopConsumers() }
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

        var results: [(name: String, spent: Int)] = []
        var claimedKeys: Set<String> = []

        for group in model.ticketGroups {
            let groupKey = "group_\(group.id)"
            var total = allSpending[groupKey] ?? 0
            if total > 0 { claimedKeys.insert(groupKey) }
            if let raw = allSpending[group.id] {
                total += raw
                claimedKeys.insert(group.id)
            }
            if total > 0 { results.append((name: group.name, spent: total)) }
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
            results.append((name: name, spent: value))
        }

        cachedTopConsumers = results
            .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }
            .prefix(5)
            .map { $0 }
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

// MARK: - Flow Layout

private struct MeFlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var rows: [[Int]] = [[]]
        var rowWidths: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        var sizes: [CGSize] = []

        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            sizes.append(size)

            let gap = rows.last!.isEmpty ? 0 : spacing
            if rowWidths.last! + gap + size.width > maxWidth && !rows.last!.isEmpty {
                rows.append([])
                rowWidths.append(0)
                rowHeights.append(0)
            }

            rows[rows.count - 1].append(i)
            rowWidths[rowWidths.count - 1] += (rows.last!.count > 1 ? spacing : 0) + size.width
            rowHeights[rowHeights.count - 1] = max(rowHeights.last!, size.height)
        }

        positions = Array(repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        for (ri, row) in rows.enumerated() {
            let rh = rowHeights[ri]
            var x: CGFloat = 0
            for idx in row {
                positions[idx] = CGPoint(x: x, y: y + (rh - sizes[idx].height) / 2)
                x += sizes[idx].width + spacing
            }
            y += rh + lineSpacing
        }

        let totalH = rowHeights.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return (CGSize(width: maxWidth, height: totalH), positions)
    }
}

// MARK: - Targets Sheet

private struct MeTargetsSheet: View {
    @ObservedObject var model: AppModel
    @Binding var stepsTarget: Double
    @Binding var sleepTarget: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private let stepsOptions: [Double] = [3000, 5000, 6000, 7000, 8000, 10_000, 12_000, 15_000, 20_000]
    private let sleepOptions: [Double] = [5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.stroke.opacity(theme.strokeOpacity))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 28)

            targetRow(
                icon: "figure.walk",
                label: String(localized: "Steps"),
                value: formatCompactNumber(Int(stepsTarget)),
                onMinus: { stepValue(in: stepsOptions, current: &stepsTarget, by: -1) },
                onPlus: { stepValue(in: stepsOptions, current: &stepsTarget, by: 1) }
            )

            Spacer().frame(height: 16)

            targetRow(
                icon: "moon.zzz.fill",
                label: String(localized: "Sleep"),
                value: sleepTarget.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(sleepTarget))h"
                    : String(format: "%.1fh", sleepTarget),
                onMinus: { stepValue(in: sleepOptions, current: &sleepTarget, by: -1) },
                onPlus: { stepValue(in: sleepOptions, current: &sleepTarget, by: 1) }
            )

            Spacer()
        }
        .padding(.horizontal, 24)
        .onDisappear {
            UserDefaults.stepsTrader().set(stepsTarget, forKey: SharedKeys.userStepsTarget)
            UserDefaults.stepsTrader().set(sleepTarget, forKey: SharedKeys.userSleepTarget)
            model.recalculateDailyEnergy()
        }
    }

    private func targetRow(icon: String, label: String, value: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(theme.adaptiveMutedText)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(theme.textPrimary)

            Spacer()

            HStack(spacing: 16) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.adaptiveSecondaryText)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(theme.backgroundSecondary.opacity(0.8)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Decrease \(label)", comment: "MeTargetsSheet – stepper VoiceOver label"))

                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 50)

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.adaptiveSecondaryText)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(theme.backgroundSecondary.opacity(0.8)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Increase \(label)", comment: "MeTargetsSheet – stepper VoiceOver label"))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.backgroundSecondary.opacity(0.5))
        )
    }

    private func stepValue(in options: [Double], current: inout Double, by direction: Int) {
        guard let idx = options.firstIndex(of: current) else {
            current = options.min(by: { abs($0 - current) < abs($1 - current) }) ?? current
            return
        }
        let newIdx = idx + direction
        guard options.indices.contains(newIdx) else { return }
        current = options[newIdx]
    }
}

private struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
