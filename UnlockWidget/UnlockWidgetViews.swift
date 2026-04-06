import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Brand Colors

// NOTE: Must match AppColors.brandAccent (#FFD369) — widget target can't import ColorConstants
private enum WidgetColors {
    static let brandAccent = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)
    static let darkCircle = Color(red: 0x1C/255, green: 0x1B/255, blue: 0x1B/255)
}

// MARK: - Icon Mapping (mirrors TargetResolver.bundleToImageName)

private let templateAppImageName: [String: String] = [
    "com.burbn.instagram": "instagram",
    "com.zhiliaoapp.musically": "tiktok",
    "com.google.ios.youtube": "youtube",
    "com.toyopagroup.picaboo": "snapchat",
    "com.reddit.Reddit": "reddit",
    "com.atebits.Tweetie2": "x",
    "com.facebook.Facebook": "facebook",
    "com.linkedin.LinkedIn": "linkedin",
    "com.pinterest": "pinterest",
    "ph.telegra.Telegraph": "telegram",
    "net.whatsapp.WhatsApp": "whatsapp"
]

private let templateAppScheme: [String: String] = [
    "com.burbn.instagram": "instagram://app",
    "com.zhiliaoapp.musically": "tiktok://",
    "com.google.ios.youtube": "youtube://",
    "com.toyopagroup.picaboo": "snapchat://",
    "com.reddit.Reddit": "reddit://",
    "com.atebits.Tweetie2": "twitter://",
    "com.facebook.Facebook": "fb://",
    "com.linkedin.LinkedIn": "linkedin://",
    "com.pinterest": "pinterest://",
    "ph.telegra.Telegraph": "tg://",
    "net.whatsapp.WhatsApp": "whatsapp://"
]

// MARK: - RayCapsuleSurface (ported from main app)

private enum RayDirection { case left, right }

private struct RayCapsuleSurface: View {
    let baseColor: Color
    let direction: RayDirection

    private let gradientStop: CGFloat = 0.889432
    private let radiusScale: CGFloat = 310.5 / 341.0

    private var center: UnitPoint {
        switch direction {
        case .left:  return UnitPoint(x: 26.0 / 341.0, y: 32.5 / 65.0)
        case .right: return UnitPoint(x: 315.0 / 341.0, y: 32.5 / 65.0)
        }
    }

    private var alphaGradient: LinearGradient {
        switch direction {
        case .left:
            return LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.75), location: 0.20),
                    .init(color: .white.opacity(0.50), location: 0.35),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .clear, location: 0.75)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        case .right:
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .white.opacity(0.50), location: 0.65),
                    .init(color: .white.opacity(0.75), location: 0.80),
                    .init(color: .white, location: 1.00)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(baseColor)
                .overlay(
                    Capsule().fill(
                        RadialGradient(
                            stops: [
                                .init(color: .black.opacity(0.12), location: 0),
                                .init(color: .clear, location: gradientStop)
                            ],
                            center: center,
                            startRadius: 0,
                            endRadius: width * radiusScale
                        )
                    )
                )
                .mask(
                    Capsule().fill(alphaGradient)
                )
        }
    }
}

// MARK: - Root Widget View

struct UnlockWidgetEntryView: View {
    let entry: UnlockEntry
    @Environment(\.widgetFamily) var family

    private var ink: Color { .white }
    private var secondaryInk: Color { .white.opacity(0.5) }
    private var tertiaryInk: Color { .white.opacity(0.3) }
    private var chipBg: Color { .white.opacity(0.06) }

    @ViewBuilder
    private var appLogo: some View {
        if let img = UIImage(named: "colors") {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14))
                .foregroundStyle(WidgetColors.brandAccent)
        }
    }

    /// Only shows groups explicitly selected in the widget configuration.
    private var visibleGroups: [UnlockEntry.GroupSnapshot] {
        let ids = entry.selectedGroupIds
        return ids.compactMap { id in entry.groups.first { $0.id == id } }
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumWidget
            case .systemLarge:
                if visibleGroups.isEmpty { emptyState } else { largeWidget }
            default:
                mediumWidget
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if let wallpaper = entry.wallpaperBackground {
            Image(uiImage: wallpaper)
                .resizable()
                .scaledToFill()
        } else {
            Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(secondaryInk)
            Text("No Groups Selected")
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryInk)
            Text("Long-press → Edit Widget to add groups")
                .font(.caption2)
                .foregroundStyle(tertiaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium Widget (energy dashboard — mirrors app StepBalanceCard)

    private var mediumWidget: some View {
        let e = entry.energyData
        let earnedFraction = Double(e.earned) / Double(max(e.maxEnergy, 1))
        let remainFraction = Double(e.remaining) / Double(max(e.maxEnergy, 1))

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                appLogo

                Text("\(e.remaining)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(WidgetColors.brandAccent))

                Text("/")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(secondaryInk)

                Text("\(e.earned)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(ink)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(WidgetColors.brandAccent, lineWidth: 1))

                Text("/")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(secondaryInk)

                Text("\(e.maxEnergy)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(secondaryInk)
                    .monospacedDigit()

                Spacer()

                if let resetDate = e.resetDate {
                    HStack(spacing: 3) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 8))
                        Text("ends \(resetDate, style: .time)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(secondaryInk)
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                    if earnedFraction > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(WidgetColors.brandAccent, lineWidth: 1.5)
                            .frame(width: max(4, w * earnedFraction))
                    }
                    if remainFraction > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(WidgetColors.brandAccent)
                            .frame(width: max(4, w * remainFraction))
                    }
                }
            }
            .frame(height: 8)

            Spacer(minLength: 2)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    categoryChip(icon: "shoeprints.fill", value: e.stepsPoints, max: 20)
                    categoryChip(icon: "bed.double.fill", value: e.sleepPoints, max: 20)
                }
                HStack(spacing: 8) {
                    categoryChip(icon: "figure.walk", value: e.bodyPoints, max: 20)
                    categoryChip(icon: "brain.head.profile", value: e.mindPoints, max: 20)
                    categoryChip(icon: "heart.fill", value: e.heartPoints, max: 20)
                }
            }

            updateFooter
        }
        .padding(12)
    }

    private func categoryChip(icon: String, value: Int, max: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .regular))
                .frame(width: 14)
            Spacer(minLength: 0)
            Text("\(value)/\(max)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundColor(value > 0 ? ink : secondaryInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Large Widget (Feeds-Page Tickets)

    private var largeWidget: some View {
        VStack(spacing: 8) {
            HStack {
                largeColorsChip

                Spacer()

                Text("UPD \(entry.date, style: .relative)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))

                Spacer()

                refreshButton
            }

            ForEach(visibleGroups) { group in
                if let bundleId = group.templateApp,
                   templateAppScheme[bundleId] != nil,
                   let url = URL(string: "steps-trader://openapp?bundleId=\(bundleId)") {
                    Link(destination: url) {
                        ticketRow(group: group)
                    }
                } else {
                    ticketRow(group: group)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    // MARK: - Ticket Row (mirrors PaperTicketView from feeds page)

    private func ticketRow(group: UnlockEntry.GroupSnapshot) -> some View {
        let isBudgetUnlock = group.budgetMinutes > 0
        let cardBase: Color = group.isUnlocked ? .white : WidgetColors.brandAccent

        return ZStack {
            RayCapsuleSurface(baseColor: cardBase, direction: group.isUnlocked ? .right : .left)

            if group.isUnlocked {
                Capsule()
                    .strokeBorder(WidgetColors.brandAccent.opacity(0.4), lineWidth: 1)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                    ticketIcon(for: group)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.name)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        Spacer()

                        Image(systemName: group.isUnlocked ? "lock.open" : "lock.fill")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundColor(group.isUnlocked ? WidgetColors.brandAccent : .black.opacity(0.35))
                    }

                    if group.isUnlocked, isBudgetUnlock {
                        budgetBar(remaining: group.budgetMinutes, initial: group.budgetInitial)
                    } else if !group.isUnlocked {
                        HStack(spacing: 4) {
                            unlockButtons(group: group)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 68)
    }

    private func budgetBar(remaining: Int, initial: Int) -> some View {
        let effectiveInitial = max(initial, remaining, 1)
        let fraction = Double(remaining) / Double(effectiveInitial)

        return HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.1))
                    Capsule()
                        .fill(WidgetColors.brandAccent)
                        .frame(width: max(geo.size.width * fraction, 4))
                }
            }
            .frame(height: 5)

            Text("\(remaining)m")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.black.opacity(0.5))
                .monospacedDigit()
        }
    }

    // MARK: - Ticket Icon

    @ViewBuilder
    private func ticketIcon(for group: UnlockEntry.GroupSnapshot) -> some View {
        if let bundleId = group.templateApp,
           let assetName = templateAppImageName[bundleId],
           let uiImage = UIImage(named: assetName)
                ?? UIImage(named: assetName.lowercased())
                ?? UIImage(named: assetName.capitalized) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Unlock Buttons

    @ViewBuilder
    private func unlockButtons(group: UnlockEntry.GroupSnapshot) -> some View {
        let intervals = group.enabledIntervals.sorted { $0.minutes < $1.minutes }

        ForEach(intervals, id: \.self) { window in
            let cost = Self.cost(for: window)
            let canAfford = entry.colorsBalance >= cost

            Button(intent: UnlockGroupWidgetIntent(groupId: group.id, window: window)) {
                Text("\(window.displayName) · \(cost)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(WidgetColors.brandAccent.opacity(canAfford ? 1.0 : 0.25))
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }

    // MARK: - Colors Chips

    private var colorsChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8))
            Text("\(entry.colorsBalance)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(secondaryInk)
    }

    private var largeColorsChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
            Text("\(entry.colorsBalance)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(WidgetColors.brandAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(WidgetColors.darkCircle))
    }

    // MARK: - Last Update Footer (medium widget)

    private var updateFooter: some View {
        HStack(spacing: 6) {
            Text("UPD \(entry.date, style: .relative)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))

            Spacer()

            refreshButton
        }
    }

    // MARK: - Shared Refresh Button (yellow in black circle)

    private var refreshButton: some View {
        Button(intent: RefreshWidgetIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(WidgetColors.brandAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(WidgetColors.darkCircle))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private static func cost(for window: AccessWindow) -> Int {
        TicketGroup.cost(for: window)
    }
}

// MARK: - Combo Medium Widget View (energy bar + 1 app group)

struct ComboWidgetEntryView: View {
    let entry: UnlockEntry

    private var ink: Color { .white }
    private var secondaryInk: Color { .white.opacity(0.5) }

    private var selectedGroup: UnlockEntry.GroupSnapshot? {
        guard let id = entry.selectedGroupIds.first else { return nil }
        return entry.groups.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 6) {
            energyHeader
            energyBar
            if let group = selectedGroup {
                comboTicketRow(group: group)
            } else {
                comboEmptySlot
            }
            comboFooter
        }
        .padding(12)
        .containerBackground(for: .widget) {
            if let wallpaper = entry.wallpaperBackground {
                Image(uiImage: wallpaper)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)
            }
        }
    }

    // MARK: - Energy Header

    private var energyHeader: some View {
        let e = entry.energyData
        return HStack(spacing: 6) {
            if let img = UIImage(named: "colors") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Text("\(e.remaining)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule().fill(WidgetColors.brandAccent))

            Text("/")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(secondaryInk)

            Text("\(e.earned)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(ink)
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(WidgetColors.brandAccent, lineWidth: 1))

            Text("/")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(secondaryInk)

            Text("\(e.maxEnergy)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(secondaryInk)
                .monospacedDigit()

            Spacer()

            if let resetDate = e.resetDate {
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 7))
                    Text("ends \(resetDate, style: .time)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(secondaryInk)
            }
        }
    }

    // MARK: - Energy Bar

    private var energyBar: some View {
        let e = entry.energyData
        let earnedFraction = Double(e.earned) / Double(max(e.maxEnergy, 1))
        let remainFraction = Double(e.remaining) / Double(max(e.maxEnergy, 1))

        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                if earnedFraction > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(WidgetColors.brandAccent, lineWidth: 1.5)
                        .frame(width: max(4, w * earnedFraction))
                }
                if remainFraction > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(WidgetColors.brandAccent)
                        .frame(width: max(4, w * remainFraction))
                }
            }
        }
        .frame(height: 7)
    }

    // MARK: - Ticket Row

    private func comboTicketRow(group: UnlockEntry.GroupSnapshot) -> some View {
        let isBudgetUnlock = group.budgetMinutes > 0
        let cardBase: Color = group.isUnlocked ? .white : WidgetColors.brandAccent

        let rowContent = ZStack {
            RayCapsuleSurface(baseColor: cardBase, direction: group.isUnlocked ? .right : .left)

            if group.isUnlocked {
                Capsule()
                    .strokeBorder(WidgetColors.brandAccent.opacity(0.4), lineWidth: 1)
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                    comboTicketIcon(for: group)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.name)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        Spacer()

                        Image(systemName: group.isUnlocked ? "lock.open" : "lock.fill")
                            .font(.system(size: 7, weight: .regular))
                            .foregroundColor(group.isUnlocked ? WidgetColors.brandAccent : .black.opacity(0.35))
                    }

                    if group.isUnlocked, isBudgetUnlock {
                        comboBudgetBar(remaining: group.budgetMinutes, initial: group.budgetInitial)
                    } else if !group.isUnlocked {
                        HStack(spacing: 4) {
                            comboUnlockButtons(group: group)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
        }
        .frame(height: 60)

        if let bundleId = group.templateApp,
           templateAppScheme[bundleId] != nil,
           let url = URL(string: "steps-trader://openapp?bundleId=\(bundleId)") {
            return AnyView(Link(destination: url) { rowContent })
        }
        return AnyView(rowContent)
    }

    @ViewBuilder
    private func comboTicketIcon(for group: UnlockEntry.GroupSnapshot) -> some View {
        if let bundleId = group.templateApp,
           let assetName = templateAppImageName[bundleId],
           let uiImage = UIImage(named: assetName)
                ?? UIImage(named: assetName.lowercased())
                ?? UIImage(named: assetName.capitalized) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func comboBudgetBar(remaining: Int, initial: Int) -> some View {
        let effectiveInitial = max(initial, remaining, 1)
        let fraction = Double(remaining) / Double(effectiveInitial)

        return HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.1))
                    Capsule()
                        .fill(WidgetColors.brandAccent)
                        .frame(width: max(geo.size.width * fraction, 4))
                }
            }
            .frame(height: 4)

            Text("\(remaining)m")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.black.opacity(0.5))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func comboUnlockButtons(group: UnlockEntry.GroupSnapshot) -> some View {
        let intervals = group.enabledIntervals.sorted { $0.minutes < $1.minutes }

        ForEach(intervals, id: \.self) { window in
            let cost = TicketGroup.cost(for: window)
            let canAfford = entry.colorsBalance >= cost

            Button(intent: UnlockGroupWidgetIntent(groupId: group.id, window: window)) {
                Text("\(window.displayName) · \(cost)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(WidgetColors.brandAccent.opacity(canAfford ? 1.0 : 0.25))
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }

    // MARK: - Empty Slot

    private var comboEmptySlot: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.06))
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                Text("Long-press → Edit to pick a group")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.35))
        }
        .frame(height: 60)
    }

    // MARK: - Footer

    private var comboFooter: some View {
        HStack(spacing: 6) {
            Text("UPD \(entry.date, style: .relative)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))

            Spacer()

            Button(intent: RefreshWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(WidgetColors.brandAccent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(WidgetColors.darkCircle))
            }
            .buttonStyle(.plain)
        }
    }
}
