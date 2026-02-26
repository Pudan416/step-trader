import SwiftUI

// MARK: - Environment key for StepBalanceCard height

private struct TopCardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var topCardHeight: CGFloat {
        get { self[TopCardHeightKey.self] }
        set { self[TopCardHeightKey.self] = newValue }
    }
}

struct MainTabView: View {
    @ObservedObject var model: AppModel
    @State private var selection: Int = Tab.canvas.rawValue
    var theme: AppTheme = .system
    @State private var selectedCategory: EnergyCategory? = nil
    @State private var metricOverlay: MetricOverlayKind? = nil
    @State private var topCardHeight: CGFloat = 0
    @State private var isLabelMode: Bool = false
    @State private var showRaysHelp: Bool = false

    private enum Tab: Int, CaseIterable {
        case canvas = 0
        case feeds = 1
        case me = 2
        case notes = 3
        case settings = 4

        var icon: String {
            switch self {
            case .feeds: return "square.grid.2x2"
            case .canvas: return "hand.point.up.left.fill"
            case .me: return "person.circle"
            case .notes: return "book.fill"
            case .settings: return "gearshape"
            }
        }

        var title: String {
            switch self {
            case .feeds: return "Feeds"
            case .canvas: return "Canvas"
            case .me: return "Me"
            case .notes: return "Notes"
            case .settings: return "Settings"
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

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                // 0: My Canvas (default) — canvas goes full-bleed behind card
                NavigationStack {
                    GalleryView(model: model, metricOverlay: $metricOverlay, isLabelMode: $isLabelMode)
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
            .environment(\.topCardHeight, topCardHeight)
            .animation(.easeInOut(duration: 0.2), value: selection)
            .safeAreaInset(edge: .bottom) {
                if !isLabelMode {
                    customTabBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isLabelMode)
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
            if !isLabelMode {
            StepBalanceCard(
                remainingSteps: model.userEconomyStore.totalStepsBalance,
                totalSteps: model.healthStore.baseEnergyToday,
                spentSteps: model.spentStepsToday,
                healthKitSteps: model.userEconomyStore.stepsBalance,
                outerWorldSteps: 0,
                grantedSteps: 0,
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
                onRaysHelpTap: { showRaysHelp = true }
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
            if showRaysHelp {
                raysHelpOverlay
            }
        }
        .onPreferenceChange(TopCardHeightPreferenceKey.self) { topCardHeight = $0 }
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
                // Post delayed notification to open specific ticket
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    AppLogger.ui.debug("🔧 Posting OpenTicketForBundle notification")
                    NotificationCenter.default.post(
                        name: .init("OpenTicketForBundle"),
                        object: nil,
                        userInfo: ["bundleId": bundleId]
                    )
                }
            }
        }
    }

    private var raysHelpOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showRaysHelp = false }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("About rays")
                        .font(.headline)
                    Spacer()
                    Button { showRaysHelp = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("Each of the five areas — steps, sleep, body, mind and heart — contributes up to 20 rays (100 rays total).")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text("Steps and sleep come from the Health app and are the same for everyone. Body, mind and heart are activities you add by tapping the + button at the bottom of the screen.")
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
                        Image(systemName: tab.icon)
                            .font(.system(size: isSelected ? 24 : 22))
                            .fontWeight(isSelected ? .semibold : .regular)
                            .symbolRenderingMode(.hierarchical)
                        
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
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
                        Image(systemName: tab.icon)
                            .font(.system(size: isSelected ? 24 : 22))
                            .fontWeight(isSelected ? .semibold : .regular)
                            .symbolRenderingMode(.hierarchical)
                        
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityId)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// EnergyGradientBackground is now in Components/EnergyGradientBackground.swift

