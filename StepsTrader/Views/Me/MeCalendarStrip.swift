import SwiftUI
import UIKit

// MARK: - Me calendar
//
// Past days as a horizontal strip, newest first, scrolling back into the past.
// Tapping a day opens `DayCanvasViewerView` — a pixel-faithful render of the
// persisted canvas at its frozen lastModified time.
//
// Every day is open — the app is free and there is no history gate.
struct MeCalendarStrip: View {
    @ObservedObject var model: AppModel
    let pastDays: [String: PastDaySnapshot]
    let onSelect: (String) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 3:4, matching the poster the tile opens.
    private static let tileSize = CGSize(width: 96, height: 128)

    /// Short month name for a day key, e.g. "Aug" — localised, and abbreviated
    /// by the locale's own rules rather than by truncation.
    private func monthLabel(for dayKey: String) -> String? {
        guard let date = CachedFormatters.dayKey.date(from: dayKey) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("LLL")
        return formatter.string(from: date)
    }

    /// Newest first. Today is always present, even before it has a snapshot.
    private var dayKeysSorted: [String] {
        var keys = Set(pastDays.keys)
        keys.insert(AppModel.dayKey(for: Date.now))
        return keys.sorted(by: >)
    }

    var body: some View {
        let keys = dayKeysSorted

        return VStack(alignment: .leading, spacing: 10) {
            // The header is a fixed-size label and the count scales, so side by
            // side they collide at accessibility sizes. Stack them there.
            let header = Text(String(localized: "CALENDAR", comment: "MeView – calendar section header"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary.opacity(0.55))
                .tracking(0.6)
            let count = Group {
                if !pastDays.isEmpty {
                    Text(String(localized: "\(keys.count) days tracked", comment: "MeView – tracked count"))
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
            }

            if dynamicTypeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: 2) {
                    header
                    count
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    header
                    Spacer(minLength: 8)
                    count
                }
            }

            // On a first run the strip still holds today's tile, so it never
            // looks broken — but nothing explains what it is going to become.
            if pastDays.isEmpty {
                Text(String(localized: "Your days will collect here.",
                            comment: "Me calendar – empty state"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                        // Name a month the first time you reach it, so scrolling
                        // back reads as travel rather than as more of the same.
                        if index == 0 || monthLabel(for: key) != monthLabel(for: keys[index - 1]),
                           let month = monthLabel(for: key) {
                            Text(month)
                                .font(.caption2)
                                .foregroundStyle(theme.textSecondary.opacity(0.5))
                                .fixedSize()
                                .rotationEffect(.degrees(-90))
                                .frame(width: 16, height: Self.tileSize.height)
                        }

                        DayHistoryTile(
                            model: model,
                            dayKey: key,
                            snapshot: pastDays[key],
                            onTap: { onSelect(key) }
                        )
                        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                    }
                }
            }
            // Without an explicit height the scroll view claims every point the
            // VStack has left, floating the tiles in the middle of it and
            // pushing whatever follows off the bottom of the screen.
            .frame(height: Self.tileSize.height)
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Day Tile

struct DayHistoryTile: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let snapshot: PastDaySnapshot?
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
            } else if isEmptyDay {
                // The tile came from a Photos-style grid on a light settings
                // background. On Me it sits on the dark energy gradient, where
                // fixed light greys read as punched-out white blocks — so the
                // placeholders and the border come from the theme instead.
                theme.textPrimary.opacity(0.06)
            } else {
                theme.textPrimary.opacity(0.10)
            }

            Text(dayNumber)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(isToday ? AppColors.brandAccent : theme.textPrimary.opacity(0.75))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            if isToday {
                todayBadge
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.stroke.opacity(theme.strokeOpacity * 0.5), lineWidth: 0.5)
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

    private var accessibilityLabel: String {
        let dayName = CachedFormatters.shortWeekday.string(from: date)
        let monthDay = CachedFormatters.monthDay.string(from: date)
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

        if canvas == nil {
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
        onSelect: { _ in }
    )
    .padding()
}
