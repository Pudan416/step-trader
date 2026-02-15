import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import Foundation

struct TicketGroupId: Identifiable {
    let id: String
}

/// Single accent for primary actions (Create Ticket, unlock). Rest uses system colors.
fileprivate enum TicketsPalette {
    // Accent yellow: #FFD369
    static let accent = Color(red: 0xFF/255.0, green: 0xD3/255.0, blue: 0x69/255.0)

    // Theme accents (used on the flipped side for controls).
    static let themes: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.95), // blue
        Color(red: 0.62, green: 0.29, blue: 0.98), // purple
        Color(red: 0.05, green: 0.68, blue: 0.45), // teal/green
        Color(red: 0.95, green: 0.33, blue: 0.35), // red
        Color(red: 0.98, green: 0.55, blue: 0.15), // orange
        Color(red: 0.15, green: 0.75, blue: 0.95)  // cyan
    ]

    static func themeColor(for index: Int) -> Color {
        let safe = abs(index)
        return themes.isEmpty ? .blue : themes[safe % themes.count]
    }

    // (intentionally no longer used for back surface; back surface follows day/night theme)
}

struct AppsPageSimplified: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var selectedGroupId: TicketGroupId? = nil
    @State private var showTemplatePicker = false
    @State private var showDifficultyPicker = false
    @State private var pendingGroupIdForDifficulty: String? = nil
    // appLanguage removed — English only for v1
    private let appLanguage = "en"
    @State private var expandedSheetGroupId: TicketGroupId? = nil
    @State private var flippedTicketId: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                EnergyGradientBackground(
                    sleepPoints: model.sleepPointsToday,
                    stepsPoints: model.stepsPointsToday
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Custom inline header (replaces navigation title)
                    HStack {
                        Text("My Tickets")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    Button {
                        showTemplatePicker = true
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .ultraLight))
                                .foregroundStyle(Color.primary.opacity(0.7))
                        }
                    }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if model.blockingStore.ticketGroups.isEmpty {
                        emptyTicketsContent
                    } else {
                        ScrollView {
                            ticketStack
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 96)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .zIndex(0)

                Image("grain 1")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.28)
                    .blendMode(.overlay)
                    .zIndex(10)
            }
            .background(Color.clear)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .navigationBarHidden(true)
            .sheet(item: $expandedSheetGroupId) { groupId in
                if let index = model.blockingStore.ticketGroups.firstIndex(where: { $0.id == groupId.id }) {
                    let groupBinding = Binding<TicketGroup>(
                        get: { model.blockingStore.ticketGroups[index] },
                        set: { updated in model.updateTicketGroup(updated) }
                    )
                    ticketSettingsSheet(group: groupBinding, onDismiss: { expandedSheetGroupId = nil })
                }
            }
            .sheet(isPresented: $showPicker, onDismiss: {
                if let groupId = selectedGroupId {
                    if let group = model.blockingStore.ticketGroups.first(where: { $0.id == groupId.id }) {
                        let hasApps = !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
                        if !hasApps { model.deleteTicketGroup(groupId.id) }
                    }
                    selectedGroupId = nil
                }
            }) {
                #if canImport(FamilyControls)
                AppSelectionSheet(
                    selection: $selection,
                    templateApp: selectedGroupId.flatMap { gid in model.blockingStore.ticketGroups.first(where: { $0.id == gid.id })?.templateApp },
                    onDone: {
                        if let groupId = selectedGroupId {
                            let hasApps = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                            if hasApps {
                                model.addAppsToGroup(groupId.id, selection: selection)
                                if let group = model.blockingStore.ticketGroups.first(where: { $0.id == groupId.id }), group.templateApp != nil {
                                    pendingGroupIdForDifficulty = groupId.id
                                    showPicker = false
                                    showDifficultyPicker = true
                                } else {
                                    showPicker = false; selectedGroupId = nil
                                }
                            } else {
                                model.deleteTicketGroup(groupId.id)
                                showPicker = false; selectedGroupId = nil
                            }
                        } else {
                            model.syncFamilyControlsCards(from: selection)
                            showPicker = false; selectedGroupId = nil
                        }
                    }
                )
                #else
                Text("Family Controls not available").padding()
                #endif
            }
            .sheet(isPresented: $showDifficultyPicker) {
                if let groupId = pendingGroupIdForDifficulty,
                   let group = model.blockingStore.ticketGroups.first(where: { $0.id == groupId }) {
                    DifficultyPickerView(model: model, group: group, onDone: {
                        showDifficultyPicker = false; pendingGroupIdForDifficulty = nil; selectedGroupId = nil
                    })
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                TicketTemplatePickerView(
                    model: model,
                    onTemplateSelected: { templateApp in
                        showTemplatePicker = false
                        let displayName = TargetResolver.displayName(for: templateApp)
                        let group = model.createTicketGroup(name: displayName, templateApp: templateApp, stickerThemeIndex: 0)
                        selection = FamilyActivitySelection()
                        selectedGroupId = TicketGroupId(id: group.id)
                        showPicker = true
                    },
                    onCustomSelected: {
                        showTemplatePicker = false
                        let group = model.createTicketGroup(name: "New Ticket", stickerThemeIndex: 0)
                        selection = FamilyActivitySelection()
                        selectedGroupId = TicketGroupId(id: group.id)
                        showPicker = true
                    }
                )
            }
            .onAppear { selection = model.appSelection }
        }
    }

    // MARK: - Ticket Stack

    private var ticketStack: some View {
        LazyVStack(spacing: 14) {
            ForEach(visibleGroupIndices, id: \.self) { index in
                let group = model.blockingStore.ticketGroups[index]
                let isFlipped = flippedTicketId == group.id

                PaperTicketView(
                    model: model,
                    group: group,
                    colorScheme: colorScheme,
                    isFlipped: isFlipped,
                    onSettings: {
                        expandedSheetGroupId = TicketGroupId(id: group.id)
                    },
                    onFlip: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            if isFlipped {
                                flippedTicketId = nil
                            } else {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                flippedTicketId = group.id
                            }
                        }
                    }
                )
                .zIndex(isFlipped ? 10 : 0)
                .contextMenu {
                    Button {
                        expandedSheetGroupId = TicketGroupId(id: group.id)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button(role: .destructive) {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        model.deleteTicketGroup(group.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty state
    private var emptyTicketsContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "ticket")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("No tickets yet")
                    .font(.title3.weight(.semibold))
                Text("No tickets yet. Create one when you're ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button {
                showTemplatePicker = true
            } label: {
                Label("New Ticket", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(TicketsPalette.accent)
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Sheet for full ticket settings
    private func ticketSettingsSheet(group: Binding<TicketGroup>, onDismiss: @escaping () -> Void) -> some View {
        NavigationStack {
            ScrollView {
                InlineTicketSettingsView(
                    model: model, group: group,
                    onEditApps: {
                        selectedGroupId = TicketGroupId(id: group.wrappedValue.id)
                        selection = group.wrappedValue.selection
                        expandedSheetGroupId = nil
                        showPicker = true
                    },
                    onAfterDelete: onDismiss
                )
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle(group.wrappedValue.name.isEmpty ? "Ticket" : group.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .onDisappear(perform: onDismiss)
        }
    }

    private var visibleGroupIndices: [Int] {
        model.blockingStore.ticketGroups.indices.filter { idx in
            let g = model.blockingStore.ticketGroups[idx]
            return g.selection.applicationTokens.count > 0 || g.selection.categoryTokens.count > 0
        }
    }
}

// MARK: - Paper Ticket View (museum-style)

/// A ticket that looks like a simplified paper museum ticket.
/// Left stub (icon) | dashed perforation | main body (title, status, apps count)
/// Back side shows unlock buttons + settings gear when flipped.
fileprivate struct PaperTicketView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let appLanguage: String = "en"
    let colorScheme: ColorScheme
    let isFlipped: Bool
    var onSettings: () -> Void = {}
    var onFlip: () -> Void = {}

    @State private var isUnlocking = false

    private var frontFill: Color { Color(red: 0.95, green: 0.86, blue: 0.28) }
    private var backSurface: Color { .white }
    private var backIsDark: Bool { false } // back is always light

    private var frontInk: Color { .black }
    private var frontSecondaryInk: Color { .black }
    private var backInk: Color { .black }
    private var backSecondaryInk: Color { .black }

    private var isUnlocked: Bool { model.isGroupUnlocked(group.id) }
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    private let intervals: [AccessWindow] = [.minutes10, .minutes30, .hour1]

    private var spentToday: Int {
        model.appStepsSpentToday["group_\(group.id)"] ?? 0
    }
    private var spentLifetime: Int {
        model.totalStepsSpent(for: "group_\(group.id)")
    }

    var body: some View {
        Group {
            if isFlipped {
                backRayCard
            } else {
                frontRayCard
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isFlipped)
    }

    // MARK: - Front/back ray cards

    private var frontRayCard: some View {
        ZStack {
            RayCapsuleSurface(baseColor: frontFill, direction: .left)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                    ticketIcon
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ticketTitle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                        Spacer()
                        Text(isUnlocked ? "open" : "active")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black)
                    }

                    Text("\(appsCount) \(appsCount == 1 ? "app" : "apps")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black)

                    Text("\(spentToday) exp today   \(spentLifetime) exp total")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 90)
        .contentShape(Rectangle())
        .onTapGesture { onFlip() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > 50 {
                        onFlip()
                    }
                }
        )
    }

    private var backRayCard: some View {
        ZStack {
            RayCapsuleSurface(baseColor: backSurface, direction: .right)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        onFlip()
                    } label: {
                        Label("Tap to return", systemImage: "arrow.uturn.backward.circle")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.72))
                                    .overlay(
                                        Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    if isUnlocked {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.open")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.black)
                            if let remaining = model.remainingUnlockTime(for: group.id), remaining > 0 {
                                Text("\(formatTime(remaining)) left")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.black)
                            } else {
                                Text("Unlocked")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.black)
                            }
                            Spacer()
                        }
                        Text("Adjust settings on the right")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.62))
                    } else {
                        Text("Unlock for time")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black)

                        let enabledIntervals = intervals.filter { group.enabledIntervals.contains($0) }
                        HStack(spacing: 4) {
                            ForEach(enabledIntervals, id: \.self) { interval in
                                unlockPill(interval: interval)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 1)
                    .padding(.vertical, 9)

                Button {
                    onSettings()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.8))
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black)
                    }
                    .frame(width: 40, height: 40)
                    .frame(width: 58, height: 90)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 90)
        .contentShape(Rectangle())
        .onTapGesture { onFlip() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > 50 {
                        onFlip()
                    }
                }
        )
    }

    // MARK: - Unlock pill button

    private func unlockPill(interval: AccessWindow) -> some View {
        let cost = group.cost(for: interval)
        let canAfford = model.userEconomyStore.totalStepsBalance >= cost
        let label = shortTimeLabel(interval)

        return Button {
            guard canAfford, !isUnlocking else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                isUnlocking = true
                await model.handlePayGatePaymentForGroup(groupId: group.id, window: interval, costOverride: cost)
                isUnlocking = false
            }
        } label: {
            Text("\(label) · \(cost) exp")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(canAfford ? 1.0 : 0.45)
        .disabled(!canAfford || isUnlocking)
    }

    private func shortTimeLabel(_ interval: AccessWindow) -> String {
        switch interval {
        case .minutes10: return "10m"
        case .minutes30: return "30m"
        case .hour1: return "1h"
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var ticketIcon: some View {
        if let templateApp = group.templateApp,
           let imageName = TargetResolver.imageName(for: templateApp),
           let uiImage = UIImage(named: imageName) ?? UIImage(named: imageName.lowercased()) ?? UIImage(named: imageName.capitalized) {
            Image(uiImage: uiImage)
                .resizable().scaledToFill()
        } else {
            #if canImport(FamilyControls)
            if let firstToken = group.selection.applicationTokens.first {
                AppIconView(token: firstToken)
            } else if let firstCat = group.selection.categoryTokens.first {
                CategoryIconView(token: firstCat)
            } else {
                Image(systemName: "app.fill")
                    .font(.title3).foregroundStyle(frontSecondaryInk)
            }
            #else
            Image(systemName: "app.fill")
                .font(.title3).foregroundStyle(frontSecondaryInk)
            #endif
        }
    }

    private var statusPill: some View {
        Group {
            if isUnlocked {
                if let remaining = model.remainingUnlockTime(for: group.id), remaining > 0 {
                    Text(formatTime(remaining))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(frontInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.55)))
                } else {
                    Text("Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(frontInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.55)))
                }
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                    Text("Active")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(frontSecondaryInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.08)))
            }
        }
    }

    private var difficultyDots: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= group.difficultyLevel ? difficultyColor(for: group.difficultyLevel) : Color.primary.opacity(0.1))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var ticketTitle: String {
        if let templateApp = group.templateApp {
            return TargetResolver.displayName(for: templateApp)
        }
        #if canImport(FamilyControls)
        let defaults = UserDefaults(suiteName: "group.personal-project.StepsTrader") ?? .standard
        if appsCount == 1, let firstToken = group.selection.applicationTokens.first,
           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
            if let name = defaults.string(forKey: tokenKey) { return name }
        }
        #endif
        if appsCount == 0 { return "Empty Ticket" }
        return group.name.isEmpty ? "\(appsCount) \(appsCount == 1 ? "app" : "apps")" : group.name
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green; case 2: return .blue; case 3: return .orange
        case 4: return .red; case 5: return .purple; default: return .gray
        }
    }

    private func difficultyLabel(for level: Int) -> String {
        guard (1...5).contains(level) else { return "Level -" }
        return "Level \(level)"
    }

}

fileprivate enum RayDirection {
    case left
    case right
}

/// Native SwiftUI recreation of ray SVG surfaces:
/// - `ray 1`: radial shade anchored on the left
/// - `ray 2`: radial shade anchored on the right
fileprivate struct RayCapsuleSurface: View {
    let baseColor: Color
    let direction: RayDirection

    // Extracted from ray1/ray2 SVGs: 341x65 with radial stop at 0.889432.
    private let gradientStop: CGFloat = 0.889432
    private let radiusScale: CGFloat = 310.5 / 341.0

    private var center: UnitPoint {
        switch direction {
        case .left:
            return UnitPoint(x: 26.0 / 341.0, y: 32.5 / 65.0)
        case .right:
            return UnitPoint(x: 315.0 / 341.0, y: 32.5 / 65.0)
        }
    }

    private var alphaGradient: LinearGradient {
        switch direction {
        case .left:
            // Front side: bright left -> transparent right.
            return LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.75), location: 0.20),
                    .init(color: .white.opacity(0.50), location: 0.35),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .clear, location: 0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .right:
            // Back side: bright right -> transparent left.
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .white.opacity(0.50), location: 0.65),
                    .init(color: .white.opacity(0.75), location: 0.80),
                    .init(color: .white, location: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
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
                    Capsule()
                        .fill(alphaGradient)
                )
        }
    }
}

// MARK: - Ticket Shape (notched edges like a real ticket)

/// Custom shape: rounded rectangle with two semicircular notches where the stub meets the body.
/// `stubOnRight` flips the notch position for the back side of a flipped ticket.
fileprivate struct TicketShape: Shape {
    var stubOnRight = false

    func path(in rect: CGRect) -> Path {
        let cr: CGFloat = 10 // corner radius
        let nr: CGFloat = 8  // notch radius
        let stubW: CGFloat = 64
        let nx: CGFloat = stubOnRight ? rect.width - stubW : stubW

        var p = Path()

        p.move(to: CGPoint(x: cr, y: 0))

        if !stubOnRight {
            // Top edge: notch on the left side
            p.addLine(to: CGPoint(x: nx - nr, y: 0))
            p.addArc(center: CGPoint(x: nx, y: 0), radius: nr,
                      startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        p.addLine(to: CGPoint(x: stubOnRight ? nx - nr : rect.width - cr, y: 0))
        if stubOnRight {
            // Top edge: notch on the right side
            p.addArc(center: CGPoint(x: nx, y: 0), radius: nr,
                      startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: CGPoint(x: rect.width - cr, y: 0))
        }

        // Top-right corner
        p.addArc(center: CGPoint(x: rect.width - cr, y: cr), radius: cr,
                  startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - cr))
        // Bottom-right corner
        p.addArc(center: CGPoint(x: rect.width - cr, y: rect.height - cr), radius: cr,
                  startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        if stubOnRight {
            // Bottom edge: notch on the right side
            p.addLine(to: CGPoint(x: nx + nr, y: rect.height))
            p.addArc(center: CGPoint(x: nx, y: rect.height), radius: nr,
                      startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        }
        p.addLine(to: CGPoint(x: stubOnRight ? cr : nx + nr, y: rect.height))
        if !stubOnRight {
            // Bottom edge: notch on the left side
            p.addArc(center: CGPoint(x: nx, y: rect.height), radius: nr,
                      startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            p.addLine(to: CGPoint(x: cr, y: rect.height))
        }

        // Bottom-left corner
        p.addArc(center: CGPoint(x: cr, y: rect.height - cr), radius: cr,
                  startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge
        p.addLine(to: CGPoint(x: 0, y: cr))
        // Top-left corner
        p.addArc(center: CGPoint(x: cr, y: cr), radius: cr,
                  startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        p.closeSubpath()
        return p
    }
}

// MARK: - Perforation dashed line

fileprivate struct PerforationLine: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in
                var y: CGFloat = 4
                while y < geo.size.height - 4 {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: 0, y: y + 4))
                    y += 8
                }
            }
            .stroke(color, lineWidth: 1)
        }
    }
}

// MARK: - Ticket Template Picker
struct TicketTemplatePickerView: View {
    @ObservedObject var model: AppModel
    let appLanguage: String = "en"
    let onTemplateSelected: (String) -> Void
    let onCustomSelected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    private struct Template {
        let bundleId: String
        let name: String
        let imageName: String
    }
    
    private static let allTemplates: [Template] = {
        let bundleIds = [
            "com.burbn.instagram", "com.zhiliaoapp.musically", "com.google.ios.youtube",
            "com.toyopagroup.picaboo", "com.reddit.Reddit", "com.atebits.Tweetie2",
            "com.duolingo.DuolingoMobile", "com.facebook.Facebook", "com.linkedin.LinkedIn",
            "com.pinterest", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp"
        ]
        return bundleIds.compactMap { bid in
            TargetResolver.imageName(for: bid).map { imageName in
                Template(bundleId: bid, name: TargetResolver.displayName(for: bid), imageName: imageName)
            }
        }
    }()
    
    // Filter out templates that are already used
    private var availableTemplates: [Template] {
        let usedTemplateApps = Set(model.blockingStore.ticketGroups.compactMap { $0.templateApp })
        return Self.allTemplates.filter { !usedTemplateApps.contains($0.bundleId) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Custom ticket option
                    Button {
                        onCustomSelected()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.brandPink.opacity(0.15), AppColors.brandPink.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                
                                Image(systemName: "plus")
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(AppColors.brandPink)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom Ticket")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Choose your own apps")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(theme.backgroundSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(AppColors.brandPink.opacity(0.3), lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Templates section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Templates")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        if availableTemplates.isEmpty {
                            Text("All templates are already in use")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(availableTemplates, id: \.bundleId) { template in
                                    templateCard(template: template)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func templateCard(template: Template) -> some View {
        Button {
            onTemplateSelected(template.bundleId)
        } label: {
            VStack(spacing: 8) {
                // Large app icon (try exact, lowercase, capitalized so Assets names match)
                let uiImage = UIImage(named: template.imageName)
                    ?? UIImage(named: template.imageName.lowercased())
                    ?? UIImage(named: template.imageName.capitalized)
                if let uiImage = uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        )
                }
                
                Text(template.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.backgroundSecondary)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Ticket Settings (Expandable)
struct InlineTicketSettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var group: TicketGroup
    let appLanguage: String = "en"
    let onEditApps: () -> Void
    var onAfterDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isUnlocking = false
    @State private var difficultyUpdateTask: Task<Void, Never>? = nil
    @State private var showEditSettings = false
    
    private let intervals: [AccessWindow] = [.minutes10, .minutes30, .hour1]
    
    private var surface: Color { Color(.secondarySystemGroupedBackground) }
    private var separator: Color { Color(.separator) }
    private var accent: Color { TicketsPalette.accent }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Spend exp buttons - main content
            unlockButtonsSection
            
            Divider()
                .background(separator)
            
            // Edit settings - reveals difficulty + time intervals
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showEditSettings.toggle()
                }
            } label: {
                rowButtonLabel(icon: "gearshape.fill", title: "Edit settings", showChevron: true, expanded: showEditSettings, surface: surface, separator: separator)
            }
            .buttonStyle(.plain)
            
            if showEditSettings {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(separator)
                    inlineDifficultySection
                    inlineIntervalsSection
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Edit Apps
            Button {
                onEditApps()
            } label: {
                rowButtonLabel(icon: "square.grid.2x2", title: "Edit Apps", showChevron: true, expanded: false, surface: surface, separator: separator)
            }
            .buttonStyle(.plain)
            
            // Delete
            Button {
                model.deleteTicketGroup(group.id)
                onAfterDelete?()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 24)
                    Text("Delete")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(separator.opacity(0.5), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
    
    private func rowButtonLabel(icon: String, title: String, showChevron: Bool, expanded: Bool, surface: Color, separator: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(separator.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    
    // MARK: - Difficulty
    private var inlineDifficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dial.high.fill")
                    .foregroundColor(inlineDifficultyColor(for: group.difficultyLevel))
                Text("Difficulty")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(difficultyLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(inlineDifficultyColor(for: group.difficultyLevel))
            }
            
            Slider(
                value: Binding(
                    get: { Double(group.difficultyLevel) },
                    set: { newValue in
                        let newLevel = Int(newValue.rounded())
                        group.difficultyLevel = newLevel
                        difficultyUpdateTask?.cancel()
                        difficultyUpdateTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            guard !Task.isCancelled else { return }
                            model.updateTicketGroup(group)
                        }
                    }
                ),
                in: 1...5,
                step: 1
            )
            .tint(inlineDifficultyColor(for: group.difficultyLevel))
            
            HStack(spacing: 8) {
                ForEach(intervals, id: \.self) { interval in
                    if group.enabledIntervals.contains(interval) {
                        HStack(spacing: 4) {
                            Text("\(group.cost(for: interval))")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            Text("experience")
                                .font(.caption2)
                        }
                        .foregroundColor(inlineDifficultyColor(for: group.difficultyLevel))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(inlineDifficultyColor(for: group.difficultyLevel).opacity(0.15))
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(separator.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Time intervals (tariffs)
    private var inlineIntervalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time options")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            ForEach(intervals, id: \.self) { interval in
                HStack {
                    Text(unlockOptionLabel(interval))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { group.enabledIntervals.contains(interval) },
                        set: { enabled in
                            if enabled {
                                group.enabledIntervals.insert(interval)
                            } else if group.enabledIntervals.count > 1 {
                                group.enabledIntervals.remove(interval)
                            }
                            model.updateTicketGroup(group)
                        }
                    ))
                    .tint(accent)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(separator.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    private func inlineDifficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    @ViewBuilder
    private var unlockButtonsSection: some View {
        if model.isGroupUnlocked(group.id) {
            // Currently unlocked - show remaining time
            if let remaining = model.remainingUnlockTime(for: group.id) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                        .font(.title2)
                        .foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(formatRemaining(remaining)) left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(accent.opacity(0.3), lineWidth: 2)
                        )
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spend exp on")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                
                ForEach(intervals, id: \.self) { interval in
                    if group.enabledIntervals.contains(interval) {
                        quickUnlockButton(interval: interval)
                    }
                }
            }
        }
    }
    
    private func quickUnlockButton(interval: AccessWindow) -> some View {
        let cost = group.cost(for: interval)
        let canAfford = model.userEconomyStore.totalStepsBalance >= cost
        let timeLabel = unlockOptionLabel(interval)
        
        return Button {
            guard canAfford, !isUnlocking else { return }
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            Task {
                isUnlocking = true
                await model.handlePayGatePaymentForGroup(groupId: group.id, window: interval, costOverride: cost)
                isUnlocking = false
            }
        } label: {
            HStack(spacing: 12) {
                // Time label - prominent
                Text(timeLabel)
                    .font(.headline)
                    .foregroundStyle(canAfford ? Color.primary : Color.primary.opacity(0.5))
                
                Spacer()
                
                // Cost - with icon
                HStack(spacing: 4) {
                    Text("\(cost)")
                        .font(.headline)
                        .monospacedDigit()
                    Text("experience")
                        .font(.subheadline)
                }
                .foregroundStyle(canAfford ? Color.primary : Color.primary.opacity(0.5))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canAfford ? accent : surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(canAfford ? Color.clear : separator.opacity(0.5), lineWidth: 1)
                    )
            )
            .shadow(color: canAfford ? accent.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .disabled(!canAfford || isUnlocking)
        .buttonStyle(.plain)
        .opacity(canAfford ? 1.0 : 0.6)
        .scaleEffect(isUnlocking ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isUnlocking)
    }
    
    private func formatRemaining(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m):\(String(format: "%02d", s))"
    }
    
    private var difficultyLabel: String {
        let safeLevel = min(max(group.difficultyLevel, 1), 5)
        return "Level \(safeLevel)"
    }
    
    private func unlockOptionLabel(_ interval: AccessWindow) -> String {
        switch interval {
        case .minutes10: return "10 min"
        case .minutes30: return "30 min"
        case .hour1: return "1 hour"
        }
    }
}

// MARK: - Difficulty Picker View
struct DifficultyPickerView: View {
    @ObservedObject var model: AppModel
    @State var group: TicketGroup
    let appLanguage: String = "en"
    let onDone: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Choose Difficulty Level")
                            .font(.title2.weight(.bold))
                        Text("Higher difficulty means higher energy cost")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Difficulty options
                    VStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { level in
                            difficultyOption(level: level)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Cost preview
                    if group.difficultyLevel > 0 {
                        costPreviewSection
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(theme.backgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.updateTicketGroup(group)
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func difficultyOption(level: Int) -> some View {
        let isSelected = group.difficultyLevel == level
        let color = difficultyColor(for: level)
        let label = difficultyLabel(for: level)
        
        return Button {
            withAnimation {
                group.difficultyLevel = level
            }
        } label: {
            HStack(spacing: 16) {
                // Level indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? color : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(level)")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Label and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(difficultyDescription(for: level))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.1) : theme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var costPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Energy Cost Preview")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach([AccessWindow.minutes10, .minutes30, .hour1], id: \.self) { interval in
                    VStack(spacing: 4) {
                        Text(interval.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Text("\(group.cost(for: interval))")
                                .font(.subheadline.weight(.semibold))
                            Text("experience")
                                .font(.caption2)
                        }
                        .foregroundColor(difficultyColor(for: group.difficultyLevel))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(difficultyColor(for: group.difficultyLevel).opacity(0.1))
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.backgroundSecondary)
        )
    }
    
    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    private func difficultyLabel(for level: Int) -> String {
        let safeLevel = min(max(level, 1), 5)
        return "Level \(safeLevel)"
    }
    
    private func difficultyDescription(for level: Int) -> String {
        switch level {
        case 1: return "Lowest energy cost"
        case 2: return "Low energy cost"
        case 3: return "Moderate energy cost"
        case 4: return "High energy cost"
        case 5: return "Highest energy cost"
        default: return ""
        }
    }
}
