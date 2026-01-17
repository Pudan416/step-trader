import AudioToolbox
import SwiftUI
import UserNotifications
import Charts

// MARK: - StatusView
struct StatusView: View {
    @ObservedObject var model: AppModel
    @State private var timer: Timer?
    @State private var lastAvailableMinutes: Int = 0
    @State private var lastNotificationMinutes: Int = -1
    @State private var selectedBundleForChart: String? = nil
    @State private var chartRange: ChartRange = .today
    @State private var detailBundle: String? = nil
    @State private var showMotivation: Bool = false
    @State private var showStatExplanation: StatType? = nil
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    private let openModulesNotification = Notification.Name("com.steps.trader.open.modules")
    
    private enum StatType: String {
        case shields
        case energy
        case batteries
    }
    
    private var dayEndHour: Int { model.dayEndHour }
    private var dayEndMinute: Int { model.dayEndMinute }

    private enum ChartRange: String, CaseIterable {
        case today
        case week
        case month
        
        var days: Int {
            switch self {
            case .today: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }

    // Accent gradient for the app
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.6, green: 0.4, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        NavigationView {
            ZStack {
                // Liquid Glass background
                backgroundGradient
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Connect CTA or main content
                    if showConnectCTA {
                        connectFirstModuleCTA
                    } else {
                            // Hero card with greeting + quick stats
                            heroCard
                            
                        // Activity Chart
                        activityChartSection
                        
                        // App Usage List
                        appUsageSection
                    }
                }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
        .onChange(of: model.isTrackingTime) { _, isTracking in
            if isTracking {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            Color(.systemBackground)
            
            // Subtle gradient orbs for depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: 150, y: 100)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Hero Card (Greeting + Stats)
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(loc(appLanguage, "Your Results", "Твой прогресс"))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(loc(appLanguage, "tap icon for info", "нажми для инфо"))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            // Stats row
            HStack(spacing: 10) {
                statPill(
                    type: .shields,
                    icon: "shield.checkered",
                    value: "\(model.appUnlockSettings.count)",
                    color: .blue
                )
                
                statPill(
                    type: .energy,
                    icon: "bolt.fill",
                    value: formatNumber(totalLifetimeSpent),
                    color: .orange
                )
                
                statPill(
                    type: .batteries,
                    icon: "battery.100.bolt",
                    value: "\(batteriesCollectedTotal)",
                    color: .green
                )
            }
            
            // Explanation text
            if let stat = showStatExplanation {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(explanationText(for: stat))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(glassCard)
        .animation(.easeInOut(duration: 0.2), value: showStatExplanation)
    }
    
    private var batteriesCollectedTotal: Int {
        UserDefaults.standard.integer(forKey: "outerworld_totalcollected") / 500
    }
    
    private func explanationText(for stat: StatType) -> String {
        switch stat {
        case .shields:
            return loc(appLanguage, "Apps protected by shields. Add more in Modules tab", "Приложения под щитами. Добавьте ещё во вкладке Модули")
        case .energy:
            return loc(appLanguage, "Total energy spent on entries and shield upgrades", "Всего энергии потрачено на входы и прокачку щитов")
        case .batteries:
            return loc(appLanguage, "Batteries collected in Outer World map", "Батареек собрано на карте Outer World")
        }
    }
    
    @ViewBuilder
    private func statPill(type: StatType, icon: String, value: String, color: Color) -> some View {
        Button {
            withAnimation {
                if showStatExplanation == type {
                    showStatExplanation = nil
                } else {
                    showStatExplanation = type
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
            Image(systemName: icon)
                        .font(.subheadline.bold())
                .foregroundColor(color)
                }
            
            Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(showStatExplanation == type ? color.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Glass Card Style
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 {
            return loc(appLanguage, "Night", "Ночь")
        } else if hour < 12 {
            return loc(appLanguage, "Morning", "Утро")
        } else if hour < 17 {
            return loc(appLanguage, "Afternoon", "День")
        } else if hour < 22 {
            return loc(appLanguage, "Evening", "Вечер")
        } else {
            return loc(appLanguage, "Night", "Ночь")
        }
    }
    
    private var totalLifetimeSpent: Int {
        model.appStepsSpentLifetime.values.reduce(0, +)
    }
    
    // MARK: - Activity Chart Section
    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(loc(appLanguage, "Activity", "Активность"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                
                // Range picker - glass style
                HStack(spacing: 2) {
                    ForEach([ChartRange.today, .week, .month], id: \.self) { range in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                chartRange = range
                            }
                        } label: {
                            Text(rangeLabel(range))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(chartRange == range ? Color.blue.opacity(0.9) : Color.clear)
                                )
                                .foregroundColor(chartRange == range ? .white : .secondary)
                        }
                    }
                }
                .padding(3)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                )
            }
            
            // Chart
            let chartData = dailyOpenData
            if chartData.isEmpty {
                emptyChartPlaceholder
            } else {
                chartView(data: chartData)
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    private func rangeLabel(_ range: ChartRange) -> String {
        switch range {
        case .today: return loc(appLanguage, "Today", "Сегодня")
        case .week: return loc(appLanguage, "Week", "Неделя")
        case .month: return loc(appLanguage, "Month", "Месяц")
        }
    }
    
    private var emptyChartPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundColor(.secondary.opacity(0.35))
            Text(loc(appLanguage, "No activity yet", "Пока нет активности"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func chartView(data: [DailyOpen]) -> some View {
        if chartRange == .today {
            let todayData = trackedAppsToday.sorted { $0.steps > $1.steps }.prefix(5)
            if todayData.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(Array(todayData)) { item in
                    BarMark(
                        x: .value("App", item.name),
                        y: .value("Energy", item.steps)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colorForBundle(item.bundleId), colorForBundle(item.bundleId).opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: todayData.map { $0.name }) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 160)
            }
        } else {
            Chart(data) { item in
                let isHighlighted = (selectedBundleForChart == nil) || (selectedBundleForChart == item.bundleId)
                let baseColor = colorForBundle(item.bundleId)
                
                AreaMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Energy", item.count),
                    series: .value("App", item.appName)
                )
                .foregroundStyle(baseColor.opacity(isHighlighted ? 0.12 : 0.03))
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Energy", item.count),
                    series: .value("App", item.appName)
                )
                .foregroundStyle(baseColor.opacity(isHighlighted ? 0.9 : 0.2))
                .lineStyle(StrokeStyle(lineWidth: isHighlighted ? 2 : 1))
                .interpolationMethod(.catmullRom)
                
                if isHighlighted {
                    PointMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Energy", item.count)
                    )
                    .foregroundStyle(baseColor)
                    .symbolSize(20)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: chartRange == .month ? .weekOfYear : .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisValueLabel {
                            Text(dateLabelFormatter.string(from: date))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 160)
        }
    }
    
    // MARK: - App Usage Section
    private var appUsageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc(appLanguage, "Apps", "Приложения"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !trackedAppsToday.isEmpty {
                    Text("\(trackedAppsToday.count)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.gray.opacity(0.12))
                        )
                }
            }
            
            if trackedAppsToday.isEmpty {
                VStack(spacing: 10) {
                        Image(systemName: "apps.iphone")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(loc(appLanguage, "No usage yet", "Нет использования"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(trackedAppsToday.enumerated()), id: \.element.id) { index, item in
                    appUsageRow(item: item)
                        
                        if index < trackedAppsToday.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    @ViewBuilder
    private func appUsageRow(item: AppUsageToday) -> some View {
        let isSelected = selectedBundleForChart == item.bundleId
        let timeAccessEnabled = model.isTimeAccessEnabled(for: item.bundleId)
        let minutesText = timeAccessEnabled ? formatMinutes(model.minuteTimeToday(for: item.bundleId)) : "—"
        let appColor = colorForBundle(item.bundleId)
        
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // App icon with glow
                ZStack {
                    // Subtle glow
                    Circle()
                        .fill(appColor.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .blur(radius: 8)
                    
                    appIconImage(item.imageName)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(formatNumber(item.steps))")
                            .font(.subheadline.bold())
                            .foregroundColor(appColor)
                    }
                    
                    // Energy bar - glass style
                    GeometryReader { geo in
                        let maxSteps = trackedAppsToday.map { $0.steps }.max() ?? 1
                        let ratio = Double(item.steps) / Double(max(1, maxSteps))
                        let width = geo.size.width * ratio
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [appColor, appColor.opacity(0.5)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, width), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    HStack {
                        Text(minutesText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                
                Spacer()
                
                        // Only show chevron in week/month mode
                        if chartRange != .today {
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.6))
            }
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                // Only allow expand in week/month mode
                guard chartRange != .today else { return }
                
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isSelected {
                        selectedBundleForChart = nil
                        detailBundle = nil
                    } else {
                        selectedBundleForChart = item.bundleId
                        detailBundle = item.bundleId
                    }
                }
            }
            
            // Expanded detail (only in week/month mode)
            if chartRange != .today && detailBundle == item.bundleId {
                detailEntriesView(bundleId: item.bundleId)
                    .padding(.leading, 52)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let mins = clamped % 60
        if hours > 0 {
            return loc(appLanguage, "\(hours)h \(mins)m", "\(hours)ч \(mins)м")
        }
        return loc(appLanguage, "\(mins) min", "\(mins) мин")
    }

    private var showConnectCTA: Bool {
        let defaults = UserDefaults.stepsTrader()
        let configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        let single = defaults.string(forKey: "automationBundleId")
        let pending = defaults.array(forKey: "automationPendingBundles") as? [String] ?? []
        return configured.isEmpty && single == nil && pending.isEmpty
    }

    private var connectFirstModuleCTA: some View {
        VStack(spacing: 24) {
            // Icon with glow effect
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                    LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.blue.opacity(0.2), radius: 20, x: 0, y: 10)
                
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(accentGradient)
            }
            
            VStack(spacing: 8) {
                Text(loc(appLanguage, "No shields yet", "Нет щитов"))
                .font(.title3.bold())
            
                Text(loc(appLanguage, "Connect your first shield to track app usage", "Подключите щит для отслеживания приложений"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            
            Button {
                NotificationCenter.default.post(name: openModulesNotification, object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.subheadline.bold())
                    Text(loc(appLanguage, "Connect Shield", "Подключить щит"))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentGradient)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .background(glassCard)
        .padding(.top, 60)
    }

    // MARK: - Chart Data
    private struct DailyOpen: Identifiable {
        let id = UUID()
        let day: Date
        let bundleId: String
        let count: Int
        let appName: String
    }
    
    private var bundleIdsForChart: [String] {
        var totals: [String: Int] = [:]
        for day in daysInRange {
            let key = AppModel.dayKey(for: day)
            for (bid, steps) in model.appStepsSpentByDay[key] ?? [:] {
                let canonical = normalizeBundleId(bid)
                totals[canonical, default: 0] += steps
            }
        }
        if let selected = selectedBundleForChart {
            totals[selected, default: 0] += 0
        }
        return totals
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
    
    private var dailyOpenData: [DailyOpen] {
        let cal = Calendar.current
        let days = (0..<chartRange.days).compactMap { offset -> Date? in
            guard let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { return nil }
            return d
        }.reversed()
        
        var result: [DailyOpen] = []
        for bundle in bundleIdsForChart {
            for day in days {
                let key = AppModel.dayKey(for: day)
                let stepsSpent = model.appStepsSpentByDay[key]?[bundle] ?? 0
                result.append(DailyOpen(day: day, bundleId: bundle, count: stepsSpent, appName: appDisplayName(bundle)))
            }
        }
        return result
    }
    
    private func appDisplayName(_ bundleId: String) -> String {
        TargetResolver.displayName(for: bundleId)
    }
    
    private func colorForBundle(_ bundleId: String) -> Color {
        switch bundleId {
        case "com.burbn.instagram": return .pink
        case "com.zhiliaoapp.musically": return .red
        case "com.google.ios.youtube": return Color(red: 1, green: 0, blue: 0)
        case "com.facebook.Facebook": return .blue
        case "com.linkedin.LinkedIn": return Color(red: 0, green: 0.47, blue: 0.71)
        case "com.atebits.Tweetie2": return .primary
        case "com.toyopagroup.picaboo": return .yellow
        case "net.whatsapp.WhatsApp": return .green
        case "ph.telegra.Telegraph": return .cyan
        case "com.duolingo.DuolingoMobile": return Color(red: 0.35, green: 0.8, blue: 0.2)
        case "com.pinterest": return .red
        case "com.reddit.Reddit": return .orange
        default: return .purple
        }
    }
    
    private var dateLabelFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = chartRange == .month ? "d/M" : "E"
        return df
    }

    private struct AppUsageToday: Identifiable {
        let id = UUID()
        let bundleId: String
        let name: String
        let imageName: String?
        let opens: Int
        let steps: Int
    }
    
    private var daysInRange: [Date] {
        (0..<chartRange.days).compactMap { offset -> Date? in
            dateByAddingDays(to: currentDayStart, value: -offset)
        }
    }

    private func stepsSpentFor(bundleId: String) -> Int {
        let keys = daysInRange.map { AppModel.dayKey(for: $0) }
        return keys.reduce(0) { acc, key in
            acc + (model.appStepsSpentByDay[key]?[bundleId] ?? 0)
        }
    }

    private var trackedAppsToday: [AppUsageToday] {
        let cutoff = dateByAddingDays(to: currentDayStart, value: -(chartRange.days - 1))
        var opensDict: [String: Int] = [:]
        for log in model.appOpenLogs where log.date >= cutoff {
            let canonical = normalizeBundleId(log.bundleId)
            opensDict[canonical, default: 0] += 1
        }

        let baseIds: [String]
        if chartRange == .today {
            let todayKey = AppModel.dayKey(for: currentDayStart)
            let spentTodayKeys = model.appStepsSpentByDay[todayKey]?.keys.map { normalizeBundleId($0) } ?? []
            baseIds = Set(model.appOpenLogs.map { normalizeBundleId($0.bundleId) })
                .union(spentTodayKeys)
                .union(bundleIdsForChart)
                .sorted()
        } else {
            baseIds = bundleIdsForChart
        }

        return baseIds.map { bundle in
            AppUsageToday(
                bundleId: bundle,
                name: appDisplayName(bundle),
                imageName: appImageName(bundle),
                opens: opensDict[bundle, default: 0],
                steps: stepsSpentFor(bundleId: bundle)
            )
        }
        .sorted { $0.steps > $1.steps }
    }
    
    private func appImageName(_ bundleId: String) -> String? {
        switch bundleId {
        case "com.burbn.instagram": return "instagram"
        case "com.zhiliaoapp.musically": return "tiktok"
        case "com.google.ios.youtube": return "youtube"
        case "com.facebook.Facebook": return "facebook"
        case "com.linkedin.LinkedIn": return "linkedin"
        case "com.atebits.Tweetie2": return "x"
        case "com.toyopagroup.picaboo": return "snapchat"
        case "net.whatsapp.WhatsApp": return "whatsapp"
        case "ph.telegra.Telegraph": return "telegram"
        case "com.duolingo.DuolingoMobile": return "duolingo"
        case "com.pinterest": return "pinterest"
        case "com.reddit.Reddit": return "reddit"
        default: return nil
        }
    }
    
    private func normalizeBundleId(_ bundleId: String) -> String {
        let lower = bundleId.lowercased()
        switch lower {
        case "instagram": return "com.burbn.instagram"
        case "tiktok": return "com.zhiliaoapp.musically"
        case "youtube": return "com.google.ios.youtube"
        case "telegram": return "ph.telegra.Telegraph"
        case "whatsapp": return "net.whatsapp.WhatsApp"
        case "snapchat": return "com.toyopagroup.picaboo"
        case "facebook": return "com.facebook.Facebook"
        case "linkedin": return "com.linkedin.LinkedIn"
        case "x", "twitter": return "com.atebits.Tweetie2"
        case "reddit": return "com.reddit.Reddit"
        case "pinterest": return "com.pinterest"
        case "duolingo": return "com.duolingo.DuolingoMobile"
        default: return bundleId
        }
    }
    
    @ViewBuilder
    private func appIconImage(_ imageName: String?) -> some View {
        if let imageName,
           let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: "app.fill")
                        .foregroundColor(.secondary)
                )
        }
    }
    
    @ViewBuilder
    private func detailEntriesView(bundleId: String) -> some View {
        let days = daysInRange.reversed()
        let entries = days.map { day -> (Date, Int) in
            let stepsSpent = model.appStepsSpentByDay[AppModel.dayKey(for: day)]?[bundleId] ?? 0
            return (day, stepsSpent)
        }.filter { $0.1 > 0 }
        
        if entries.isEmpty {
            Text(loc(appLanguage, "No usage in this period", "Нет использования за этот период"))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries.prefix(7), id: \.0) { entry in
                    HStack {
                        Text(detailDateFormatter.string(from: entry.0))
                            .font(.caption)
                        Spacer()
                        Text("\(entry.1) \(loc(appLanguage, "energy", "энергии"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var detailDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "E, d MMM"
        df.locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        return df
    }
    
    private func formatNumber(_ num: Int) -> String {
        let absValue = abs(num)
        let sign = num < 0 ? "-" : ""
        
        func trimTrailingZero(_ s: String) -> String {
            s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        
        if absValue < 1000 { return "\(num)" }
        
        if absValue < 10_000 {
            let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "K"
        }
        
        if absValue < 1_000_000 {
            let v = Int((Double(absValue) / 1000.0).rounded())
            return sign + "\(v)K"
        }
        
        if absValue < 10_000_000 {
            let v = (Double(absValue) / 1_000_000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "M"
        }
        
        let v = Int((Double(absValue) / 1_000_000.0).rounded())
        return sign + "\(v)M"
    }

    // MARK: - Day boundary helpers
    private var currentDayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private func dateByAddingDays(to date: Date, value: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: value, to: date) ?? date
    }

    // MARK: - Timer Management
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                model.reloadBudgetFromStorage()
                model.loadSpentTime()
            }

            if calculatedRemainingMinutes > 0 {
                lastAvailableMinutes = calculatedRemainingMinutes
            }

            sendRemainingTimeNotificationIfNeeded()
            checkTimeExpiration()
        }
    }

    private var calculatedRemainingMinutes: Int {
        max(0, model.dailyBudgetMinutes - model.spentMinutes)
    }

    private func checkTimeExpiration() {
        if model.isTrackingTime && calculatedRemainingMinutes <= 0 && !model.isBlocked {
            let minutesBeforeBlocking = lastAvailableMinutes > 0 ? lastAvailableMinutes : 0

            model.stopTracking()
            model.isBlocked = true
            model.message = "⏰ Time is up!"

            model.notificationService.sendTimeExpiredNotification(remainingMinutes: minutesBeforeBlocking)
            model.sendReturnToAppNotification()
            AudioServicesPlaySystemSound(1005)
        }

        if model.isBlocked && calculatedRemainingMinutes > 0 {
            unblockApp()
        }
    }

    private func unblockApp() {
        model.isBlocked = false
        model.message = "✅ Time restored! Available: \(calculatedRemainingMinutes) min"

        model.notificationService.sendUnblockNotification(remainingMinutes: calculatedRemainingMinutes)
        AudioServicesPlaySystemSound(1003)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func sendRemainingTimeNotificationIfNeeded() {
        if calculatedRemainingMinutes > 0 && calculatedRemainingMinutes < 10
            && calculatedRemainingMinutes != lastNotificationMinutes
        {
            model.notificationService.sendRemainingTimeNotification(remainingMinutes: calculatedRemainingMinutes)
            lastNotificationMinutes = calculatedRemainingMinutes
        }
    }

    private func onAppear() {
        if model.isTrackingTime {
            startTimer()
        }
    }

    private func onDisappear() {
        stopTimer()
    }
}
