import SwiftUI

// MARK: - Environment key for StepBalanceCard height

private struct TopCardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct TabBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 80
}

extension EnvironmentValues {
    var topCardHeight: CGFloat {
        get { self[TopCardHeightKey.self] }
        set { self[TopCardHeightKey.self] = newValue }
    }
    var tabBarHeight: CGFloat {
        get { self[TabBarHeightKey.self] }
        set { self[TabBarHeightKey.self] = newValue }
    }
}

struct MainTabView: View {
    @ObservedObject var model: AppModel
    // Persisted across process death within the same scene so users return to the
    // tab they last had open after a deep link or relaunch.
    @SceneStorage("selectedTab") private var selection: Int = Tab.canvas.rawValue
    // Drives the deterministic deep-link readiness signal for OpenTicketSettings.
    @State private var pendingTicketBundleId: String?
    // Bumped per delivery so repeat-same-bundleId notifications still re-fire `.task(id:)`.
    @State private var ticketDeliveryToken = UUID()
    var theme: AppTheme = .system
    @State private var selectedCategory: EnergyCategory? = nil
    @State private var metricOverlay: MetricOverlayKind? = nil
    @State private var topCardHeight: CGFloat = 0
    @State private var isWideCanvas: Bool = false
    @State private var uiTestPickerCategory: EnergyCategory? = nil
    @State private var showColorsHelp: Bool = false
    @State private var tabBarHeight: CGFloat = 0
    private let isUITest = ProcessInfo.processInfo.arguments.contains("ui-testing")
    @ScaledMetric(relativeTo: .caption2) private var tabIconSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption2) private var selectedTabIconSize: CGFloat = 24

    #if DEBUG
    @EnvironmentObject private var coachMarkManager: CoachMarkManager
    @State private var coachAnchors: [CoachMarkAnchor] = []
    #endif

    private enum Tab: Int, CaseIterable {
        case canvas = 0
        case feeds = 1
        case me = 2
        case notes = 3
        case settings = 4

        var icon: String {
            switch self {
            case .feeds: return "square.grid.2x2"
            case .canvas: return "paintbrush"
            case .me: return "person.circle"
            case .notes: return "book"
            case .settings: return "gearshape"
            }
        }

        var title: String {
            switch self {
            case .feeds: return String(localized: "Feeds", comment: "Tab bar title")
            case .canvas: return String(localized: "Canvas", comment: "Tab bar title")
            case .me: return String(localized: "Now", comment: "Tab bar title")
            case .notes: return String(localized: "Notes", comment: "Tab bar title")
            case .settings: return String(localized: "Settings", comment: "Tab bar title")
            }
        }
        
        
        var accessibilityId: String {
            switch self {
            case .feeds: return "tab_feeds"
            case .canvas: return "tab_canvas"
            case .me: return "tab_me"
            case .notes: return "tab_notes"
            case .settings: return "tab_settings"
            }
        }
    }

    // Height preference key for the StepBalanceCard overlay
    private struct TopCardHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct TabBarHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                // 0: My Canvas (default) — canvas goes full-bleed behind card
                Group {
                    if isUITest {
                        ZStack {
                            Color.clear.ignoresSafeArea()
                            VStack(spacing: 16) {
                                Spacer()
                                ForEach(EnergyCategory.allCases) { cat in
                                    Button(cat.rawValue) {
                                        uiTestPickerCategory = cat
                                    }
                                    .accessibilityIdentifier("uitest_open_\(cat.rawValue)")
                                }
                                .padding(.bottom, 40)
                            }
                        }
                        .sheet(item: $uiTestPickerCategory) { category in
                            CategoryDetailView(
                                model: model,
                                category: category,
                                outerWorldSteps: 0,
                                onActivityConfirmed: { _, _, _, _ in },
                                onActivityUndo: { _, _ in },
                                onReroll: { _, _ in }
                            )
                        }
                    } else {
                        NavigationStack {
                            GalleryView(model: model, metricOverlay: $metricOverlay, isWideCanvas: $isWideCanvas)
                                .toolbarBackground(.hidden, for: .navigationBar)
                        }
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: topCardHeight)
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.canvas.rawValue)

                // 1: My Feeds
                AppsPageSimplified(model: model)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.feeds.rawValue)
                    // Deterministic deep-link delivery: this task only fires once
                    // the feeds tab view has materialized (and any time a new
                    // pending bundleId arrives), so AppsPageSimplified has already
                    // subscribed to OpenTicketForBundle by the time we post it.
                    .task(id: ticketDeliveryToken) {
                        guard let bundleId = pendingTicketBundleId else { return }
                        AppLogger.ui.debug("🔧 Posting OpenTicketForBundle notification")
                        NotificationCenter.default.post(
                            name: .init("OpenTicketForBundle"),
                            object: nil,
                            userInfo: ["bundleId": bundleId]
                        )
                        pendingTicketBundleId = nil
                    }

                // 2: Me
                MeView(model: model)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.me.rawValue)

                // 3: Notes
                ManualsPage(model: model)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.notes.rawValue)
                
                // 4: Settings
                SettingsSheet(model: model, embeddedInTab: true)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.settings.rawValue)
            }
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .environment(\.topCardHeight, topCardHeight)
            .environment(\.tabBarHeight, tabBarHeight)
            .animation(.easeInOut(duration: 0.2), value: selection)
            .safeAreaInset(edge: .bottom) {
                if !isWideCanvas {
                    customTabBar
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TabBarHeightPreferenceKey.self, value: geo.size.height)
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isWideCanvas)
            .background(Color.clear)
            .onAppear {
                model.recalculateDailyEnergy()
            }
            .sheet(item: $selectedCategory) { category in
                CategoryDetailView(model: model, category: category, outerWorldSteps: 0)
                .onAppear {
                    AppLogger.ui.debug("🟢 MainTabView: Showing CategoryDetailView for category: \(category.rawValue)")
                    AppLogger.ui.debug("🟢 CategoryDetailView appeared for category: \(category.rawValue)")
                }
            }
        }
        .overlay(alignment: .top) {
            if !isWideCanvas {
            StepBalanceCard(
                remainingSteps: model.userEconomyStore.totalStepsBalance,
                totalSteps: model.healthStore.baseEnergyToday,
                spentSteps: model.spentStepsToday,
                healthKitSteps: model.userEconomyStore.stepsBalance,
                dayEndHour: model.dayEndHour,
                dayEndMinute: model.dayEndMinute,
                showDetails: selection == Tab.canvas.rawValue,
                stepsPoints: model.stepsPointsToday,
                sleepPoints: model.sleepPointsToday,
                bodyPoints: model.activityPointsToday,
                mindPoints: model.creativityPointsToday,
                heartPoints: model.joysCategoryPointsToday,
                baseEnergyToday: model.healthStore.baseEnergyToday,
                onStepsTap: {
                    if selection == Tab.canvas.rawValue {
                        metricOverlay = .steps
                    }
                },
                onSleepTap: {
                    if selection == Tab.canvas.rawValue {
                        metricOverlay = .sleep
                    }
                },
                onMoveTap: {
                    if selection == Tab.canvas.rawValue {
                        metricOverlay = .category(.body)
                    } else {
                        selectedCategory = .body
                    }
                },
                onRebootTap: {
                    if selection == Tab.canvas.rawValue {
                        metricOverlay = .category(.mind)
                    } else {
                        selectedCategory = .mind
                    }
                },
                onJoyTap: {
                    if selection == Tab.canvas.rawValue {
                        metricOverlay = .category(.heart)
                    } else {
                        selectedCategory = .heart
                    }
                },
                onColorsHelpTap: { showColorsHelp = true }
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: TopCardHeightPreferenceKey.self, value: geo.size.height)
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if showColorsHelp {
                colorsHelpOverlay
            }
        }
        #if DEBUG
        .onPreferenceChange(CoachMarkAnchorKey.self) { coachAnchors = $0 }
        .overlay {
            CoachMarkOverlay(manager: coachMarkManager, anchors: coachAnchors)
        }
        .onChange(of: coachMarkManager.currentStep) { _, newStep in
            guard let step = newStep,
                  let tabRaw = coachMarkManager.tabRawValue(for: step) else { return }
            if selection != tabRaw {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selection = tabRaw
                }
            }
        }
        .onAppear {
            coachMarkManager.configure {
                !model.blockingStore.ticketGroups.isEmpty
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CoachMarkManager.actionNotification)) { notification in
            if let step = notification.object as? CoachMarkStep {
                coachMarkManager.completeAction(for: step)
            }
        }
        .onChange(of: selection) { _, newValue in
            if coachMarkManager.currentStep == .tapFeedsTab && newValue == Tab.feeds.rawValue {
                coachMarkManager.completeAction(for: .tapFeedsTab)
            }
        }
        #endif
        .onPreferenceChange(TopCardHeightPreferenceKey.self) { topCardHeight = $0 }
        .onPreferenceChange(TabBarHeightPreferenceKey.self) { tabBarHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.open.modules"))) { _ in
            selection = Tab.feeds.rawValue
        }
        .onChange(of: selection) { _, newValue in
            if newValue != Tab.canvas.rawValue {
                metricOverlay = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenTicketSettings"))) { notification in
            AppLogger.ui.debug("🔧 Received OpenTicketSettings notification")
            // Navigate to feeds tab.
            selection = Tab.feeds.rawValue
            if let bundleId = notification.userInfo?["bundleId"] as? String {
                AppLogger.ui.debug("🔧 Will open ticket for bundleId: \(bundleId)")
                // Hand off to the feeds tab's `.task(id:)` which fires only once
                // AppsPageSimplified has materialized — replaces the prior 0.5s
                // asyncAfter race.
                pendingTicketBundleId = bundleId
                // Bump token so consecutive deliveries of the same bundleId still re-fire .task(id:).
                ticketDeliveryToken = UUID()
            }
        }
    }

    private var colorsHelpOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showColorsHelp = false }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "About colors", comment: "Help overlay title"))
                        .font(.headline)
                    Spacer()
                    Button { showColorsHelp = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(String(localized: "Each of the five areas — steps, sleep, body, mind and heart — contributes up to 20 colors (100 colors total)."))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(String(localized: "Steps and sleep come from the Health app and are the same for everyone. Body, mind and heart are activities you add by tapping the + button at the bottom of the screen."))
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(16)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.backgroundSecondary.opacity(0.98))
                    .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
            )
            .padding(.horizontal, 32)
        }
    }

    private var customTabBar: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassTabBar
                    .background(.clear)
                    .onAppear {
                        AppLogger.ui.debug("🔵 Using Liquid Glass tab bar (iOS 26+)")
                    }
            } else {
                legacyTabBar
                    .onAppear {
                        AppLogger.ui.debug("🟠 Using legacy tab bar (iOS < 26)")
                    }
            }
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                let isSelected = selection == tab.rawValue
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = tab.rawValue
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: isSelected ? selectedTabIconSize : tabIconSize))
                                .fontWeight(isSelected ? .light : .ultraLight)
                                .symbolRenderingMode(.hierarchical)
                            if tab == .settings && model.hasPermissionIssues {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -2)
                            }
                        }
                        
                        Text(tab.title)
                            .font(.caption2.weight(isSelected ? .regular : .light))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityId)
                #if DEBUG
                .modifier(FeedsTabCoachAnchor(tab: tab))
                #endif
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var legacyTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                let isSelected = selection == tab.rawValue
                Button {
                    selection = tab.rawValue
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: isSelected ? selectedTabIconSize : tabIconSize))
                                .fontWeight(isSelected ? .light : .ultraLight)
                                .symbolRenderingMode(.hierarchical)
                            if tab == .settings && model.hasPermissionIssues {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -2)
                            }
                        }
                        
                        Text(tab.title)
                            .font(.caption2.weight(isSelected ? .regular : .light))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityId)
                #if DEBUG
                .modifier(FeedsTabCoachAnchor(tab: tab))
                #endif
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    #if DEBUG
    private struct FeedsTabCoachAnchor: ViewModifier {
        let tab: Tab

        func body(content: Content) -> some View {
            if tab == .feeds {
                content.coachMarkAnchor(.tapFeedsTab)
            } else {
                content
            }
        }
    }
    #endif
}

// EnergyGradientBackground is now in Components/EnergyGradientBackground.swift

