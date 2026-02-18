import SwiftUI

// MARK: - Me tab
struct MeView: View {
    @ObservedObject var model: AppModel
    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var selectedDayKey: String? = nil
    @State private var showLogin = false
    @State private var showProfileEditor = false
    @State private var cachedDayKeys: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                EnergyGradientBackground(
                    stepsPoints: model.stepsPointsToday,
                    sleepPoints: model.sleepPointsToday,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 24) {
                    // Profile: compact inline row
                    profileRow

                    // 7-day ring row (always 7 slots)
                    weekRow

                    // Reflection line (hidden when empty)
                    if hasAnyData {
                        reflectionLine
                    }

                    // Body · Mind · Heart (hidden when no picks)
                    if hasAnyPicks {
                        Text("mostly from")
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textSecondary)
                        dimensionRow
                    }

                    // Average sleep & steps
                    if hasAnyData {
                        weeklyAveragesLine
                    }

                    // Top energy consumers (week)
                    if !topConsumers.isEmpty {
                        topConsumersSection
                    }

                    Spacer()

                    // Totals line
                    if hasAnyData {
                        totalsLine
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .navigationBarHidden(true)
            .onAppear {
                cachedDayKeys = Self.computeDayKeys()
                loadAllSnapshots()
            }
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
            .sheet(item: Binding(
                get: { selectedDayKey.map { MeDayKeyWrapper(key: $0) } },
                set: { selectedDayKey = $0?.key }
            )) { wrapper in
                GalleryDayDetailSheet(
                    model: model,
                    dayKey: wrapper.key,
                    snapshot: pastDays[wrapper.key],
                    onDismiss: { selectedDayKey = nil }
                )
            }
        }
    }

    // MARK: - Computed helpers

    private var hasAnyData: Bool {
        !pastDays.isEmpty
    }

    private var hasAnyPicks: Bool {
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        return snaps.contains { !$0.bodyIds.isEmpty || !$0.mindIds.isEmpty || !$0.heartIds.isEmpty }
    }

    /// Compute 7 day-keys once (today and 6 prior days), using the custom day boundary
    /// so keys stay correct between midnight and the configured day-end time.
    private static func computeDayKeys() -> [String] {
        let cal = Calendar.current
        let (endH, endM) = DayBoundary.storedDayEnd()
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return DayBoundary.dayKey(for: d, dayEndHour: endH, dayEndMinute: endM)
        }
    }

    // MARK: - Data loading

    private func loadAllSnapshots() {
        pastDays = model.loadPastDaySnapshots()
        Task {
            let server = await SupabaseSyncService.shared.loadHistoricalSnapshots()
            await MainActor.run {
                for (key, snap) in server where pastDays[key] == nil {
                    pastDays[key] = snap
                }
            }
        }
    }

    // MARK: - Profile row (avatar + name, single line)

    private var profileRow: some View {
        Button {
            if authService.isAuthenticated { showProfileEditor = true }
            else { showLogin = true }
        } label: {
            HStack(spacing: 10) {
                avatarView
                if authService.isAuthenticated, let user = authService.currentUser {
                    Text(user.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                } else {
                    Text("Sign in")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var avatarView: some View {
        if authService.isAuthenticated, let user = authService.currentUser {
            if let data = user.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .grayscale(1.0)
                    .overlay(Circle().strokeBorder(theme.accentColor, lineWidth: 1))
            } else {
                ZStack {
                    Circle().fill(Color(.systemGray5)).frame(width: 40, height: 40)
                    Text(String(user.displayName.prefix(2)).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundColor(theme.textPrimary)
                }
                .overlay(Circle().strokeBorder(theme.accentColor, lineWidth: 1))
            }
        } else {
            ZStack {
                Circle().fill(theme.stroke.opacity(theme.strokeOpacity)).frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(theme.textSecondary)
            }
        }
    }

    // MARK: - 7-day ring row (always 7 slots)

    private var weekRow: some View {
        HStack(spacing: 0) {
            ForEach(cachedDayKeys, id: \.self) { dayKey in
                dayRing(dayKey: dayKey)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayRing(dayKey: String) -> some View {
        Button { selectedDayKey = dayKey } label: {
            let snapshot = pastDays[dayKey]
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .stroke(theme.stroke.opacity(theme.strokeOpacity), lineWidth: 1)
                        .frame(width: 36, height: 36)

                    if let snap = snapshot {
                        let maxE = 100.0
                        let gained = min(1.0, Double(snap.inkEarned) / maxE)
                        let remaining = min(1.0, Double(max(0, snap.inkEarned - snap.inkSpent)) / maxE)

                        Circle()
                            .trim(from: 0, to: remaining)
                            .stroke(theme.accentColor, lineWidth: 2.5)
                            .frame(width: 33, height: 33)
                            .rotationEffect(.degrees(-90))

                        if gained > remaining {
                            Circle()
                                .trim(from: remaining, to: gained)
                                .stroke(theme.accentColor.opacity(0.25), lineWidth: 2.5)
                                .frame(width: 33, height: 33)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                }

                Text(shortDayLabel(dayKey))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isToday(dayKey) ? theme.textPrimary : theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func shortDayLabel(_ dayKey: String) -> String {
        guard let date = CachedFormatters.dayKey.date(from: dayKey) else { return "" }
        return String(CachedFormatters.shortWeekday.string(from: date).prefix(2))
    }

    private func isToday(_ dayKey: String) -> Bool {
        return dayKey == AppModel.dayKey(for: Date())
    }

    // MARK: - Reflection (single centered line)

    private var reflectionLine: some View {
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        let gained = snaps.reduce(0) { $0 + $1.inkEarned }
        let spent = snaps.reduce(0) { $0 + $1.inkSpent }
        let kept = max(0, gained - spent)

        return VStack(spacing: 4) {
            if gained > 0 {
                Text("My week")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textPrimary)
                Text("\(gained) earned · \(spent) spent · \(kept) kept")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .monospacedDigit()
            } else {
                Text("No activity yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weekly averages (sleep + steps)

    private var weeklyAveragesLine: some View {
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        let dayCount = max(snaps.count, 1)
        let avgSleep = snaps.reduce(0.0) { $0 + $1.sleepHours } / Double(dayCount)
        let avgSteps = snaps.reduce(0) { $0 + $1.steps } / dayCount
        let sleepText = String(format: "%.1f", avgSleep)

        return Text("avg \(sleepText)h sleep · \(avgSteps) steps / day")
            .font(.caption.weight(.medium))
            .foregroundColor(theme.textSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
    }

    // MARK: - Body · Mind · Heart

    private var dimensionRow: some View {
        let snaps = cachedDayKeys.compactMap { pastDays[$0] }
        let topBody = topOptionId(for: .body, from: snaps)
        let topMind = topOptionId(for: .mind, from: snaps)
        let topHeart = topOptionId(for: .heart, from: snaps)

        return HStack(spacing: 0) {
            dimensionItem(icon: "figure.run", optionId: topBody)
            dimensionItem(icon: "sparkles", optionId: topMind)
            dimensionItem(icon: "heart.fill", optionId: topHeart)
        }
    }

    private func dimensionItem(icon: String, optionId: String?) -> some View {
        VStack(spacing: 3) {
            if let id = optionId {
                if id.hasPrefix("custom_") {
                    Image(systemName: optionIcon(for: id))
                        .font(.system(size: 22))
                        .foregroundColor(theme.textPrimary)
                } else {
                    Image(assetImageName(for: id))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                Text(model.resolveOptionTitle(for: id))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(theme.textSecondary.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top Energy Consumers

    private var topConsumers: [(name: String, spent: Int)] {
        // Aggregate all spending across the 7-day window
        var allSpending: [String: Int] = [:]
        for dayKey in cachedDayKeys {
            if let perApp = model.appStepsSpentByDay[dayKey] {
                for (key, value) in perApp {
                    allSpending[key, default: 0] += value
                }
            }
        }

        // Build results from ticket groups first (guaranteed correct names)
        var results: [(name: String, spent: Int)] = []
        var claimedKeys: Set<String> = []

        for group in model.ticketGroups {
            let groupKey = "group_\(group.id)"
            var total = allSpending[groupKey] ?? 0
            if total > 0 { claimedKeys.insert(groupKey) }

            // Also claim spending under the raw group id
            if let raw = allSpending[group.id] {
                total += raw
                claimedKeys.insert(group.id)
            }

            if total > 0 {
                results.append((name: group.name, spent: total))
            }
        }

        // Remaining keys not claimed by any current group
        let txNames = Self.loadTransactionNameMap()
        for (key, value) in allSpending where !claimedKeys.contains(key) {
            let name: String
            if key.hasPrefix("group_") {
                // Orphaned group — look up stored name from payment log
                name = txNames[key] ?? txNames[String(key.dropFirst(6))] ?? "Deleted ticket"
            } else {
                name = txNames[key] ?? TargetResolver.displayName(for: key)
            }
            results.append((name: name, spent: value))
        }

        return results
            .sorted { $0.spent > $1.spent }
            .prefix(5)
            .map { $0 }
    }

    /// Build a map of spending target → display name from the payment transaction log.
    private static func loadTransactionNameMap() -> [String: String] {
        let url = PersistenceManager.paymentTransactionsFileURL
        guard let data = try? Data(contentsOf: url),
              let txs = try? JSONDecoder().decode([TransactionNameEntry].self, from: data)
        else { return [:] }
        var map: [String: String] = [:]
        for tx in txs {
            if let name = tx.targetName, !name.isEmpty {
                map[tx.target] = name
            }
        }
        return map
    }

    /// Minimal decodable for reading just target + targetName from the payment log.
    private struct TransactionNameEntry: Decodable {
        let target: String
        let targetName: String?
    }

    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top consumers")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)

            ForEach(Array(topConsumers.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 16, alignment: .trailing)

                    Text(item.name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(item.spent) ink")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.accentColor)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Totals

    private var totalsLine: some View {
        let totalG = pastDays.values.reduce(0) { $0 + $1.inkEarned }
        let totalS = pastDays.values.reduce(0) { $0 + $1.inkSpent }
        return Text("\(pastDays.count)d · \(totalG) earned · \(totalS) spent")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(theme.textSecondary)
            .monospacedDigit()
    }

    // MARK: - Helpers

    private func topOptionId(for category: EnergyCategory, from snapshots: [PastDaySnapshot]) -> String? {
        var counts: [String: Int] = [:]
        for s in snapshots {
            let ids: [String] = switch category {
            case .body: s.bodyIds
            case .mind: s.mindIds
            case .heart: s.heartIds
            }
            for id in ids { counts[id, default: 0] += 1 }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func optionIcon(for optionId: String) -> String {
        if optionId.hasPrefix("custom_"),
           let c = model.customEnergyOptions.first(where: { $0.id == optionId }) { return c.icon }
        return EnergyDefaults.options.first(where: { $0.id == optionId })?.icon ?? "circle.fill"
    }

    private func assetImageName(for optionId: String) -> String { optionId }
}

private struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

// MARK: - Glass card modifier (iOS 26+ liquid glass, fallback ultraThinMaterial)

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension View {
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
