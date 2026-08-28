import SwiftUI
import UIKit

enum MeCalendarTimeline {
    static func logicalToday(
        now: Date = .now,
        dayEndHour: Int,
        dayEndMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let key = DayBoundary.dayKey(
            for: now,
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute,
            calendar: calendar
        )
        return date(for: key, calendar: calendar) ?? calendar.startOfDay(for: now)
    }

    static func shouldAttemptRemoteRecovery(
        hasTrackedSnapshot: Bool,
        localCanvasMissing: Bool
    ) -> Bool {
        hasTrackedSnapshot && localCanvasMissing
    }

    static func dayKeys(
        trackedDayKeys _: Set<String>,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [String] {
        let todayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart

        var result: [String] = []
        var currentDate = start
        while currentDate <= todayStart {
            result.append(dayKey(for: currentDate, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = next
        }
        return result
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(for dayKey: String, calendar: Calendar = .current) -> Date? {
        let values = dayKey.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: values[0],
            month: values[1],
            day: values[2]
        ))
    }

    static func monthDays(
        containing date: Date,
        calendar: Calendar = .current
    ) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date)
        else { return [] }

        let firstDay = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        var result = Array<Date?>(repeating: nil, count: leadingEmptyDays)
        result.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        })
        return result
    }
}

enum MeCalendarTileLayout {
    static func tileWidth(
        containerWidth: CGFloat,
        count: Int,
        spacing: CGFloat,
        displayScale: CGFloat = 3
    ) -> CGFloat {
        guard count > 0 else { return 0 }
        let gaps = spacing * CGFloat(max(0, count - 1))
        let rawWidth = max(0, (containerWidth - gaps) / CGFloat(count))
        let scale = max(1, displayScale)
        return floor(rawWidth * scale) / scale
    }
}

struct MeCalendarTileBorderMetrics: Equatable {
    let lineWidth: CGFloat
    let opacity: Double
}

enum MeCalendarTileBorderStyle {
    static func metrics(isSelected: Bool) -> MeCalendarTileBorderMetrics {
        MeCalendarTileBorderMetrics(
            lineWidth: isSelected ? 1.5 : 1,
            opacity: isSelected ? 0.95 : 0.24
        )
    }
}

// MARK: - Me calendar
//
// A chronological seven-day strip: older days are on the left and today is
// on the right. Earlier saved posters belong to the full archive calendar.
// Tapping any of the seven days selects its health background or saved canvas
// in the large poster above.
struct MeCalendarStrip: View {
    let pastDays: [String: PastDaySnapshot]
    let recentHealthByDay: [String: MeDayHealth]
    let selectedDayKey: String
    let onSelect: (String) -> Void
    let posterCount: Int
    let onOpenArchive: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    private static let tileSpacing: CGFloat = 4
    private static let compactTileHeight: CGFloat = 76
    private static let accessibleTileSize = CGSize(width: 64, height: 96)

    private var todayKey: String {
        AppModel.dayKey(for: .now)
    }

    private var dayKeys: [String] {
        let today = CachedFormatters.dayKey.date(from: todayKey) ?? .now
        return MeCalendarTimeline.dayKeys(
            trackedDayKeys: Set(pastDays.keys),
            today: today
        )
    }

    var body: some View {
        let keys = dayKeys
        let tileHeight = dynamicTypeSize >= .accessibility1
            ? Self.accessibleTileSize.height
            : Self.compactTileHeight

        return VStack(alignment: .leading, spacing: 10) {
            recentDaysHeader
                .zIndex(1)

            GeometryReader { geometry in
                let tileWidth = MeCalendarTileLayout.tileWidth(
                    containerWidth: geometry.size.width,
                    count: keys.count,
                    spacing: Self.tileSpacing,
                    displayScale: displayScale
                )

                HStack(spacing: Self.tileSpacing) {
                    ForEach(keys, id: \.self) { key in
                        let isSelected = key == selectedDayKey
                        let shape = RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                        let border = MeCalendarTileBorderStyle.metrics(
                            isSelected: isSelected
                        )

                        DayHistoryTile(
                            dayKey: key,
                            snapshot: pastDays[key],
                            health: recentHealthByDay[key],
                            isSelected: isSelected,
                            onTap: { onSelect(key) }
                        )
                        .frame(width: tileWidth, height: tileHeight)
                        .clipShape(shape)
                        .overlay {
                            shape.strokeBorder(
                                isSelected
                                    ? AppColors.brandAccent.opacity(border.opacity)
                                    : theme.textPrimary.opacity(border.opacity),
                                lineWidth: border.lineWidth
                            )
                        }
                        .id(key)
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .frame(height: tileHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recentDaysHeader: some View {
        if dynamicTypeSize >= .accessibility1 {
            VStack(alignment: .leading, spacing: 0) {
                recentDaysTitle
                archiveButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(spacing: 12) {
                recentDaysTitle
                Spacer(minLength: 8)
                archiveButton
            }
        }
    }

    private var recentDaysTitle: some View {
        Text(String(localized: "LAST 7 CALENDAR DAYS", comment: "MeView – recent calendar section header"))
            .font(.geist(.caption).weight(.medium))
            .foregroundStyle(theme.textSecondary.opacity(0.72))
            .tracking(1.1)
    }

    private var archiveButton: some View {
        Button(action: onOpenArchive) {
            HStack(spacing: 4) {
                Text(String(localized: "Archive · \(posterCount)", comment: "Me archive – compact saved-poster count"))
                Image(systemName: "chevron.right")
                    .font(.geist(.caption2).weight(.semibold))
            }
            .font(.geist(.subheadline).weight(.medium))
            .foregroundStyle(AppColors.brandAccent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        // Keep the 44pt target in the parent's layout, rather than expanding
        // only the label's accessibility frame over the first calendar tile.
        .frame(minHeight: 44)
        .buttonStyle(.plain)
        .accessibilityIdentifier("me_archive_button")
        .accessibilityLabel(
            String(localized: "Archive, \(posterCount) posters", comment: "Me archive – compact action accessibility label")
        )
    }
}

// MARK: - Day Tile

struct DayHistoryTile: View {
    let dayKey: String
    let snapshot: PastDaySnapshot?
    let health: MeDayHealth?
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    @State private var thumbnail: UIImage?
    @State private var hasLoaded = false

    private var date: Date {
        CachedFormatters.dayKey.date(from: dayKey) ?? Date.now
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var weekdayLabel: String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return localizedShortWeekday }
        return symbols[weekday - 1]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return Button(action: onTap) {
            tileBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(shape)
        .clipShape(shape)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier("me_calendar_day_\(dayKey)")
        .accessibilityLabel(accessibilityLabel)
    }

    private var tileBody: some View {
        let resolvedHealth = health
            ?? snapshot.map(MeDayHealth.init(snapshot:))
            ?? MeDayHealth(steps: nil, sleepHours: nil)

        return ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                EnergyGradientBackground(
                    stepsPoints: resolvedHealth.stepsPoints,
                    sleepPoints: resolvedHealth.sleepPoints,
                    hasStepsData: resolvedHealth.hasStepsData,
                    hasSleepData: resolvedHealth.hasSleepData,
                    showGrain: true
                )
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 4) {
                Text(weekdayLabel)
                    .font(.geist(.caption2).weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? AppColors.brandAccent : theme.textPrimary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                Text(dayNumber)
                    .font(.unbounded(18, weight: .medium, relativeTo: .title3))
                    .fontDesign(nil)
                    .foregroundStyle(isSelected ? AppColors.brandAccent : theme.textPrimary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadThumbnail()
        }
    }

    private var accessibilityLabel: String {
        let dayName = localizedShortWeekday
        let monthDay = CachedFormatters.monthDay.string(from: date)
        if let health {
            let details = [
                health.steps.map { "\($0) steps" },
                health.sleepHours.map { "\($0.formatted(.number.precision(.fractionLength(1)))) hours sleep" }
            ].compactMap { $0 }.joined(separator: ", ")
            return "\(dayName), \(monthDay), \(details)"
        }
        if let snap = snapshot {
            return String(localized: "\(dayName), \(monthDay), \(snap.inkEarned) colors earned", comment: "Me calendar – tile a11y, with data")
        }
        return String(localized: "\(dayName), \(monthDay), no data", comment: "Me calendar – tile a11y, empty")
    }

    private var localizedShortWeekday: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    // MARK: - Thumbnail loading

    private func loadThumbnail() async {
        let key = dayKey
        var canvas = await Task.detached(priority: .utility) {
            CanvasStorageService.shared.loadCanvas(for: key)
        }.value

        if MeCalendarTimeline.shouldAttemptRemoteRecovery(
            hasTrackedSnapshot: snapshot != nil,
            localCanvasMissing: canvas == nil
        ) {
            if let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: key) {
                CanvasStorageService.shared.saveCanvas(remote)
                canvas = remote
            }
        }

        guard let canvas, !canvas.elements.isEmpty else {
            return
        }

        let size = CGSize(width: 240, height: 240 * 4.0 / 3.0)
        let fixedTime = canvas.lastModified

        let image = await HistoryThumbnailCache.shared.thumbnail(
            for: dayKey,
            canvas: canvas,
            size: size,
            fixedTime: fixedTime,
            theme: theme
        )

        await MainActor.run { thumbnail = image }
    }
}

// MARK: - Full calendar

struct MeFullCalendarView: View {
    @ObservedObject var model: AppModel
    let pastDays: [String: PastDaySnapshot]
    let recentHealthByDay: [String: MeDayHealth]
    let unlockRecords: [MePosterUnlockRecord]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var visibleMonth: Date
    @State private var selectedDayKey: String?

    init(
        model: AppModel,
        pastDays: [String: PastDaySnapshot],
        recentHealthByDay: [String: MeDayHealth] = [:],
        unlockRecords: [MePosterUnlockRecord] = []
    ) {
        self.model = model
        self.pastDays = pastDays
        self.recentHealthByDay = recentHealthByDay
        self.unlockRecords = unlockRecords
        let boundary = AppModel.storedDayEnd()
        _visibleMonth = State(initialValue: MeCalendarTimeline.logicalToday(
            dayEndHour: boundary.hour,
            dayEndMinute: boundary.minute
        ))
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale.current
        return calendar
    }

    private var todayKey: String {
        AppModel.dayKey(for: .now)
    }

    private var logicalToday: Date {
        MeCalendarTimeline.date(for: todayKey, calendar: calendar)
            ?? calendar.startOfDay(for: .now)
    }

    private var monthCells: [Date?] {
        MeCalendarTimeline.monthDays(containing: visibleMonth, calendar: calendar)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
    }

    private var canMoveForward: Bool {
        guard let visible = calendar.dateInterval(of: .month, for: visibleMonth)?.start,
              let current = calendar.dateInterval(of: .month, for: logicalToday)?.start
        else { return false }
        return visible < current
    }

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 24) {
                        monthHeader
                        weekdayHeader
                        monthGrid
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .energyGradientBackground(model: model, showGrain: false)
        .preferredColorScheme(theme.colorScheme)
        .fullScreenCover(item: Binding(
            get: { selectedDayKey.map { MeDayKeyWrapper(key: $0) } },
            set: { selectedDayKey = $0?.key }
        )) { wrapper in
            DayCanvasViewerView(
                model: model,
                dayKey: wrapper.key,
                snapshot: pastDays[wrapper.key],
                health: recentHealthByDay[wrapper.key],
                unlockRecords: unlockRecords
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Calendar", comment: "Full calendar – title"))
                    .font(.geist(.title2).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(String(localized: "\(pastDays.count) days tracked", comment: "Full calendar – tracked count"))
                    .font(.geist(.caption))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            }

            Spacer()

            Button {
                visibleMonth = logicalToday
            } label: {
                Text(String(localized: "Today", comment: "Full calendar – jump to today"))
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.geist(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(String(localized: "Close", comment: "Full calendar – close"))
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Previous month", comment: "Full calendar – previous month"))

            Spacer()

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.geist(.headline))
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())

            Spacer()

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveForward)
            .opacity(canMoveForward ? 1 : 0.25)
            .accessibilityLabel(String(localized: "Next month", comment: "Full calendar – next month"))
        }
        .foregroundStyle(theme.textSecondary)
    }

    private var weekdayHeader: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
            spacing: 0
        ) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.geist(.caption2).weight(.medium))
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
            spacing: 8
        ) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = MeCalendarTimeline.dayKey(for: date, calendar: calendar)
        let isToday = key == todayKey
        let isTracked = pastDays[key] != nil
        let isFuture = date > logicalToday
        let day = calendar.component(.day, from: date)

        return Button {
            guard isTracked else { return }
            selectedDayKey = key
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isToday
                            ? theme.accentColor.opacity(0.18)
                            : theme.textPrimary.opacity(isTracked ? 0.07 : 0.025)
                    )

                Text(day.formatted())
                    .font(.unbounded(15, weight: isToday ? .bold : .medium, relativeTo: .body))
                    .fontDesign(nil)
                    .monospacedDigit()
                    .foregroundStyle(
                        isToday
                            ? theme.accentColor
                            : theme.textPrimary.opacity(isFuture ? 0.25 : 0.85)
                    )

                if isTracked {
                    Circle()
                        .fill(theme.accentColor.opacity(0.9))
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isToday ? theme.accentColor.opacity(0.8) : .clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isFuture || !isTracked)
        .accessibilityLabel(CachedFormatters.longDate.string(from: date))
        .accessibilityValue(isTracked ? String(localized: "Tracked", comment: "Full calendar – tracked day") : "")
    }

    private func moveMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = next
        }
    }
}

// MARK: - Preview

#Preview {
    MeCalendarStrip(
        pastDays: [:],
        recentHealthByDay: [:],
        selectedDayKey: AppModel.dayKey(for: .now),
        onSelect: { _ in },
        posterCount: 0,
        onOpenArchive: {}
    )
    .padding()
}
