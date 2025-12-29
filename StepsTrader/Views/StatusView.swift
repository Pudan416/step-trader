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
    @State private var chartRange: ChartRange = .week
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    private enum ChartRange: String, CaseIterable {
        case week
        case month
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
        
        var title: String {
            switch self {
            case .week: return "7"
            case .month: return "30"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                openFrequencyChart
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return model.appOpenLogs.filter { $0.date >= cutoff }
    }
    
    private var bundleIdsForChart: [String] {
        var set = Set(recentOpenLogs.map { normalizeBundleId($0.bundleId) })
        if let selected = selectedBundleForChart { set.insert(selected) }
        return Array(set).sorted()
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
        switch bundleId {
        case "com.burbn.instagram": return "Instagram"
        case "com.zhiliaoapp.musically": return "TikTok"
        case "com.google.ios.youtube": return "YouTube"
        case "com.facebook.Facebook": return "Facebook"
        case "com.linkedin.LinkedIn": return "LinkedIn"
        case "com.atebits.Tweetie2": return "X"
        case "com.toyopagroup.picaboo": return "Snapchat"
        case "net.whatsapp.WhatsApp": return "WhatsApp"
        case "ph.telegra.Telegraph": return "Telegram"
        case "com.duolingo.DuolingoMobile": return "Duolingo"
        case "com.pinterest": return "Pinterest"
        case "com.reddit.Reddit": return "Reddit"
        default: return bundleId
        }
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
                Text(chartRange == .week
                     ? loc(appLanguage, "Opens last 7 days", "Открытия за 7 дней")
                     : loc(appLanguage, "Opens last 30 days", "Открытия за 30 дней"))
                .font(.headline)
                Spacer()
                Picker("", selection: $chartRange) {
                    Text("7d").tag(ChartRange.week)
                    Text("30d").tag(ChartRange.month)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            
            let chartData = dailyOpenData
            if chartData.isEmpty {
                Text(loc(appLanguage, "No opens yet.", "Нет открытий"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let dateValues = Array(Set(chartData.map { Calendar.current.startOfDay(for: $0.day) })).sorted()
                Chart(chartData) { item in
                    let isHighlighted = (selectedBundleForChart == nil) || (selectedBundleForChart == item.bundleId)
                    let baseColor = colorForBundle(item.bundleId)
                    let lineColor = baseColor.opacity(isHighlighted ? 1.0 : 0.25)
                    
                    LineMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Opens", item.count),
                        series: .value("App", item.appName)
                    )
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: isHighlighted ? 3 : 1.5))
                    .symbol(Circle())
                    PointMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Opens", item.count)
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
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
    
    private var dateLabelFormatter: DateFormatter {
        let df = DateFormatter()
        if chartRange == .week {
            df.dateFormat = "E"
        } else {
            df.dateFormat = "d MMM"
        }
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
        let today = Calendar.current.startOfDay(for: Date())
        var opensDict: [String: Int] = [:]
        for log in model.appOpenLogs where Calendar.current.isDate(log.date, inSameDayAs: today) {
            let canonical = normalizeBundleId(log.bundleId)
            opensDict[canonical, default: 0] += 1
        }
        let spentDict = model.appStepsSpentToday
        let bundleIds = Set(opensDict.keys).union(spentDict.keys.map { normalizeBundleId($0) })
        let usages = bundleIds.map { bundle -> AppUsageToday in
            AppUsageToday(
                bundleId: bundle,
                name: appDisplayName(bundle),
                imageName: appImageName(bundle),
                opens: opensDict[bundle, default: 0],
                steps: spentDict[bundle, default: 0]
            )
        }
        return usages.sorted { $0.opens > $1.opens }
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
                            Text(loc(appLanguage, "Opens today", "Открытий сегодня") + ": \(item.opens) • " + loc(appLanguage, "Steps spent", "Шагов потрачено") + ": \(item.steps)")
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
                    }
                    .opacity(isSelected ? 1.0 : 0.85)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? colorForBundle(item.bundleId) : Color.clear, lineWidth: 1)
                    )
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

    // MARK: - Timer Management
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                model.reloadBudgetFromStorage()
            }

            Task { @MainActor in
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
