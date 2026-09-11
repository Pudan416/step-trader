import SwiftUI
import WidgetKit
import AppIntents

private enum WidgetStyle {
    // Shared with the app's smoked Canvas surfaces and duration controls.
    static var palette: DailyInterfacePalette {
        .load(from: UserDefaults(suiteName: SharedKeys.appGroupId) ?? .standard)
    }
    static var accent: Color { palette.accent.color }
    static var background: Color { palette.ink.color }
}

struct UnlockWidgetEntryView: View {
    let entry: UnlockEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        NowhereWidgetContent(entry: entry, kind: family == .systemLarge ? .groups : .status)
    }
}

struct ComboWidgetEntryView: View {
    let entry: UnlockEntry

    var body: some View {
        NowhereWidgetContent(entry: entry, kind: .combo)
    }
}

enum NowhereWidgetKind { case status, combo, groups }

/// Full color and Clear use one hierarchy. Only the system-controlled surfaces
/// and accents change; names, prices and actions never move between appearances.
struct NowhereWidgetContent: View {
    let entry: UnlockEntry
    let kind: NowhereWidgetKind
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isAccented: Bool { renderingMode == .accented }
    private var ink: Color { isAccented ? .primary : .white }
    private var accent: Color { isAccented ? .primary : WidgetStyle.accent }
    private var groups: [UnlockEntry.GroupSnapshot] {
        var seen = Set<String>()
        return entry.selectedGroupIds.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return entry.groups.first { $0.id == id }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            widgetContent(dense: geometry.size.height < 320)
        }
        .containerBackground(for: .widget) {
            if !isAccented {
                if let image = entry.wallpaperBackground {
                    Image(uiImage: image).resizable().scaledToFill()
                        .overlay(.black.opacity(reduceTransparency ? 0.85 : 0.48))
                } else {
                    WidgetStyle.background
                }
            }
        }
    }

    private func widgetContent(dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            balanceHeader
            switch kind {
            case .status:
                statusContent
            case .combo:
                if let group = groups.first {
                    groupCard(group, compact: false)
                } else {
                    emptyState
                }
            case .groups:
                if groups.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 6) {
                        ForEach(groups.prefix(4)) { group in
                            groupCard(group, compact: groups.count >= 4, dense: dense)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(ink)
    }

    private var balanceHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "drop.fill")
                .font(.onest(size: 12))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("\(entry.colorsBalance)")
                .font(.onest(size: 24, weight: .medium))
                .monospacedDigit()
                .widgetAccentable()
            Text("colors")
                .font(.onest(size: 12))
                .opacity(0.8)
            Spacer(minLength: 4)
            if kind == .status {
                Text("\(entry.energyData.earned) earned")
                    .font(.onest(size: 11)).monospacedDigit()
                    .opacity(0.8)
            }
            Button(intent: RefreshWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.onest(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(ink.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh colors and app groups")
        }
        .frame(height: 28)
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let fraction = min(max(Double(entry.energyData.earned) / Double(max(1, entry.energyData.maxEnergy)), 0), 1)
                Capsule().fill(ink.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent)
                            .frame(width: geometry.size.width * fraction)
                            .widgetAccentable()
                    }
            }
            .frame(height: 4)
            .accessibilityLabel("\(entry.energyData.earned) of \(entry.energyData.maxEnergy) colors earned")
            HStack(spacing: 6) {
                metric("Steps", icon: "shoeprints.fill", value: entry.energyData.stepsPoints, maximum: 20)
                metric("Sleep", icon: "bed.double.fill", value: entry.energyData.sleepPoints, maximum: 20)
                metric("Happenings", icon: "sparkles", value: entry.energyData.bodyPoints + entry.energyData.mindPoints + entry.energyData.heartPoints, maximum: 60)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func metric(_ title: LocalizedStringKey, icon: String, value: Int, maximum: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.onest(size: 10))
                Text(title).font(.onest(size: 10)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .opacity(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)").font(.onest(size: 19, weight: .medium))
                Text("/ \(maximum)").font(.onest(size: 10)).opacity(0.7)
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func identity(for group: UnlockEntry.GroupSnapshot) -> AppGroupIdentity {
        group.identity ?? AppGroupIdentity(name: group.name, templateApp: group.templateApp, applicationCount: group.appsCount)
    }

    private func groupCard(_ group: UnlockEntry.GroupSnapshot, compact: Bool, dense: Bool = false) -> some View {
        let identity = identity(for: group)
        return VStack(alignment: .leading, spacing: compact ? (dense ? 2 : 4) : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(identity.title)
                    .font(.onest(size: compact ? 13 : 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(identity.detail)
                    .font(.onest(size: 10))
                    .opacity(0.75)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if group.isUnlocked {
                activeGroup(group, identity: identity, compact: compact, dense: dense)
            } else {
                HStack(spacing: 6) {
                    ForEach(group.enabledIntervals.sorted { $0.minutes < $1.minutes }, id: \.self) { window in
                        durationButton(window, group: group, identity: identity, compact: compact, dense: dense)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? (dense ? 4 : 7) : 10)
        .frame(maxWidth: .infinity, maxHeight: kind == .combo ? .infinity : nil, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .fill(isAccented ? Color.primary.opacity(0.1) : Color.white.opacity(reduceTransparency ? 0.18 : 0.10))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(identity.title), \(identity.detail)")
    }

    private func durationButton(_ window: AccessWindow, group: UnlockEntry.GroupSnapshot, identity: AppGroupIdentity, compact: Bool, dense: Bool) -> some View {
        let cost = TicketGroup.cost(for: window)
        let canAfford = entry.colorsBalance >= cost
        return Button(intent: UnlockGroupWidgetIntent(groupId: group.id, window: window)) {
            VStack(spacing: 2) {
                Text("\(window.minutes) min")
                    .font(.onest(size: compact ? 11 : 13))
                HStack(spacing: 3) {
                    Image(systemName: "drop.fill").font(.onest(size: 8))
                    Text("\(cost)").font(.onest(size: compact ? 10 : 11, weight: .medium))
                }
                .foregroundStyle(accent)
                .widgetAccentable()
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: compact ? (dense ? 28 : 32) : 40)
            .background(ink.opacity(0.11), in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
        }
        .buttonStyle(.plain)
        .disabled(!canAfford)
        .opacity(canAfford ? 1 : 0.5)
        .accessibilityLabel("Unlock \(identity.title) for \(window.minutes) minutes, \(cost) colors")
        .accessibilityHint(canAfford ? Text("Unlock this group") : Text("Not enough colors"))
    }

    private func activeGroup(_ group: UnlockEntry.GroupSnapshot, identity: AppGroupIdentity, compact: Bool, dense: Bool) -> some View {
        return activeGroupLink(group) {
            HStack(spacing: 6) {
                Image(systemName: "lock.open").font(.onest(size: 11))
                Text("\(group.budgetMinutes) min left")
                    .font(.onest(size: compact ? 12 : 14)).monospacedDigit()
                Spacer(minLength: 0)
                if group.templateApp != nil {
                    Image(systemName: "arrow.up.right").font(.onest(size: 11))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: compact ? (dense ? 28 : 32) : 40)
            .background {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 14).fill(ink.opacity(0.08))
                    RoundedRectangle(cornerRadius: 14).fill(accent.opacity(isAccented ? 0.16 : 0.24))
                        .frame(width: geometry.size.width * min(1, Double(group.budgetMinutes) / Double(max(1, group.budgetInitial, group.budgetMinutes))))
                }
            }
        }
        .accessibilityLabel("\(identity.title), \(group.budgetMinutes) minutes left")
    }

    @ViewBuilder
    private func activeGroupLink<Content: View>(_ group: UnlockEntry.GroupSnapshot, @ViewBuilder content: () -> Content) -> some View {
        if let bundle = group.templateApp,
           let url = URL(string: "steps-trader://openapp?bundleId=\(bundle)") {
            Link(destination: url, label: content)
        } else {
            content()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2").font(.onest(size: 24))
            Text("Choose an app group").font(.onest(size: 14, weight: .medium))
            Text("Long-press → Edit Widget")
                .font(.onest(size: 11)).opacity(0.75)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
