import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import Foundation

struct TicketGroupId: Identifiable {
    let id: String
}

private struct FeedUnlockOptionsBottomPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(
        value: inout [String: CGFloat],
        nextValue: () -> [String: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var selectedGroupId: TicketGroupId? = nil
    @State private var showTemplatePicker = false
    @State private var expandedSheetGroupId: TicketGroupId? = nil
    @State private var inlineExpansion = FeedInlineExpansion()
    @State private var autoScrolledTargetID: String?
    /// Unspent minutes per group id, for groups whose window is open.
    ///
    /// One poll for the whole page. Every row reads this same observation, and
    /// it refreshes on `.active` so returning from the blocked app — the most
    /// common transition in the app — shows the current number immediately.
    @State private var unspentMinutes: [String: Int] = [:]
    /// Purchased size of each active window. Together with `unspentMinutes`
    /// this determines how much yellow remains in the row.
    @State private var initialMinutes: [String: Int] = [:]

    private var buttonTint: Color { AppColors.Night.textPrimary }
    @State private var showCustomNamePrompt = false
    @State private var customTicketName = ""
    @State private var deleteHapticTick = 0
    @State private var showPickerAfterDismiss = false
    @State private var groupIdToDelete: String? = nil

    /// Single entry point for the "create new feed" buttons. Feeds are
    /// unlimited — this stays a named function so the call sites keep reading
    /// as an intent rather than a raw state flip.
    private func attemptCreateGroup() {
        showTemplatePicker = true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "Feeds"))
                            .font(.geist(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(buttonTint)

                        Spacer(minLength: 16)

                        Button {
                            attemptCreateGroup()
                        } label: {
                            Image(systemName: "plus")
                                .font(.geist(size: 17, weight: .regular))
                                .foregroundStyle(buttonTint)
                                .frame(
                                    width: FeedCardLayout.addControlDiameter,
                                    height: FeedCardLayout.addControlDiameter
                                )
                                .liquidGlassControl(in: Circle())
                        }
                        #if DEBUG
                        .coachMarkAnchor(.unlockSuccess)
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                    if visibleGroups.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, max(tabBarHeight, 50) + 20)
                    } else {
                        feedsList
                    }
                }
                .zIndex(0)

                if !reduceTransparency {
                    TextureOverlayView(texture: CanvasTexture.fromStored(canvasTextureRaw))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
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
                refreshUsageBudgets()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    refreshUsageBudgets()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Coming back from the blocked app is the transition that
                // matters most here, and it does not wait for the poll.
                if phase == .active { refreshUsageBudgets() }
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
        }
        .sensoryFeedback(.warning, trigger: deleteHapticTick)
    }

    // MARK: - Feed rows

    private var feedsList: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleGroups) { group in
                            let state = FeedRowModel.accessState(
                                remainingMinutes: unspentMinutes[group.id] ?? 0,
                                initialMinutes: initialMinutes[group.id] ?? 0
                            )
                            let canOpen = group.templateApp.map {
                                TargetResolver.canOpen(bundleId: $0)
                            } ?? false

                            let showsUnlockOptions = inlineExpansion.expandedGroupID == group.id
                                && state == .locked

                            FeedRowView(
                                model: model,
                                group: group,
                                accessState: state,
                                canOpen: canOpen,
                                showsUnlockOptions: showsUnlockOptions,
                                onTap: { handleRowTap(group: group, state: state, canOpen: canOpen) },
                                onSettings: {
                                    expandedSheetGroupId = TicketGroupId(id: group.id)
                                },
                                onDelete: {
                                    groupIdToDelete = group.id
                                },
                                onPurchased: {
                                    completeInlinePurchase(groupID: group.id)
                                }
                            )
                            .id("\(group.id)-unlock-options")
                            .background {
                                if showsUnlockOptions {
                                    GeometryReader { cardGeometry in
                                        Color.clear.preference(
                                            key: FeedUnlockOptionsBottomPreferenceKey.self,
                                            value: [
                                                group.id: cardGeometry.frame(
                                                    in: .named(FeedInlineLayout.coordinateSpaceName)
                                                ).maxY
                                            ]
                                        )
                                    }
                                }
                            }
                            #if DEBUG
                            .modifier(FirstFeedAnchor(groupId: group.id, firstId: visibleGroups.first?.id))
                            #endif
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .coordinateSpace(name: FeedInlineLayout.coordinateSpaceName)
                .safeAreaPadding(
                    .bottom,
                    max(tabBarHeight, 50) + FeedInlineLayout.tabBarClearance
                )
                .scrollIndicators(.hidden)
                .onPreferenceChange(FeedUnlockOptionsBottomPreferenceKey.self) { optionBottoms in
                    guard
                        let groupID = inlineExpansion.expandedGroupID,
                        let targetID = inlineExpansion.scrollTargetID,
                        autoScrolledTargetID != targetID,
                        let optionsBottom = optionBottoms[groupID],
                        FeedInlineLayout.needsAutoScroll(
                            optionsBottom: optionsBottom,
                            viewportHeight: viewport.size.height,
                            tabBarHeight: max(tabBarHeight, 50)
                        )
                    else { return }

                    Task { @MainActor in
                        autoScrolledTargetID = targetID
                        withAnimation(feedExpansionAnimation) {
                            proxy.scrollTo(targetID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var feedExpansionAnimation: Animation {
        .snappy(duration: 0.42, extraBounce: 0.04)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.geist(size: 34, weight: .light))
                .foregroundStyle(AppColors.brandAccent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.white.opacity(0.1)))

            VStack(spacing: 6) {
                Text(String(localized: "No feeds yet"))
                    .font(.geist(size: 20, weight: .semibold, design: .rounded))
                Text(String(localized: "Add an app to unlock it with your colors"))
                    .font(.geist(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(buttonTint.opacity(0.68))
                    .multilineTextAlignment(.center)
            }

            Button(action: attemptCreateGroup) {
                Label(String(localized: "Add a feed"), systemImage: "plus")
                    .font(.geist(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(Capsule().fill(AppColors.brandAccent))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(buttonTint)
        .padding(.horizontal, 40)
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
    private func refreshUsageBudgets() {
        var latest: [String: Int] = [:]
        var latestInitial: [String: Int] = [:]
        let defaults = UserDefaults.stepsTrader()
        for group in model.blockingStore.ticketGroups {
            let minutes = model.unspentUsageBudgetMatchingShield(for: group.id)
            guard minutes > 0 else { continue }
            latest[group.id] = minutes
            latestInitial[group.id] = max(
                defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(group.id)),
                minutes
            )
        }
        if latest != unspentMinutes { unspentMinutes = latest }
        if latestInitial != initialMinutes { initialMinutes = latestInitial }
    }

    private func handleRowTap(
        group: TicketGroup,
        state: FeedRowAccessState,
        canOpen: Bool
    ) {
        switch FeedRowModel.tapAction(for: state, canOpen: canOpen) {
        case .chooseDuration:
            withAnimation(feedExpansionAnimation) {
                autoScrolledTargetID = nil
                inlineExpansion = inlineExpansion.toggling(groupID: group.id)
            }
        case .openApp:
            if let bundleId = group.templateApp {
                AppLauncher.open(bundleId: bundleId)
            }
        case .openSettings:
            // A custom multi-app feed has no single URL scheme to launch. Its
            // row is still the timer; settings is the useful destination we
            // can address directly.
            expandedSheetGroupId = TicketGroupId(id: group.id)
        }
    }

    private var visibleGroups: [TicketGroup] {
        model.blockingStore.ticketGroups.filter { group in
            !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
        }
    }

    private func deleteAndCleanup(_ groupId: String) {
        if expandedSheetGroupId?.id == groupId { expandedSheetGroupId = nil }
        inlineExpansion = inlineExpansion.collapsing(groupID: groupId)
        model.deleteTicketGroup(groupId)
    }

    private func completeInlinePurchase(groupID: String) {
        withAnimation(feedExpansionAnimation) {
            refreshUsageBudgets()
            autoScrolledTargetID = nil
            inlineExpansion = inlineExpansion.collapsing(groupID: groupID)
        }
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
