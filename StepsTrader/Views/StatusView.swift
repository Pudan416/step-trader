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
    
    private struct DayDetailItem: Identifiable {
        let id = UUID()
        let date: Date
    }
    
    @State private var selectedDayForDetail: DayDetailItem? = nil
    
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
                // Background
                backgroundGradient
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Today's App Usage Chart (shows energy spent on shields today)
                        todayAppUsageChartSection
                        
                        // 7-Day Calendar (at the bottom)
                        sevenDayCalendarSection
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
    
    // MARK: - Hero Card (Stats)
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc(appLanguage, "Your Progress"))
                        .font(.title3.weight(.bold))
                    Text(loc(appLanguage, "Tap to see details"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Stats grid - improved layout
            HStack(spacing: 12) {
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
            
            // Explanation text with animation
            if let stat = showStatExplanation {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(explanationText(for: stat))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.08))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background(glassCard)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showStatExplanation)
    }
    
    private var batteriesCollectedTotal: Int {
        UserDefaults.standard.integer(forKey: "outerworld_totalcollected") / 5
    }
    
    private func explanationText(for stat: StatType) -> String {
        switch stat {
        case .shields:
            return loc(appLanguage, "Apps protected by shields. Your call")
        case .energy:
            return loc(appLanguage, "Total control spent on entries and shield upgrades")
        case .batteries:
            return loc(appLanguage, "Batteries collected in Outer World map")
        }
    }
    
    @ViewBuilder
    private func statPill(type: StatType, icon: String, value: String, color: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if showStatExplanation == type {
                    showStatExplanation = nil
                } else {
                    showStatExplanation = type
                }
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.15), color.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: color.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(showStatExplanation == type ? color.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(showStatExplanation == type ? color.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
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
            return loc(appLanguage, "Night")
        } else if hour < 12 {
            return loc(appLanguage, "Morning")
        } else if hour < 17 {
            return loc(appLanguage, "Afternoon")
        } else if hour < 22 {
            return loc(appLanguage, "Evening")
        } else {
            return loc(appLanguage, "Night")
        }
    }
    
    private var totalLifetimeSpent: Int {
        model.appStepsSpentLifetime.values.reduce(0, +)
    }
    
    // MARK: - Activity Chart Section
    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc(appLanguage, "Activity"))
                        .font(.title3.weight(.bold))
                    Text(loc(appLanguage, "Control spent over time"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Range picker - improved design
                HStack(spacing: 4) {
                    ForEach([ChartRange.today, .week, .month], id: \.self) { range in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                chartRange = range
                            }
                        } label: {
                            Text(rangeLabel(range))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(chartRange == range ? 
                                              LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) :
                                              LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                                        )
                                )
                                .foregroundColor(chartRange == range ? .white : .secondary)
                        }
                    }
                }
                .padding(4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
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
        .padding(20)
        .background(glassCard)
    }
    
    private func rangeLabel(_ range: ChartRange) -> String {
        switch range {
        case .today: return loc(appLanguage, "Today")
        case .week: return loc(appLanguage, "Week")
        case .month: return loc(appLanguage, "Month")
        }
    }
    
    private var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.4))
            Text(loc(appLanguage, "No activity yet"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 160)
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
                        y: .value("Control", item.steps)
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
                .drawingGroup()
            }
        } else {
            Chart(data) { item in
                let isHighlighted = (selectedBundleForChart == nil) || (selectedBundleForChart == item.bundleId)
                let baseColor = colorForBundle(item.bundleId)
                
                AreaMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Control", item.count),
                    series: .value("App", item.appName)
                )
                .foregroundStyle(baseColor.opacity(isHighlighted ? 0.12 : 0.03))
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Control", item.count),
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
            .drawingGroup()
        }
    }
    
    // MARK: - App Usage Section
    private var appUsageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc(appLanguage, "Apps"))
                        .font(.title3.weight(.bold))
                    Text(loc(appLanguage, "Control spent per app"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !trackedAppsToday.isEmpty {
                    Text("\(trackedAppsToday.count)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
            
            if trackedAppsToday.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(loc(appLanguage, "No usage yet"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(trackedAppsToday.enumerated()), id: \.element.id) { index, item in
                        appUsageRow(item: item)
                        
                        if index < trackedAppsToday.count - 1 {
                            Divider()
                                .padding(.leading, 64)
                                .opacity(0.3)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(glassCard)
    }
    
    @ViewBuilder
    private func appUsageRow(item: AppUsageToday) -> some View {
        let isSelected = selectedBundleForChart == item.bundleId
        let timeAccessEnabled = model.isTimeAccessEnabled(for: item.bundleId)
        let minutesText = timeAccessEnabled ? formatMinutes(model.minuteTimeToday(for: item.bundleId)) : "—"
        let appColor = colorForBundle(item.bundleId)
        
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // App icon with improved glow
                ZStack {
                    // Enhanced glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [appColor.opacity(0.25), appColor.opacity(0.1), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 56, height: 56)
                        .blur(radius: 10)
                    
                    appIconImage(item.imageName)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: appColor.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(formatNumber(item.steps))")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [appColor, appColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .monospacedDigit()
                    }
                    
                    // Energy bar - improved design
                    GeometryReader { geo in
                        let maxSteps = trackedAppsToday.map { $0.steps }.max() ?? 1
                        let ratio = Double(item.steps) / Double(max(1, maxSteps))
                        let width = geo.size.width * ratio
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [appColor, appColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, width), height: 6)
                                .shadow(color: appColor.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        if timeAccessEnabled {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                Text(minutesText)
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Only show chevron in week/month mode
                        if chartRange != .today {
                            Image(systemName: isSelected ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.vertical, 12)
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
                    .padding(.leading, 64)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        StatusViewHelpers.formatMinutes(minutes, appLanguage: appLanguage)
    }

    // MARK: - Today's App Usage Chart
    
    private var todayAppUsageData: [(name: String, bundleId: String, spent: Int)] {
        let todayKey = AppModel.dayKey(for: Date())
        let todaySpent = model.appStepsSpentByDay[todayKey] ?? [:]
        
        var result: [(name: String, bundleId: String, spent: Int)] = []
        
        for (bundleId, spent) in todaySpent {
            if spent > 0 {
                // Check if it's a shield group
                if bundleId.hasPrefix("group_") {
                    let groupId = String(bundleId.dropFirst(6))
                    if let group = model.shieldGroups.first(where: { $0.id == groupId }) {
                        result.append((name: group.name, bundleId: bundleId, spent: spent))
                    } else {
                        result.append((name: "Shield Group", bundleId: bundleId, spent: spent))
                    }
                } else {
                    result.append((name: appDisplayName(bundleId), bundleId: bundleId, spent: spent))
                }
            }
        }
        
        return result.sorted { $0.spent > $1.spent }
    }
    
    private var todayAppUsageChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc(appLanguage, "Today's Usage"))
                        .font(.title3.weight(.bold))
                    Text(loc(appLanguage, "Energy spent on shields"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            let chartData = todayAppUsageData
            if chartData.isEmpty {
                emptyChartPlaceholder
            } else {
                todayChartView(data: chartData)
            }
        }
        .padding(20)
        .background(glassCard)
    }
    
    @ViewBuilder
    private func todayChartView(data: [(name: String, bundleId: String, spent: Int)]) -> some View {
        Chart(data, id: \.bundleId) { item in
            let baseColor = colorForBundle(item.bundleId)
            
            BarMark(
                x: .value("App", item.name),
                y: .value("Energy", item.spent)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [baseColor, baseColor.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(6)
        }
        .chartXAxis {
            AxisMarks { value in
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
        .frame(height: 250)
        .drawingGroup()
    }

    private var connectFirstModuleCTA: some View {
        VStack(spacing: 28) {
            // Icon with enhanced glow effect
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                
                // Middle glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                // Icon container
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 24, x: 0, y: 12)
                
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(accentGradient)
            }
            
            VStack(spacing: 10) {
                Text(loc(appLanguage, "No shields yet"))
                    .font(.title2.bold())
                
                Text(loc(appLanguage, "Connect your first shield. Or don't. Your call"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button {
                NotificationCenter.default.post(name: openModulesNotification, object: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    Text(loc(appLanguage, "Connect Shield"))
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: Color.blue.opacity(0.4), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .background(glassCard)
        .padding(.top, 40)
    }

    // MARK: - Chart Data
    
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
        StatusViewHelpers.colorForBundle(bundleId)
    }
    
    private var dateLabelFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = chartRange == .month ? "d/M" : "E"
        return df
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
        var opensDict: [String: Int] = [:]
        // Count opens from steps spent data (approximation)
        let keys = (0..<chartRange.days).compactMap { dayOffset in
            AppModel.dayKey(for: dateByAddingDays(to: currentDayStart, value: -dayOffset))
        }
        for key in keys {
            if let dayData = model.appStepsSpentByDay[key] {
                for (bundleId, _) in dayData {
                    let canonical = normalizeBundleId(bundleId)
                    opensDict[canonical, default: 0] += 1
                }
            }
        }

        let baseIds: [String]
        if chartRange == .today {
            let todayKey = AppModel.dayKey(for: currentDayStart)
            let spentTodayKeys = model.appStepsSpentByDay[todayKey]?.keys.map { normalizeBundleId($0) } ?? []
            let allSpentKeys = model.appStepsSpentByDay.values.flatMap { $0.keys }.map { normalizeBundleId($0) }
            baseIds = Set(allSpentKeys)
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
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(loc(appLanguage, "No usage in this period"))
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries.prefix(7), id: \.0) { entry in
                    HStack {
                        Text(detailDateFormatter.string(from: entry.0))
                            .font(.caption.weight(.medium))
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                            Text("\(entry.1)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
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
    
    // MARK: - 7-Day Calendar
    
    private struct DayData {
        let date: Date
        let dayKey: String
        let earned: Int
        let spent: Int
        let remaining: Int
        let remainingPercent: Double
        
        var hasData: Bool {
            spent > 0 || earned > 0
        }
    }
    
    private var last7Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }.reversed()
    }
    
    private func dayData(for date: Date) -> DayData {
        let dayKey = AppModel.dayKey(for: date)
        let isToday = Calendar.current.isDateInToday(date)
        
        // Calculate earned: steps for the day + bonuses (if available)
        // For today, use actual stepsToday + bonusSteps
        // For historical days, we don't have step data, so earned = 0 unless we can infer from spent
        let earned: Int
        if isToday {
            earned = Int(model.stepsToday) + model.bonusSteps
        } else {
            // For historical days, we don't have step data stored
            // We'll show based on spent data only
            earned = 0
        }
        
        // Calculate spent: sum of all appStepsSpentByDay[dayKey]
        let spent = (model.appStepsSpentByDay[dayKey] ?? [:]).values.reduce(0, +)
        
        let remaining = max(0, earned - spent)
        let remainingPercent = earned > 0 ? Double(remaining) / Double(earned) : 0.0
        
        return DayData(
            date: date,
            dayKey: dayKey,
            earned: earned,
            spent: spent,
            remaining: remaining,
            remainingPercent: remainingPercent
        )
    }
    
    private func punkRockTitle(for remainingPercent: Double) -> String {
        switch remainingPercent {
        case 0.0..<0.02: return "Burned Punk"
        case 0.02..<0.05: return "Empty Tank"
        case 0.05..<0.08: return "Fuse Blower"
        case 0.08..<0.12: return "Last Riffer"
        case 0.12..<0.16: return "Stage Diver"
        case 0.16..<0.20: return "Broken Amp"
        case 0.20..<0.25: return "Cracked Strings"
        case 0.25..<0.30: return "Low Gain"
        case 0.30..<0.35: return "Mosh Dweller"
        case 0.35..<0.40: return "Worn Shouter"
        case 0.40..<0.45: return "Tight Driver"
        case 0.45..<0.50: return "Noise Maker"
        case 0.50..<0.55: return "Rebel Grinder"
        case 0.55..<0.60: return "Backline Boss"
        case 0.60..<0.65: return "Spare Picks"
        case 0.65..<0.70: return "Clean Break"
        case 0.70..<0.75: return "Quiet Riot"
        case 0.75..<0.80: return "Crowd Denier"
        case 0.80..<0.90: return "Stage Saver"
        case 0.90...1.0: return "Sweat Free"
        default: return "Neutral"
        }
    }
    
    // Color intensity based on remaining balance: less remaining = brighter/more intense
    // Formula: remaining = earned - spent. Intensity = 1 - (remaining / earned)
    // Less remaining balance means higher intensity (red/orange), more remaining means calmer (green)
    private func colorForDay(_ dayData: DayData) -> Color {
        guard dayData.hasData else {
            return Color.gray.opacity(0.2)
        }
        
        // Invert: less remaining = more intense (brighter)
        // More remaining = calmer (darker/muted)
        let intensity = 1.0 - dayData.remainingPercent
        
        // Use orange/red gradient for intensity
        if intensity > 0.7 {
            return Color.red.opacity(0.6 + intensity * 0.4)
        } else if intensity > 0.4 {
            return Color.orange.opacity(0.5 + intensity * 0.3)
        } else if intensity > 0.2 {
            return Color.yellow.opacity(0.4 + intensity * 0.2)
        } else {
            return Color.green.opacity(0.3 + intensity * 0.2)
        }
    }
    
    private var sevenDayCalendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc(appLanguage, "7-Day Dashboard"))
                        .font(.title3.weight(.bold))
                    Text(loc(appLanguage, "Tap a day for details"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Calendar grid
            HStack(spacing: 8) {
                ForEach(last7Days, id: \.self) { date in
                    calendarDayCell(date: date)
                }
            }
        }
        .padding(20)
        .background(glassCard)
        .sheet(item: $selectedDayForDetail) { item in
            dayDetailSheet(date: item.date)
        }
    }
    
    @ViewBuilder
    private func calendarDayCell(date: Date) -> some View {
        let data = dayData(for: date)
        let isToday = Calendar.current.isDateInToday(date)
        let dayColor = colorForDay(data)
        
        Button {
            selectedDayForDetail = DayDetailItem(date: date)
        } label: {
            VStack(spacing: 8) {
                // Day label
                Text(dayLabel(for: date))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                
                // Day number
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
                
                // Color indicator
                RoundedRectangle(cornerRadius: 6)
                    .fill(dayColor)
                    .frame(height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isToday ? Color.blue : Color.clear, lineWidth: 2)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        return formatter.string(from: date).uppercased()
    }
    
    @ViewBuilder
    private func dayDetailSheet(date: Date) -> some View {
        let data = dayData(for: date)
        let dayKey = AppModel.dayKey(for: date)
        let spentByApp = model.appStepsSpentByDay[dayKey] ?? [:]
        let title = punkRockTitle(for: data.remainingPercent)
        let isToday = Calendar.current.isDateInToday(date)
        
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Day title with punk-rock style
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayDetailDateFormatter.string(from: date))
                            .font(.title2.weight(.bold))
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accentGradient)
                    }
                    .padding(.bottom, 8)
                    
                    // Summary stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc(appLanguage, "Summary"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        summaryRow(label: loc(appLanguage, "Steps"), value: data.earned > 0 ? "\(data.earned)" : "—")
                        summaryRow(label: loc(appLanguage, "Sleep"), value: isToday ? String(format: "%.1f", model.dailySleepHours) : "—")
                        summaryRow(label: loc(appLanguage, "Move Energy"), value: isToday ? "\(model.movePointsToday)" : "—")
                        summaryRow(label: loc(appLanguage, "Reboot Energy"), value: isToday ? "\(model.rebootPointsToday)" : "—")
                        summaryRow(label: loc(appLanguage, "Joy Energy"), value: isToday ? "\(model.joyCategoryPointsToday)" : "—")
                        summaryRow(label: loc(appLanguage, "Remaining Balance"), value: "\(data.remaining)")
                    }
                    .padding()
                    .background(glassCard)
                    
                    // Spent per app
                    if !spentByApp.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(loc(appLanguage, "Spent per App"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            ForEach(Array(spentByApp.sorted { $0.value > $1.value }), id: \.key) { bundleId, spent in
                                appSpentRow(bundleId: bundleId, spent: spent)
                            }
                        }
                        .padding()
                        .background(glassCard)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(loc(appLanguage, "Done")) {
                        selectedDayForDetail = nil
                    }
                }
            }
        }
    }
    
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }
    
    @ViewBuilder
    private func appSpentRow(bundleId: String, spent: Int) -> some View {
        // Check if it's a shield group (group_x format)
        if bundleId.hasPrefix("group_") {
            let groupId = String(bundleId.dropFirst(6)) // Remove "group_" prefix
            if let group = model.shieldGroups.first(where: { $0.id == groupId }) {
                HStack {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                    Text(group.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(spent)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                    Text("Shield Group")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(spent)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        } else {
            // Regular app
            HStack {
                Text(TargetResolver.displayName(for: bundleId))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(spent)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
    }
    
    private var dayDetailDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        df.locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        return df
    }
}
