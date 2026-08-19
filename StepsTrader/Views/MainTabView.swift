import SwiftUI

// MARK: - Environment key for the energy pill height

extension EnvironmentValues {
    @Entry var topCardHeight: CGFloat = 0
    @Entry var tabBarHeight: CGFloat = 80
}

struct MainTabView: View {
    @ObservedObject var model: AppModel
    // Persisted across process death within the same scene so users return to the
    // tab they last had open after a deep link or relaunch.
    @SceneStorage("selectedTab") private var storedSelection: Int = Tab.canvas.rawValue

    /// Every read and write of the current tab goes through `Tab.resolve`, so a
    /// raw value left behind by a build with more tabs can never select a page
    /// that no longer exists.
    private var selection: Int {
        get { Tab.resolve(storedRawValue: storedSelection).rawValue }
        nonmutating set { storedSelection = Tab.resolve(storedRawValue: newValue).rawValue }
    }

    private var selectionBinding: Binding<Int> {
        Binding(get: { selection }, set: { selection = $0 })
    }
    // Drives the deterministic deep-link readiness signal for OpenTicketSettings.
    @State private var pendingTicketBundleId: String?
    // Bumped per delivery so repeat-same-bundleId notifications still re-fire `.task(id:)`.
    @State private var ticketDeliveryToken = UUID()
    var theme: AppTheme = .night
    @State private var isHappeningPaletteVisible = false
    @State private var isHappeningPalettePanelVisible = false
    @State private var paletteRoute = CanvasPaletteRouteState()
    @State private var metricOverlay: MetricOverlayKind? = nil
    @State private var topCardHeight: CGFloat = 0
    @State private var isWideCanvas: Bool = false
    /// Deep-link route for the Settings sheet, driven by feature-tip CTAs.
    @State private var settingsDeepLinkRoute: FeatureTipSettingsPage?
    /// Settings is a sheet opened from Me. The host owns the flag and the route
    /// because `TabView` builds its pages lazily — a deep link that arrives
    /// before Me has ever been opened must not be delivered to a view that does
    /// not exist yet.
    @State private var showSettings = false
    @State private var tabBarHeight: CGFloat = 80
    private let isUITest = ProcessInfo.processInfo.arguments.contains("ui-testing")
    // Figma menu tabs (475:64): icon ≈ 2× label height, label ≈ caption.
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @ScaledMetric(relativeTo: .caption2) private var tabIconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var selectedTabIconSize: CGFloat = 26
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(CoachMarkManager.self) private var coachMarkManager
    @State private var coachAnchors: [CoachMarkAnchor] = []

    enum Tab: Int, CaseIterable {
        case canvas = 0
        case feeds = 1
        case me = 2

        var icon: String {
            switch self {
            case .feeds: return "square.grid.2x2"
            case .canvas: return "scribble.variable"
            case .me: return "person.circle"
            }
        }

        var title: String {
            switch self {
            case .feeds: return String(localized: "Feeds", comment: "Tab bar title")
            case .canvas: return String(localized: "Canvas", comment: "Tab bar title")
            case .me: return String(localized: "Me", comment: "Tab bar title")
            }
        }


        var accessibilityId: String {
            switch self {
            case .feeds: return "tab_feeds"
            case .canvas: return "tab_canvas"
            case .me: return "tab_me"
            }
        }

        /// `@SceneStorage` persists a raw Int across app updates. Values written
        /// by builds that had more tabs (3 = History, 4 = Settings) no longer
        /// resolve, so anything unknown falls back to the canvas.
        static func resolve(storedRawValue: Int) -> Tab {
            Tab(rawValue: storedRawValue) ?? .canvas
        }
    }

    private var tabTint: Color { AppColors.Night.textPrimary }

    private var hidesSurroundingChromeForPalette: Bool {
        HappeningPaletteChromeLayout.hidesSurroundingChrome(
            isPalettePresented: isHappeningPaletteVisible,
            isPanelPresented: isHappeningPalettePanelVisible,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var task7AccessibilityConfigurationValue: String {
        let contrast = Task7UITestAccessibilityConfiguration.current.usesIncreasedContrast
            ? "increased-contrast"
            : "standard-contrast"
        return "\(Task7UITestAccessibilityConfiguration.name(for: dynamicTypeSize)),\(contrast)"
    }

    // Height preference key for the energy pill overlay
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
            TabView(selection: selectionBinding) {
                // 0: My Canvas (default) — canvas goes full-bleed behind card
                Group {
                    NavigationStack {
                        GalleryView(
                            model: model,
                            metricOverlay: $metricOverlay,
                            isWideCanvas: $isWideCanvas,
                            paletteRoute: $paletteRoute,
                            isCanvasSelected: selection == Tab.canvas.rawValue,
                            onPalettePresentationChange: { isPresented in
                                isHappeningPaletteVisible = isPresented
                                if !isPresented {
                                    isHappeningPalettePanelVisible = false
                                }
                            },
                            onPalettePanelPresentationChange: { isPresented in
                                isHappeningPalettePanelVisible = isPresented
                            }
                        )
                            .toolbarBackground(.hidden, for: .navigationBar)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: topCardHeight)
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.canvas.rawValue)
                .environment(\.renderingIsActive, selection == Tab.canvas.rawValue)

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
                    .environment(\.renderingIsActive, selection == Tab.feeds.rawValue)

                // 2: Me
                MeView(model: model, onOpenSettings: { showSettings = true })
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.me.rawValue)
                    .environment(\.renderingIsActive, selection == Tab.me.rawValue)
            }

            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .environment(\.topCardHeight, topCardHeight)
            .environment(\.tabBarHeight, tabBarHeight)
            .animation(.easeInOut(duration: 0.2), value: selection)
            // Feature-tip CTA deep-link: Settings is a sheet on Me now. Set the
            // route BEFORE presenting — SettingsSheet reads the binding when it
            // is first created and pushes via navigationDestination on appear.
            // Owning both here (not in MeView) means the link works even if Me
            // has never been visited, since TabView builds its pages lazily.
            // Posted by FeatureTipSheet.
            .onReceive(NotificationCenter.default.publisher(for: .openFeatureTipSettings)) { note in
                settingsDeepLinkRoute = (note.userInfo?["page"] as? String)
                    .flatMap(FeatureTipSettingsPage.init(rawValue:))
                withAnimation { selection = Tab.me.rawValue }
                guard !showSettings else { return }
                // The poster (FeatureTipSheet) is itself a sheet and calls
                // dismiss() immediately before posting. Presenting on top of a
                // dismissal already in flight gets dropped by UIKit, so wait for
                // it to finish — the same reason the tab version deferred its push.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    showSettings = true
                }
            }
            // Use overlay (not safeAreaInset) so page content extends fully
            // behind the bar — gives the Liquid Glass lens something to refract.
            // Each tab page should add `.safeAreaPadding(.bottom, tabBarHeight)`
            // (or read \.tabBarHeight) on its scrollable content so the last
            // row can scroll past the pill.
            .overlay(alignment: .bottom) {
                if !isWideCanvas, !hidesSurroundingChromeForPalette {
                    customTabBar
                        .allowsHitTesting(
                            !CanvasPaletteRouteState.blocksTabBar(
                                isCanvasSelected: selection == Tab.canvas.rawValue,
                                isPaletteVisible: isHappeningPaletteVisible
                            )
                        )
                        .accessibilityHidden(
                            CanvasPaletteRouteState.blocksTabBar(
                                isCanvasSelected: selection == Tab.canvas.rawValue,
                                isPaletteVisible: isHappeningPaletteVisible
                            )
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TabBarHeightPreferenceKey.self, value: geo.size.height)
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isWideCanvas)
            .overlay {
                if selection == Tab.feeds.rawValue {
                    TextureOverlayView(texture: CanvasTexture.fromStored(canvasTextureRaw))
                        .transaction { $0.animation = nil }
                }
            }
            .background(Color.clear)
            .onAppear {
                model.recalculateDailyEnergy()
            }

            if ProcessInfo.processInfo.arguments.contains("ui-testing-task7") {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("task7_accessibility_configuration")
                    .accessibilityLabel("Task 7 accessibility configuration")
                    .accessibilityValue(task7AccessibilityConfigurationValue)

                // XCUITest cannot synthesise a device shake, so the fixture
                // fires the notification the window would have posted. Gated on
                // the environment variable, so it cannot exist in a shipping
                // build.
            }
        }
        .overlay(alignment: .top) {
            // Me is where you look back, not where you check your balance — the
            // pill is drawn on canvas and feeds only.
            if !isWideCanvas, !hidesSurroundingChromeForPalette, selection != Tab.me.rawValue {
                CanvasEnergyStatusPill(
                    status: CanvasEnergyStatus(
                        stepsBalance: model.userEconomyStore.stepsBalance,
                        baseEnergyToday: model.healthStore.baseEnergyToday
                    )
                )
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: TopCardHeightPreferenceKey.self, value: geo.size.height)
                    }
                )
                .coachMarkAnchor(.colorBalance)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Settings left the tab bar; `embeddedInTab` defaults to false, which
        // drops the topCardHeight inset the tab version needed.
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model, featureTipRouteBinding: $settingsDeepLinkRoute)
        }
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
        .onPreferenceChange(TopCardHeightPreferenceKey.self) { value in
            guard value != topCardHeight else { return }
            topCardHeight = value
        }
        .onPreferenceChange(TabBarHeightPreferenceKey.self) { value in
            guard value != tabBarHeight else { return }
            tabBarHeight = value
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.open.modules"))) { _ in
            selection = Tab.feeds.rawValue
        }
        .onChange(of: selection) { _, newValue in
            if newValue != Tab.canvas.rawValue {
                metricOverlay = nil
                paletteRoute.cancelPendingRequest()
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

    private var customTabBar: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassTabBar
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

    // Figma 475:64 — translucent pill-shaped floating tab bar with white
    // outline icons + labels. Selection state uses opacity rather than color
    // shift to stay on-design over the energy gradient background.
    @available(iOS 26.0, *)
    private var liquidGlassTabBar: some View {
        GlassEffectContainer(spacing: 8) {
            tabBarItems(animated: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // Tab bar follows the global cycling shimmer tint via
                // `liquidGlassControl(in:)` — same effect as `.glassEffect(.clear.interactive())`
                // but reads `\.glassShimmerColor` from the env so it slowly cycles.
                .liquidGlassControl(in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var legacyTabBar: some View {
        tabBarItems(animated: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .liquidGlassControl(in: Capsule(style: .continuous))
            .clipShape(Capsule(style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tabBarItems(animated: Bool) -> some View {
        // Fixed spacing, not a distributed one: with three destinations left,
        // stretching each item to an equal share of the screen leaves the icons
        // marooned at the edges of a bar that spans the whole width.
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                let isSelected = selection == tab.rawValue
                Button {
                    if animated {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selection = tab.rawValue
                        }
                    } else {
                        selection = tab.rawValue
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(
                                    size: isSelected ? selectedTabIconSize : tabIconSize,
                                    weight: isSelected ? .semibold : .regular
                                ))
                                .symbolRenderingMode(.monochrome)
                                // Pin every glyph to a fixed-height slot so symbols
                                // with differing intrinsic heights (and the 24→26pt
                                // selection bump) don't shift the label baseline.
                                .frame(height: selectedTabIconSize, alignment: .center)
                            // Settings is a button on Me now, so the permission
                            // warning dot follows it there.
                            if tab == .me && model.hasPermissionIssues {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -2)
                            }
                        }

                        Text(tab.title)
                            .font(.caption2.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(tabTint.opacity(isSelected ? 1.0 : 0.75))
                    // A minimum, so the pill hugs its contents while every item
                    // keeps a tap target wider than the 44pt floor.
                    .frame(minWidth: 56)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityId)
                .modifier(FeedsTabCoachAnchor(tab: tab))
            }
        }
    }

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
}

#Preview {
    MainTabView(model: DIContainer.shared.makeAppModel())
        .environment(CoachMarkManager())
}

// EnergyGradientBackground is now in Components/EnergyGradientBackground.swift

// MARK: - Liquid Glass control modifier

extension View {
    /// Applies the same Liquid Glass treatment as the floating tab bar.
    /// Tint follows the global cycling shimmer color by default.
    ///
    /// - `.lens` (default): `.clear.interactive()` — strong refraction +
    ///   specular sheen, best for floating chrome over rich content.
    /// - `.frosted`: `.regular` — material backdrop, better for legibility
    ///   when the control contains text.
    ///
    /// Pass any `InsettableShape` (`Circle()`, `Capsule()`,
    /// `RoundedRectangle(...)`).
    func liquidGlassControl<S: InsettableShape>(
        in shape: S,
        style: LiquidGlassStyle = .lens,
        tint: GlassTint = .auto
    ) -> some View {
        modifier(LiquidGlassControlModifier(shape: shape, style: style, tint: tint))
    }
}

private struct LiquidGlassControlModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let style: LiquidGlassStyle
    let tint: GlassTint

    @Environment(\.glassShimmerColor) private var shimmerColor

    private var resolvedTint: Color? {
        switch tint {
        case .auto:         return shimmerColor
        case .off:          return nil
        case .fixed(let c): return c
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let t = resolvedTint
        if #available(iOS 26.0, *) {
            switch style {
            case .lens, .lensTinted:
                content.glassEffect(makeTintedLensGlass(tint: t), in: shape)
            case .frosted:
                content.glassEffect(makeTintedFrostedGlass(tint: t), in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    if let t {
                        shape.fill(t.opacity(AppGlassTint.fallbackStrength))
                    }
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}
