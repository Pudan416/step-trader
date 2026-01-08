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
        
        var title: String {
            switch self {
            case .today: return "Today"
            case .week: return "7 days"
            case .month: return "30 days"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if showConnectCTA {
                    connectFirstModuleCTA
                } else {
                    openFrequencyChart
                }
                ScrollView {
                    trackedAppsTodayList
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
            }
            .padding(.top)
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

    private var showConnectCTA: Bool {
        let defaults = UserDefaults.stepsTrader()
        let configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        let single = defaults.string(forKey: "automationBundleId")
        let pending = defaults.array(forKey: "automationPendingBundles") as? [String] ?? []
        return configured.isEmpty && single == nil && pending.isEmpty
    }

    private var connectFirstModuleCTA: some View {
        VStack(spacing: 12) {
            Text(loc(appLanguage, "No modules connected yet", "Модули еще не подключены"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(loc(appLanguage, "Connect your first module to start tracking jumps to social media.", "Подключите первый модуль, чтобы начать отслеживание погруженияв соцсети."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                NotificationCenter.default.post(name: openModulesNotification, object: nil)
            } label: {
                Text(loc(appLanguage, "Connect your first module", "Подключить первый модуль"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.88, green: 0.38, blue: 0.72),
                                Color.black
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.1)))
        .padding(.horizontal)
    }

    private var calculatedRemainingMinutes: Int {
        max(0, model.dailyBudgetMinutes - model.spentMinutes)
    }

    private var timeColor: Color {
        if calculatedRemainingMinutes <= 0 {
            return .red
        } else if calculatedRemainingMinutes < 10 {
            return .red
        } else if calculatedRemainingMinutes <= 30 {
            return .orange
        } else {
            return .blue
        }
    }

    private var timeBackgroundColor: Color {
        if model.isBlocked {
            return .red.opacity(0.1)
        } else {
            return timeColor.opacity(0.1)
        }
    }

    private var progressValue: Double {
        guard model.dailyBudgetMinutes > 0 else { return 0 }
        let used = model.dailyBudgetMinutes - model.remainingMinutes
        return Double(used) / Double(model.dailyBudgetMinutes)
    }

    private var progressPercentage: Int {
        Int(progressValue * 100)
    }

    // MARK: - Opens frequency chart
    private struct DailyOpen: Identifiable {
        let id = UUID()
        let day: Date
        let bundleId: String
        let count: Int
        let appName: String
    }
    
    private var recentOpenLogs: [AppModel.AppOpenLog] {
        let days = chartRange.days
        let cutoff = dateByAddingDays(to: currentDayStart, value: -(days - 1))
        return model.appOpenLogs.filter { $0.date >= cutoff }
    }
    
    private var bundleIdsForChart: [String] {
        var totals: [String: Int] = [:]
        for log in recentOpenLogs {
            let canonical = normalizeBundleId(log.bundleId)
            totals[canonical, default: 0] += 1
        }
        // include any app that has spent steps today (even if no opens in range)
        for (bid, _) in model.appStepsSpentToday {
            let canonical = normalizeBundleId(bid)
            totals[canonical, default: 0] += 0
        }
        if let selected = selectedBundleForChart {
            totals[selected, default: 0] += 0
        }
        return totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map { $0.key }
    }
    
    private var dailyOpenData: [DailyOpen] {
        let cal = Calendar.current
        var grouped: [String: [Date: Int]] = [:]
        for log in recentOpenLogs {
            let day = cal.startOfDay(for: log.date)
            let canonical = normalizeBundleId(log.bundleId)
            grouped[canonical, default: [:]][day, default: 0] += 1
        }
        let days = (0..<chartRange.days).compactMap { offset -> Date? in
            guard let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { return nil }
            return d
        }.reversed()
        
        var result: [DailyOpen] = []
        for bundle in bundleIdsForChart {
            for day in days {
                let count = grouped[bundle]?[day] ?? 0
                result.append(DailyOpen(day: day, bundleId: bundle, count: count, appName: appDisplayName(bundle)))
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
        case "com.google.ios.youtube": return .red.opacity(0.8)
        case "com.facebook.Facebook": return .blue
        case "com.linkedin.LinkedIn": return .blue.opacity(0.6)
        case "com.atebits.Tweetie2": return .gray
        case "com.toyopagroup.picaboo": return .yellow
        case "net.whatsapp.WhatsApp": return .green
        case "ph.telegra.Telegraph": return .cyan
        case "com.duolingo.DuolingoMobile": return .green.opacity(0.7)
        case "com.pinterest": return .red
        case "com.reddit.Reddit": return .orange
        case "__placeholder": return .clear
        default: return .purple
        }
    }
    
    private var openFrequencyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc(appLanguage, "Stats for...", "Статистика за...") + " ")
                .font(.headline)
                Spacer()
                Picker("", selection: $chartRange) {
                    Text(loc(appLanguage, "Today", "Сегодня")).tag(ChartRange.today)
                    Text(loc(appLanguage, "7 days", "7 дней")).tag(ChartRange.week)
                    Text(loc(appLanguage, "30 days", "30 дней")).tag(ChartRange.month)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            
            let chartData = dailyOpenData
            if chartData.isEmpty {
                Text(loc(appLanguage, "No opens yet.", "Нет открытий"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                if chartRange == .today {
                    let todayData = trackedAppsToday
                    Chart(todayData) { item in
                        BarMark(
                            x: .value("App", item.name),
                            y: .value("Jumps", item.opens)
                        )
                        .foregroundStyle(colorForBundle(item.bundleId))
                    }
                    .chartXAxis {
                        AxisMarks(values: todayData.map { $0.name }) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .chartYAxis { AxisMarks() }
                    .frame(height: 220)
                } else {
                    let dateValues = Array(Set(chartData.map { Calendar.current.startOfDay(for: $0.day) })).sorted()
                    Chart(chartData) { item in
                        let isHighlighted = (selectedBundleForChart == nil) || (selectedBundleForChart == item.bundleId)
                        let baseColor = colorForBundle(item.bundleId)
                        let lineColor = baseColor.opacity(isHighlighted ? 1.0 : 0.25)
                        
                        LineMark(
                            x: .value("Day", item.day, unit: .day),
                            y: .value("Jumps", item.count),
                            series: .value("App", item.appName)
                        )
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: isHighlighted ? 3 : 1.5))
                        .symbol(Circle())
                        PointMark(
                            x: .value("Day", item.day, unit: .day),
                            y: .value("Jumps", item.count)
                        )
                        .foregroundStyle(lineColor)
                    }
                    .chartXAxis {
                        if chartRange == .month {
                            AxisMarks(values: dateValues.filter { Calendar.current.component(.day, from: $0) == 1 || $0 == dateValues.first }) { value in
                                if let date = value.as(Date.self) {
                                    AxisGridLine()
                                    AxisValueLabel {
                                        Text(dateMonthFormatter.string(from: date))
                                    }
                                }
                            }
                        } else {
                            AxisMarks(values: .stride(by: .day)) { value in
                                if let date = value.as(Date.self) {
                                    AxisGridLine()
                                    AxisValueLabel {
                                        Text(dateLabelFormatter.string(from: date))
                                    }
                                }
                            }
                        }
                    }
                    .chartYAxis { AxisMarks() }
                    .frame(height: 220)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
    
    private var dateLabelFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        return df
    }
    
    private var dateMonthFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "dd/MM"
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
    
    private var trackedAppsToday: [AppUsageToday] {
        let cutoff = dateByAddingDays(to: currentDayStart, value: -(chartRange.days - 1))
        var opensDict: [String: Int] = [:]
        for log in model.appOpenLogs where log.date >= cutoff {
            let canonical = normalizeBundleId(log.bundleId)
            opensDict[canonical, default: 0] += 1
        }

        // Для Today включаем все приложения с подключенными модулями
        let baseIds: [String]
        if chartRange == .today {
            baseIds = Set(model.appOpenLogs.map { normalizeBundleId($0.bundleId) })
                .union(model.appStepsSpentToday.keys.map { normalizeBundleId($0) })
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
                steps: model.appStepsSpentToday[bundle, default: 0]
            )
        }
        .sorted {
            if $0.opens == $1.opens { return $0.name < $1.name }
            return $0.opens > $1.opens
        }
    }
    
    @ViewBuilder
    private var trackedAppsTodayList: some View {
        if trackedAppsToday.isEmpty {
            Text(loc(appLanguage, "No tracked opens today.", "Сегодня открытий нет."))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(trackedAppsToday) { item in
                    let isSelected = selectedBundleForChart == item.bundleId
                    HStack(spacing: 10) {
                        Circle()
                            .fill(colorForBundle(item.bundleId))
                            .frame(width: 10, height: 10)
                        appIconImage(item.imageName)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.subheadline)
                            Text(loc(appLanguage, "Jumps", "Прыжки") + ": \(item.opens) • " + loc(appLanguage, "Fuel spent", "Потрачено топлива") + ": \(item.steps)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelected {
                            selectedBundleForChart = nil
                        } else {
                            selectedBundleForChart = item.bundleId
                        }
                        if detailBundle == item.bundleId {
                            detailBundle = nil
                        } else {
                            detailBundle = item.bundleId
                        }
                    }
                    .opacity(isSelected ? 1.0 : 0.85)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? colorForBundle(item.bundleId) : Color.clear, lineWidth: 1)
                    )
                    
                    if detailBundle == item.bundleId {
                        detailEntriesView(bundleId: item.bundleId)
                            .padding(.leading, 18)
                    }
                }
            }
        }
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: "questionmark")
                        .foregroundColor(.secondary)
                )
        }
    }
    
    @ViewBuilder
    private func detailEntriesView(bundleId: String) -> some View {
        let cal = Calendar.current
        let days = (0..<chartRange.days).compactMap { offset -> Date? in
            dateByAddingDays(to: currentDayStart, value: -offset)
        }.reversed()
        let entries = days.map { day -> (Date, Int, Int) in
            let count = model.appOpenLogs.filter { normalizeBundleId($0.bundleId) == bundleId && cal.isDate($0.date, inSameDayAs: day) }.count
            let stepsSpent = cal.isDateInToday(day) ? model.appStepsSpentToday[bundleId, default: 0] : 0
            return (day, count, stepsSpent)
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries, id: \.0) { entry in
                HStack {
                    Text(dateLabelFormatter.string(from: entry.0))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(loc(appLanguage, "Jumps", "Прыжки") + ": \(entry.1)")
                        Text(loc(appLanguage, "Fuel spent", "Потрачено топлива") + ": \(entry.2)")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                Divider()
            }
        }
    }

    // MARK: - Day boundary helpers
    private var currentDayStart: Date {
        dayStart(for: Date())
    }
    
    private func dayStart(for date: Date) -> Date {
        let cal = Calendar.current
        guard let cutoffToday = cal.date(bySettingHour: dayEndHour, minute: dayEndMinute, second: 0, of: date) else {
            return cal.startOfDay(for: date)
        }
        if date >= cutoffToday {
            return cutoffToday
        } else if let prev = cal.date(byAdding: .day, value: -1, to: cutoffToday) {
            return prev
        } else {
            return cal.startOfDay(for: date)
        }
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

    private func checkTimeExpiration() {
        if model.isTrackingTime && calculatedRemainingMinutes <= 0 && !model.isBlocked {
            print("⏰ Time expired in StatusView - triggering blocking")

            let minutesBeforeBlocking = lastAvailableMinutes > 0 ? lastAvailableMinutes : 0

            model.stopTracking()
            model.isBlocked = true
            model.message = "⏰ Time is up!"

            if let familyService = model.familyControlsService as? FamilyControlsService {
                familyService.enableShield()
                print("🛡️ Applied real app blocking via ManagedSettings")
            }

            model.notificationService.sendTimeExpiredNotification(
                remainingMinutes: minutesBeforeBlocking)
            model.sendReturnToAppNotification()
            AudioServicesPlaySystemSound(1005)
        }

        if model.isBlocked && calculatedRemainingMinutes > 0 {
            print("🔄 New time available after blocking - unblocking app")
            unblockApp()
        }
    }

    private func unblockApp() {
        model.isBlocked = false
        model.message = "✅ Time restored! Available: \(calculatedRemainingMinutes) min"

        if let familyService = model.familyControlsService as? FamilyControlsService {
            familyService.disableShield()
            print("🔓 Removed app blocking via ManagedSettings")
        }

        model.notificationService.sendUnblockNotification(
            remainingMinutes: calculatedRemainingMinutes)
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
            model.notificationService.sendRemainingTimeNotification(
                remainingMinutes: calculatedRemainingMinutes)
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
