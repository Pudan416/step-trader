import SwiftUI
import UIKit

// MARK: - Me calendar
//
// Past days as a horizontal strip, newest first, scrolling back into the past.
// Tapping a day opens `DayCanvasViewerView` — a pixel-faithful render of the
// persisted canvas at its frozen lastModified time.
//
// The Pro gate is dormant, not gone: `SubscriptionGate.allFeaturesUnlocked` is
// currently `true`, so `model.isPro` is unconditionally true and every day is
// open. The constant is a documented kill-switch, so the gating stays wired.
struct MeCalendarStrip: View {
    @ObservedObject var model: AppModel
    let pastDays: [String: PastDaySnapshot]
    let onSelect: (String) -> Void
    let onLocked: () -> Void

    @Environment(\.appTheme) private var theme

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

    /// Newest first. Today is always present, even before it has a snapshot.
    private var dayKeysSorted: [String] {
        var keys = Set(pastDays.keys)
        keys.insert(AppModel.dayKey(for: Date.now))
        return keys.sorted(by: >)
    }

    var body: some View {
        let keys = dayKeysSorted
        let unlocked = MeWeekStats.unlockedKeys(
            sortedKeys: keys,
            isPro: effectiveIsPro,
            freeCount: SubscriptionGate.freeHistoryDayCount
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "CALENDAR", comment: "MeView – calendar section header"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary.opacity(0.55))
                    .tracking(0.6)
                Spacer(minLength: 8)
                Text(String(localized: "\(keys.count) days tracked", comment: "MeView – tracked count"))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(keys, id: \.self) { key in
                        DayHistoryTile(
                            model: model,
                            dayKey: key,
                            snapshot: pastDays[key],
                            isLocked: !unlocked.contains(key),
                            onTap: {
                                if unlocked.contains(key) { onSelect(key) } else { onLocked() }
                            }
                        )
                        .frame(width: 96, height: 128)
                    }
                }
            }
            .scrollIndicators(.hidden)

            #if DEBUG
            Toggle(isOn: $debugForceUnlock) {
                Text("🐛 Force unlock")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(AppColors.brandAccent)
            #endif
        }
    }
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
        CachedFormatters.dayKey.date(from: dayKey) ?? Date.now
    }

    private var isToday: Bool {
        dayKey == AppModel.dayKey(for: Date.now)
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
                .font(.system(size: 28, weight: .black, design: .serif))
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
        Text(String(localized: "Today", comment: "Me calendar – today badge"))
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
                Text(String(localized: "Pro", comment: "Me calendar – locked tile badge"))
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
            return String(localized: "\(dayName), \(monthDay), locked, requires Pro", comment: "Me calendar – tile a11y, locked")
        }
        if let snap = snapshot {
            return String(localized: "\(dayName), \(monthDay), \(snap.inkEarned) colors earned", comment: "Me calendar – tile a11y, with data")
        }
        return String(localized: "\(dayName), \(monthDay), no data", comment: "Me calendar – tile a11y, empty")
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
    MeCalendarStrip(
        model: DIContainer.shared.makeAppModel(),
        pastDays: [:],
        onSelect: { _ in },
        onLocked: {}
    )
    .padding()
}
