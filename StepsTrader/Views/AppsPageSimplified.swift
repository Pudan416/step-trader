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
    // Daily accent shared with Canvas and PayGate.
    static var accent: Color { AppColors.brandAccent }

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
    @Environment(\.canvasChromePalette) private var palette
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var selectedGroupId: TicketGroupId? = nil
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
    /// this determines how much pigment remains in the row.
    @State private var initialMinutes: [String: Int] = [:]

    private var buttonTint: Color { theme.textPrimary }
    @State private var deleteHapticTick = 0
    @State private var showPickerAfterDismiss = false
    @State private var groupIdToDelete: String? = nil
    @State private var pickerOperation: CanvasTourOperation?
    @State private var requestingTourAccess = false
    @State private var pickerCommitted = false
    @State private var pickerDismissalPending = false
    @State private var pickerPresentedForTour = false
    @State private var settingsTourSessionID: UUID?
    @State private var tourAuthorizationTask: Task<Void, Never>?

    /// Single entry point for the "create new feed" buttons. Feeds are
    /// unlimited — this stays a named function so the call sites keep reading
    /// as an intent rather than a raw state flip.
    private func attemptCreateGroup() {
        selection = FamilyActivitySelection()
        selectedGroupId = nil
        if CanvasTour.shared.isActive {
            guard !requestingTourAccess, !showPicker, !pickerDismissalPending else { return }
            pickerCommitted = false
            guard let operation = CanvasTour.shared.beginOperation("appSelection", returnContext: tourReturnContext) else { return }
            pickerOperation = operation
            if !model.blockingStore.isAuthorized {
                requestingTourAccess = true
                CanvasTour.shared.sheetPresented("screenTimeAuthorization", returnContext: tourReturnContext)
                tourAuthorizationTask = Task { @MainActor in
                    do {
                        try await model.blockingStore.requestAuthorization()
                        guard !Task.isCancelled, CanvasTour.shared.isCurrent(operation) else { return }
                        requestingTourAccess = false
                        CanvasTour.shared.sheetDismissed("screenTimeAuthorization", sessionID: operation.sessionID)
                        restoreSetupContextIfNeeded(sessionID: operation.sessionID)
                        guard model.blockingStore.isAuthorized else {
                            pickerOperation = nil
                            CanvasTour.shared.recover("App access is needed. Try again or skip this section.")
                            return
                        }
                        guard let pickerToken = CanvasTour.shared.beginOperation("appSelection", returnContext: tourReturnContext) else { return }
                        pickerOperation = pickerToken
                        showPicker = true
                    } catch {
                        guard !Task.isCancelled, CanvasTour.shared.isCurrent(operation) else { return }
                        requestingTourAccess = false
                        CanvasTour.shared.sheetDismissed("screenTimeAuthorization", sessionID: operation.sessionID)
                        pickerOperation = nil
                        restoreSetupContextIfNeeded(sessionID: operation.sessionID)
                        CanvasTour.shared.recover("App access was not granted. Try again or skip this section.")
                    }
                }
                return
            }
        }
        showPicker = true
    }

    private var tourReturnContext: String { CanvasTour.shared.step == .setup ? "setup" : "flow" }

    private func restoreSetupContextIfNeeded(sessionID: UUID) {
        if CanvasTour.shared.isActive, CanvasTour.shared.sessionID == sessionID,
           CanvasTour.shared.step == .setup {
            CanvasTour.shared.sheetPresented("setup", returnContext: "setup")
        }
    }

    private func dismissStaleTourPresentation() {
        let tour = CanvasTour.shared
        if let operation = pickerOperation, !tour.isActive || operation.sessionID != tour.sessionID {
            tourAuthorizationTask?.cancel()
            tourAuthorizationTask = nil
            requestingTourAccess = false
            showPickerAfterDismiss = false
            if pickerPresentedForTour || showPicker {
                pickerDismissalPending = true
                showPicker = false
            } else if !pickerDismissalPending {
                pickerOperation = nil
            }
        }
        if let owner = settingsTourSessionID, !tour.isActive || owner != tour.sessionID {
            showPickerAfterDismiss = false
            expandedSheetGroupId = nil
        }
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
                                .foregroundStyle(palette.textColor)
                                .frame(
                                    width: FeedCardLayout.addControlDiameter,
                                    height: FeedCardLayout.addControlDiameter
                                )
                                .canvasChromeSurface(in: Circle())
                        }
                        .accessibilityLabel(String(localized: "Add apps"))
                        .accessibilityIdentifier("feed.add")
                        .canvasTourControl("feeds.add")
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

            }
            .todayCanvasBackground(matchesCanvas: true)
            .background(Color.clear)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $expandedSheetGroupId, onDismiss: {
                if let owner = settingsTourSessionID {
                    CanvasTour.shared.sheetDismissed("feedSettings", sessionID: owner)
                    restoreSetupContextIfNeeded(sessionID: owner)
                    if !CanvasTour.shared.isActive || CanvasTour.shared.sessionID != owner {
                        showPickerAfterDismiss = false
                    }
                    settingsTourSessionID = nil
                }
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
                        .onAppear {
                            if CanvasTour.shared.isActive, settingsTourSessionID == nil {
                                settingsTourSessionID = CanvasTour.shared.sessionID
                                CanvasTour.shared.sheetPresented("feedSettings", returnContext: tourReturnContext)
                            }
                        }
                }
            }
            .sheet(isPresented: $showPicker, onDismiss: {
                selectedGroupId = nil
                if let owner = pickerOperation?.sessionID {
                    CanvasTour.shared.sheetDismissed("appPicker", sessionID: owner)
                    restoreSetupContextIfNeeded(sessionID: owner)
                }
                pickerOperation = nil
                pickerDismissalPending = false
                pickerPresentedForTour = false
            }) {
                NewAppGroupSheet(
                    selection: selection,
                    name: selectedGroupId.flatMap { id in
                        model.blockingStore.ticketGroups.first { $0.id == id.id }?.name
                    } ?? ""
                ) { selection, name in
                    guard selection.hasGroupTargets else { return }
                    guard !pickerCommitted else { return }
                    if let pickerOperation {
                        guard CanvasTour.shared.isCurrent(pickerOperation) else { return }
                        if let editingID = selectedGroupId?.id {
                            guard let existing = model.blockingStore.ticketGroups.first(where: { $0.id == editingID }),
                                  existing.selection == self.selection else {
                                CanvasTour.shared.endOperation(pickerOperation, error: "This feed changed while you were choosing apps. Open it again to edit the current selection.")
                                return
                            }
                        }
                    }
                    pickerCommitted = true
                    let savedGroupID: String
                    if let id = selectedGroupId,
                       var group = model.blockingStore.ticketGroups.first(where: { $0.id == id.id }) {
                        if group.selection != selection { group.templateApp = nil }
                        group.selection = selection
                        group.name = name
                        model.updateTicketGroup(group)
                        savedGroupID = group.id
                    } else {
                        savedGroupID = model.createTicketGroup(name: name, selection: selection, stickerThemeIndex: 0).id
                    }
                    if let pickerOperation, CanvasTour.shared.isCurrent(pickerOperation),
                       model.blockingStore.ticketGroups.contains(where: { $0.id == savedGroupID && $0.selection.hasGroupTargets }) {
                        CanvasTour.shared.send(.appSelectionCommitted(savedGroupID), token: pickerOperation)
                    }
                }
                .canvasTourExitChrome(context: "appPicker")
                .onAppear {
                    if CanvasTour.shared.isActive, pickerOperation == nil {
                        pickerOperation = CanvasTour.shared.beginOperation("appSelection", returnContext: tourReturnContext)
                    }
                    if let pickerOperation, CanvasTour.shared.isCurrent(pickerOperation) {
                        pickerPresentedForTour = true
                        CanvasTour.shared.sheetPresented("appPicker", returnContext: tourReturnContext)
                    }
                }
            }
            .onChange(of: showPicker) { _, presented in
                if presented { pickerCommitted = false }
                else if pickerPresentedForTour { pickerDismissalPending = true }
            }
            .onChange(of: CanvasTour.shared.sessionID) { _, _ in dismissStaleTourPresentation() }
            .onChange(of: CanvasTour.shared.isActive) { _, _ in dismissStaleTourPresentation() }
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
                    LazyVStack(spacing: 20) {
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
                                    guard !CanvasTour.shared.isActive || CanvasTour.shared.step == .setup else { return }
                                    expandedSheetGroupId = TicketGroupId(id: group.id)
                                },
                                onDelete: {
                                    guard !CanvasTour.shared.isActive || CanvasTour.shared.step == .setup else { return }
                                    groupIdToDelete = group.id
                                },
                                onPurchased: {
                                    completeInlinePurchase(groupID: group.id)
                                }
                            )
                            .id("\(group.id)-unlock-options")
                            .onChange(of: showsUnlockOptions) { _, expanded in
                                if expanded { CanvasTour.shared.send(.groupOpened(group.id)) }
                            }
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
                .foregroundStyle(theme.isLightTheme ? palette.surfaceColor : palette.accentColor)
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
                Label(String(localized: "Add apps"), systemImage: "plus")
                    .font(.geist(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.onAccentColor)
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(Capsule().fill(palette.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed.addDuplicate")
            .canvasTourControl("feeds.addDuplicate")
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
            .todayCanvasBackground(detail: true)
            .navigationTitle(group.wrappedValue.name.isEmpty ? String(localized: "Feed") : group.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            // Let the system render the nav bar background — on iOS 26 this
            // becomes Liquid Glass automatically; pre-26 it's translucent
            // material. Explicit color was flattening it into a solid bar.
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppGroupTitle(identity: group.wrappedValue.displayIdentity)
                        .font(.headline)
                }
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
        let tour = CanvasTour.shared
        if tour.isActive {
            guard let current = model.blockingStore.ticketGroups.first(where: { $0.id == group.id }),
                  current.selection.hasGroupTargets, current.selection == group.selection else {
                tour.revalidate(groupIDs: Set(visibleGroups.map(\.id)))
                tour.recover("This feed changed. Choose an available feed again.")
                return
            }
        }
        if tour.isActive, tour.step == .addApps, group.selection.hasGroupTargets {
            // Reusing a group selects its identity; the next teaching step
            // still waits for a fresh user tap to disclose its durations.
            inlineExpansion = inlineExpansion.collapsing(groupID: group.id)
            tour.send(.appSelectionCommitted(group.id))
            return
        }
        if tour.isActive, tour.step == .selectFeed,
           tour.selectedGroupID == group.id,
           model.unspentUsageBudgetMatchingShield(for: group.id) > 0 {
            guard model.blockingStore.isAuthorized else {
                tour.recover("App access is needed before this feed can be unlocked. Skip this section or check Your setup.")
                return
            }
            tour.send(.groupOpened(group.id))
            tour.send(.unlockSucceeded(group.id))
            return
        }
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
#Preview {
    AppsPageSimplified(model: DIContainer.shared.makeAppModel())
}
#endif
