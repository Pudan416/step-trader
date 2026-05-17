import SwiftUI
import UIKit

// MARK: - History View
/// Photos/Health-style grid of past day canvases. Groups by month with sticky
/// headers. The newest 7 days are always unlocked; days 8…90 are blurred behind
/// a Pro paywall (`PaywallView` with `source: .feature`). Tap an unlocked day
/// to open `DayCanvasViewerView` — a pixel-faithful render of the persisted
/// canvas at its frozen lastModified time.
struct HistoryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.topCardHeight) private var topCardHeight

    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var dayKeysSorted: [String] = []
    @State private var selectedDay: HistoryDayKey?
    @State private var showPaywall = false
    @State private var hasLoaded = false

    #if DEBUG
    @State private var debugForceUnlock = false
    #endif

    private var effectiveIsPro: Bool {
        #if DEBUG
        return model.isPro || debugForceUnlock
        #else
        return model.isPro
        #endif
    }

    private var unlockedKeys: Set<String> {
        if effectiveIsPro { return Set(dayKeysSorted) }
        return Set(dayKeysSorted.prefix(SubscriptionGate.freeHistoryDayCount))
    }

    private var groupedByMonth: [(monthDate: Date, keys: [String])] {
        var buckets: [Date: [String]] = [:]
        let cal = Calendar.current
        for key in dayKeysSorted {
            guard let date = CachedFormatters.dayKey.date(from: key) else { continue }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let monthDate = cal.date(from: comps) else { continue }
            buckets[monthDate, default: []].append(key)
        }
        return buckets
            .map { (monthDate: $0.key, keys: $0.value) }
            .sorted { $0.monthDate > $1.monthDate }
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                DetailHeader(title: String(localized: "History", comment: "HistoryView – page title"))
                    .padding(.horizontal, 16)

                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await reloadHistory()
        }
        .fullScreenCover(item: $selectedDay) { wrapper in
            DayCanvasViewerView(model: model, dayKey: wrapper.id)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(model: model, store: model.subscriptionStore, source: .feature)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if dayKeysSorted.isEmpty && hasLoaded {
            emptyState
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    counterRow

                    ForEach(groupedByMonth, id: \.monthDate) { group in
                        Section {
                            monthGrid(keys: group.keys)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                        } header: {
                            monthHeader(for: group.monthDate)
                        }
                    }

                    #if DEBUG
                    debugFooter
                    #endif

                    Color.clear.frame(height: 32)
                }
                .padding(.bottom, 16)
            }
            .refreshable {
                await reloadHistory()
            }
        }
    }

    private var counterRow: some View {
        let count = dayKeysSorted.count
        let text = String(localized: "\(count) days tracked", comment: "HistoryView – tracked count")
        return SettingsFooter(text: text)
            .padding(.horizontal, 20)
            .padding(.top, 4)
    }

    private func monthHeader(for monthDate: Date) -> some View {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL"
        let monthName = formatter.string(from: monthDate)
        let yearComp = cal.component(.year, from: monthDate)
        let currentYear = cal.component(.year, from: Date())

        return HStack(alignment: .firstTextBaseline) {
            Text(monthName)
                .font(.systemSerif(20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(theme.adaptivePrimaryText)
            if yearComp != currentYear {
                Text(String(yearComp))
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func monthGrid(keys: [String]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(keys, id: \.self) { key in
                DayHistoryTile(
                    model: model,
                    dayKey: key,
                    snapshot: pastDays[key],
                    isLocked: !unlockedKeys.contains(key),
                    onTap: { handleTap(key) }
                )
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 56, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.brandAccent)
            Text(String(localized: "No history yet", comment: "HistoryView – empty state title"))
                .font(.systemSerif(20, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(theme.adaptivePrimaryText)
            Text(String(localized: "Your daily canvases will appear here.", comment: "HistoryView – empty state subtitle"))
                .font(.subheadline)
                .foregroundStyle(theme.adaptiveSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    private var debugFooter: some View {
        HStack {
            Spacer()
            Toggle(isOn: $debugForceUnlock) {
                Text("🐛 Force unlock")
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            .toggleStyle(.switch)
            .tint(AppColors.brandAccent)
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }
    #endif

    // MARK: - Actions

    private func handleTap(_ dayKey: String) {
        if unlockedKeys.contains(dayKey) {
            selectedDay = HistoryDayKey(id: dayKey)
        } else {
            showPaywall = true
        }
    }

    private func reloadHistory() async {
        let local = model.loadPastDaySnapshots()
        let today = AppModel.dayKey(for: Date())
        await MainActor.run {
            pastDays = local
            var keys = Set(local.keys)
            keys.insert(today)
            dayKeysSorted = keys.sorted(by: >)
        }

        HistoryThumbnailCache.shared.invalidate(dayKey: today)

        let server = await SupabaseSyncService.shared.loadHistoricalSnapshots()
        guard !server.isEmpty else { return }

        await MainActor.run {
            var newFromServer: [String: PastDaySnapshot] = [:]
            for (key, snap) in server where pastDays[key] == nil {
                pastDays[key] = snap
                newFromServer[key] = snap
            }
            var keys = Set(pastDays.keys)
            keys.insert(today)
            dayKeysSorted = keys.sorted(by: >)

            if !newFromServer.isEmpty {
                model.mergePastDaySnapshots(newFromServer)
            }
        }
    }
}

private struct HistoryDayKey: Identifiable, Equatable {
    let id: String
}

// MARK: - Day Tile

struct DayHistoryTile: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let snapshot: PastDaySnapshot?
    let isLocked: Bool
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    @State private var thumbnail: UIImage?
    @State private var hasLoaded = false
    @State private var isEmptyDay = false

    private var date: Date {
        CachedFormatters.dayKey.date(from: dayKey) ?? Date()
    }

    private var isToday: Bool {
        dayKey == AppModel.dayKey(for: Date())
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var userName: String? {
        AuthenticationService.shared.currentUser?.displayName
    }

    var body: some View {
        Button(action: onTap) {
            tileBody
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var tileBody: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: isLocked ? 12 : 0)
            } else if isEmptyDay {
                Color(white: 0.94)
            } else {
                Color(white: 0.88)
            }

            Text(dayNumber)
                .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                .foregroundStyle(Color.yellow)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            if isToday {
                todayBadge
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if isLocked {
                lockOverlay
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(white: 0.82), lineWidth: 0.5)
        )
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadThumbnail()
        }
    }

    private var todayBadge: some View {
        Text(String(localized: "Today", comment: "HistoryView – today badge"))
            .font(.system(size: 8, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(AppColors.brandAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var lockOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)

            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.brandAccent)
                Text(String(localized: "Pro", comment: "HistoryView – locked tile badge"))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(AppColors.brandAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var accessibilityLabel: String {
        let dayName = CachedFormatters.shortWeekday.string(from: date)
        let monthDay = CachedFormatters.monthDay.string(from: date)
        if isLocked {
            return String(localized: "\(dayName), \(monthDay), locked, requires Pro", comment: "HistoryView – tile a11y, locked")
        }
        if let snap = snapshot {
            return String(localized: "\(dayName), \(monthDay), \(snap.inkEarned) colors earned", comment: "HistoryView – tile a11y, with data")
        }
        return String(localized: "\(dayName), \(monthDay), no data", comment: "HistoryView – tile a11y, empty")
    }

    // MARK: - Thumbnail loading

    private func loadThumbnail() async {
        let key = dayKey
        var canvas = await Task.detached(priority: .utility) {
            CanvasStorageService.shared.loadCanvas(for: key)
        }.value

        if canvas == nil && !isLocked {
            if let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: key) {
                CanvasStorageService.shared.saveCanvas(remote)
                canvas = remote
            }
        }

        guard let canvas, !canvas.elements.isEmpty else {
            await MainActor.run { isEmptyDay = true }
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

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryView(model: DIContainer.shared.makeAppModel())
    }
}
