import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import Foundation

struct TicketGroupId: Identifiable {
    let id: String
}

/// Single accent for primary actions (Create Ticket, unlock). Rest uses system colors.
enum TicketsPalette {
    // Accent yellow: #FFD369
    static let accent = AppColors.brandAccent

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
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var selectedGroupId: TicketGroupId? = nil
    @State private var showTemplatePicker = false
    @State private var expandedSheetGroupId: TicketGroupId? = nil
    /// Which group's tile is selected in the dock. Distinct from
    /// `selectedGroupId`, which tracks the group being edited via the
    /// `FamilyActivityPicker` sheet — conflating the two breaks group editing.
    @State private var selectedFeedGroupId: String? = nil
    /// Unspent minutes per group id, for groups whose window is open.
    ///
    /// One poll for the whole page. The tile and the surface used to keep
    /// their own 15s loops, which drifted: after a purchase the surface showed
    /// a running timer above a tile that still looked locked, for up to 15
    /// seconds. They now read this, and it refreshes on `.active` so returning
    /// from the blocked app — the most common transition in the app — shows
    /// the current number immediately.
    @State private var unspentMinutes: [String: Int] = [:]

    private var buttonTint: Color { AppColors.Night.textPrimary }
    @State private var showCustomNamePrompt = false
    @State private var customTicketName = ""
    @State private var deleteHapticTick = 0
    @State private var showPickerAfterDismiss = false
    @State private var groupIdToDelete: String? = nil
    @State private var showPaywall = false

    /// Centralized gate for the "create new feed" entry points. Free users get
    /// a paywall once they've already created their allotted group(s); Pro
    /// users (and grandfathered legacy users) bypass the check entirely.
    private func attemptCreateGroup() {
        let canAdd = SubscriptionGate.canAddBlockingGroup(
            isPro: model.isPro,
            currentCount: model.blockingStore.ticketGroups.count
        )
        if canAdd {
            showTemplatePicker = true
        } else {
            showPaywall = true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "My Feeds", comment: "Feeds page title"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            attemptCreateGroup()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(buttonTint)
                                .frame(width: 44, height: 44)
                                .liquidGlassControl(in: Circle())
                        }
                        #if DEBUG
                        .coachMarkAnchor(.unlockSuccess)
                        #endif
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                    if model.blockingStore.ticketGroups.isEmpty {
                        emptyTicketsContent
                    } else {
                        FeedsSurfaceView(
                            model: model,
                            selectedGroup: selectedFeedGroupId,
                            unspentMinutes: selectedFeedGroupId.flatMap { unspentMinutes[$0] } ?? 0,
                            onBudgetChanged: refreshUnspentMinutes,
                            onSettings: { groupId in
                                expandedSheetGroupId = TicketGroupId(id: groupId)
                            },
                            onDelete: { groupId in
                                groupIdToDelete = groupId
                            }
                        )
                        // The surface fits itself to what it is offered (see
                        // `FeedsSurfaceView.designSize`); this keeps the
                        // design's 3pt side margins on a 393pt phone and lets
                        // it shrink rather than overflow on a narrower one.
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        dock
                            .padding(.top, 7)
                            .padding(.bottom, max(tabBarHeight, 50) + 20)
                    }
                }
                .zIndex(0)

                Image("grain (small)")
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
            .energyGradientBackground(model: model, showGrain: false)
            .background(Color.clear)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $expandedSheetGroupId, onDismiss: {
                if showPickerAfterDismiss {
                    showPickerAfterDismiss = false
                    showPicker = true
                }
            }) { groupId in
                if model.blockingStore.ticketGroups.contains(where: { $0.id == groupId.id }) {
                    let groupBinding = Binding<TicketGroup>(
                        get: {
                            guard let group = model.blockingStore.ticketGroups.first(where: { $0.id == groupId.id }) else {
                                return TicketGroup(name: "", settings: AppUnlockSettings(entryCostSteps: 10, dayPassCostSteps: 100))
                            }
                            return group
                        },
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
                                showPicker = false; selectedGroupId = nil
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
                Text(String(localized: "Family Controls not available")).padding()
                #endif
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
                        customTicketName = ""
                        showCustomNamePrompt = true
                    }
                )
            }
            .onAppear { selection = model.appSelection }
            .task {
                // The honest signal steps once a minute (the monitor
                // extension's per-minute tick). Poll a little faster so
                // nothing on the page is badly stale; never interpolate
                // between ticks.
                refreshUnspentMinutes()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    refreshUnspentMinutes()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Coming back from the blocked app is the transition that
                // matters most here, and it does not wait for the poll.
                if phase == .active { refreshUnspentMinutes() }
            }
            .alert(String(localized: "Name your feed"), isPresented: $showCustomNamePrompt) {
                TextField(String(localized: "e.g. Social, Games…", comment: "Placeholder for feed name"), text: $customTicketName)
                Button(String(localized: "Create")) {
                    let name = customTicketName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let group = model.createTicketGroup(
                        name: name.isEmpty ? String(localized: "New Feed") : name,
                        stickerThemeIndex: 0
                    )
                    selection = FamilyActivitySelection()
                    selectedGroupId = TicketGroupId(id: group.id)
                    showPicker = true
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .alert(String(localized: "Delete this feed?"), isPresented: Binding(
                get: { groupIdToDelete != nil },
                set: { if !$0 { groupIdToDelete = nil } }
            )) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let id = groupIdToDelete {
                        deleteHapticTick &+= 1
                        deleteAndCleanup(id)
                    }
                    groupIdToDelete = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    groupIdToDelete = nil
                }
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(
                    model: model,
                    store: model.subscriptionStore,
                    source: .feature
                )
            }
        }
        .sensoryFeedback(.warning, trigger: deleteHapticTick)
    }

    // MARK: - Dock

    /// A horizontal row of one tile per group, plus a trailing add tile.
    /// Scrolls when the tiles overflow the width; the add tile is always last.
    private var dock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(visibleGroups) { group in
                    FeedTileView(
                        group: group,
                        isSelected: selectedFeedGroupId == group.id,
                        remainingMinutes: unspentMinutes[group.id] ?? 0,
                        onTap: { selectedFeedGroupId = group.id }
                    )
                    #if DEBUG
                    .modifier(FirstFeedAnchor(groupId: group.id, firstId: visibleGroups.first?.id))
                    #endif
                }
                FeedAddTileView(onTap: attemptCreateGroup)
            }
            .padding(.horizontal, 9)
        }
    }

    // MARK: - Empty state
    private var emptyTicketsContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "ticket")
                .font(.system(size: 52, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .opacity(0.55)
            VStack(spacing: 8) {
                Text(String(localized: "No feeds connected yet"))
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.primary)
                Text(String(localized: "Create one when you're ready."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button {
                attemptCreateGroup()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .ultraLight))
                    Text(String(localized: "New Feed"))
                        .font(.system(size: 15, weight: .light, design: .rounded))
                }
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
            }
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
                        showPickerAfterDismiss = true
                        expandedSheetGroupId = nil
                    },
                    onAfterDelete: onDismiss
                )
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle(group.wrappedValue.name.isEmpty ? String(localized: "Feed") : group.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            // Let the system render the nav bar background — on iOS 26 this
            // becomes Liquid Glass automatically; pre-26 it's translucent
            // material. Explicit color was flattening it into a solid bar.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { onDismiss() }
                }
            }
        }
    }

    /// Re-reads every group's open window. Only groups with an open window get
    /// an entry, so the map stays small and `?? 0` is the locked case.
    private func refreshUnspentMinutes() {
        var latest: [String: Int] = [:]
        for group in model.blockingStore.ticketGroups {
            let minutes = model.unspentUsageBudgetMatchingShield(for: group.id)
            if minutes > 0 { latest[group.id] = minutes }
        }
        if latest != unspentMinutes { unspentMinutes = latest }
    }

    private var visibleGroups: [TicketGroup] {
        model.blockingStore.ticketGroups.filter { group in
            !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
        }
    }

    private func deleteAndCleanup(_ groupId: String) {
        if expandedSheetGroupId?.id == groupId { expandedSheetGroupId = nil }
        if selectedFeedGroupId == groupId { selectedFeedGroupId = nil }
        model.deleteTicketGroup(groupId)
    }
}

#if DEBUG
private struct FirstFeedAnchor: ViewModifier {
    let groupId: String
    let firstId: String?
    func body(content: Content) -> some View {
        if groupId == firstId {
            content.coachMarkAnchor(.feedsExplain)
        } else {
            content
        }
    }
}

#Preview {
    AppsPageSimplified(model: DIContainer.shared.makeAppModel())
}
#endif
