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
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    private let openModulesNotification = Notification.Name("com.steps.trader.open.modules")
    
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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Daily Summary Card
                    if !showConnectCTA {
                        dailySummaryCard
                    }
                    
                    // Quick Stats Row
                    if !showConnectCTA {
                        quickStatsRow
                    }
                    
                    // Connect CTA or Activity Section
                    if showConnectCTA {
                        connectFirstModuleCTA
                    } else {
                        // Activity Chart
                        activityChartSection
                        
                        // App Usage List
                        appUsageSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .background(Color.clear)
        .scrollContentBackground(.hidden)
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
    
    // MARK: - Daily Summary Card
    private var dailySummaryCard: some View {
        VStack(spacing: 16) {
            // Greeting
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.title2.bold())
                    Text(motivationalText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Daily streak badge
                if model.appUnlockSettings.count > 0 {
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("\(model.appUnlockSettings.count)")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .background(
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                    )
                }
            }
            
            // Progress Ring
            HStack(spacing: 24) {
                // Energy efficiency
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: energyEfficiency)
                            .stroke(
                                LinearGradient(
                                    colors: [.green, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text("\(Int(energyEfficiency * 100))%")
                                .font(.title3.bold())
                            Text(loc(appLanguage, "saved", "сохранено"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 80, height: 80)
                    
                    Text(loc(appLanguage, "Energy", "Энергия"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Divider
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 60)
                
                // Steps today
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatNumber(Int(model.effectiveStepsToday)))
                            .font(.title.bold())
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text(loc(appLanguage, "steps", "шагов"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(model.spentStepsToday) \(loc(appLanguage, "spent", "потрачено"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(model.totalStepsBalance) \(loc(appLanguage, "available", "доступно"))")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return loc(appLanguage, "Good morning! 🌅", "Доброе утро! 🌅")
        } else if hour < 17 {
            return loc(appLanguage, "Good afternoon! ☀️", "Добрый день! ☀️")
        } else {
            return loc(appLanguage, "Good evening! 🌙", "Добрый вечер! 🌙")
        }
    }
    
    private var motivationalText: String {
        let steps = Int(model.effectiveStepsToday)
        if steps < 1000 {
            return loc(appLanguage, "Let's get moving!", "Пора двигаться!")
        } else if steps < 5000 {
            return loc(appLanguage, "Good start, keep it up!", "Хорошее начало!")
        } else if steps < 10000 {
            return loc(appLanguage, "You're doing great!", "Отличная работа!")
        } else {
            return loc(appLanguage, "Amazing progress! 🏆", "Потрясающий результат! 🏆")
        }
    }
    
    private var energyEfficiency: Double {
        let total = model.effectiveStepsToday
        let spent = Double(model.spentStepsToday)
        guard total > 0 else { return 1.0 }
        return max(0, min(1, (total - spent) / total))
    }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            quickStatCard(
                icon: "shield.checkered",
                value: "\(model.appUnlockSettings.count)",
                label: loc(appLanguage, "Shields", "Щитов"),
                color: .blue
            )
            
            quickStatCard(
                icon: "bolt.fill",
                value: formatNumber(model.spentStepsToday),
                label: loc(appLanguage, "Spent", "Потрачено"),
                color: .orange
            )
            
            quickStatCard(
                icon: "clock.fill",
                value: timeUntilReset,
                label: loc(appLanguage, "Reset in", "Сброс через"),
                color: .purple
            )
        }
    }
    
    @ViewBuilder
    private func quickStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline.bold())
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.1))
        )
    }
    
    private var timeUntilReset: String {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 0
        
        guard let todayMidnight = calendar.date(from: components),
              let tomorrowMidnight = calendar.date(byAdding: .day, value: 1, to: todayMidnight) else {
            return "--:--"
        }
        
        let diff = tomorrowMidnight.timeIntervalSince(now)
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        
        return String(format: "%dh %dm", hours, minutes)
    }
    
    // MARK: - Activity Chart Section
    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(loc(appLanguage, "Activity Log", "Активность"))
                    .font(.headline)
                Spacer()
                
                // Range picker
                HStack(spacing: 0) {
                    ForEach([ChartRange.today, .week, .month], id: \.self) { range in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                chartRange = range
                            }
                        } label: {
                            Text(rangeLabel(range))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(chartRange == range ? Color.blue : Color.clear)
                                )
                                .foregroundColor(chartRange == range ? .white : .secondary)
                        }
                    }
                }
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func rangeLabel(_ range: ChartRange) -> String {
        switch range {
        case .today: return loc(appLanguage, "Today", "Сегодня")
        case .week: return loc(appLanguage, "Week", "Неделя")
        case .month: return loc(appLanguage, "Month", "Месяц")
        }
    }
    
    private var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
            Text(loc(appLanguage, "No activity yet", "Пока нет активности"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(loc(appLanguage, "Use your shields to see stats here", "Используйте щиты, чтобы увидеть статистику"))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func chartView(data: [DailyOpen]) -> some View {
        if chartRange == .today {
            let todayData = trackedAppsToday.sorted { $0.steps > $1.steps }
            if todayData.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(todayData) { item in
                    BarMark(
                        x: .value("App", item.name),
                        y: .value("Energy", item.steps)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colorForBundle(item.bundleId), colorForBundle(item.bundleId).opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(values: todayData.map { $0.name }) { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
            }
        } else {
            let dateValues = Array(Set(data.map { Calendar.current.startOfDay(for: $0.day) })).sorted()
            Chart(data) { item in
                let isHighlighted = (selectedBundleForChart == nil) || (selectedBundleForChart == item.bundleId)
                let baseColor = colorForBundle(item.bundleId)
                
                AreaMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Energy", item.count),
                    series: .value("App", item.appName)
                )
                .foregroundStyle(baseColor.opacity(isHighlighted ? 0.15 : 0.05))
                
                LineMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Energy", item.count),
                    series: .value("App", item.appName)
                )
                .foregroundStyle(baseColor.opacity(isHighlighted ? 1.0 : 0.25))
                .lineStyle(StrokeStyle(lineWidth: isHighlighted ? 2.5 : 1))
                
                if isHighlighted {
                    PointMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Energy", item.count)
                    )
                    .foregroundStyle(baseColor)
                    .symbolSize(30)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: chartRange == .month ? .weekOfYear : .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        AxisValueLabel {
                            Text(dateLabelFormatter.string(from: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    AxisValueLabel()
                }
            }
            .frame(height: 200)
        }
    }
    
    // MARK: - App Usage Section
    private var appUsageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc(appLanguage, "App Usage", "Использование"))
                    .font(.headline)
                Spacer()
                if !trackedAppsToday.isEmpty {
                    Text("\(trackedAppsToday.count) \(loc(appLanguage, "apps", "приложений"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if trackedAppsToday.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "apps.iphone")
                            .font(.title)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(loc(appLanguage, "No usage recorded", "Нет записей"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                ForEach(trackedAppsToday) { item in
                    appUsageRow(item: item)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
    
    @ViewBuilder
    private func appUsageRow(item: AppUsageToday) -> some View {
        let isSelected = selectedBundleForChart == item.bundleId
        
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // App icon
                ZStack {
                    appIconImage(item.imageName)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    // Color indicator
                    Circle()
                        .fill(colorForBundle(item.bundleId))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                        .offset(x: 16, y: 16)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                    
                    // Energy bar
                    GeometryReader { geo in
                        let maxSteps = trackedAppsToday.map { $0.steps }.max() ?? 1
                        let width = geo.size.width * (Double(item.steps) / Double(max(1, maxSteps)))
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [colorForBundle(item.bundleId), colorForBundle(item.bundleId).opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, width), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                
                Spacer()
                
                // Energy spent
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.steps)")
                        .font(.subheadline.bold())
                        .foregroundColor(colorForBundle(item.bundleId))
                    Text(loc(appLanguage, "energy", "энергии"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSelected {
                        selectedBundleForChart = nil
                        detailBundle = nil
                    } else {
                        selectedBundleForChart = item.bundleId
                        detailBundle = item.bundleId
                    }
                }
            }
            
            // Expanded detail
            if detailBundle == item.bundleId {
                detailEntriesView(bundleId: item.bundleId)
                    .padding(.leading, 56)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Divider()
        }
    }

    private var showConnectCTA: Bool {
        let defaults = UserDefaults.stepsTrader()
        let configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        let single = defaults.string(forKey: "automationBundleId")
        let pending = defaults.array(forKey: "automationPendingBundles") as? [String] ?? []
        return configured.isEmpty && single == nil && pending.isEmpty
    }

    private var connectFirstModuleCTA: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(loc(appLanguage, "No shields connected", "Нет подключенных щитов"))
                .font(.title3.bold())
            
            Text(loc(appLanguage, "Connect your first shield to start tracking your app usage and control screen time.", "Подключите первый щит, чтобы отслеживать использование приложений и контролировать экранное время."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                NotificationCenter.default.post(name: openModulesNotification, object: nil)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(loc(appLanguage, "Connect Shield", "Подключить щит"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .padding(.top, 40)
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
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

            if let familyService = model.familyControlsService as? FamilyControlsService {
                familyService.enableShield()
            }

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

        if let familyService = model.familyControlsService as? FamilyControlsService {
            familyService.disableShield()
        }

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
