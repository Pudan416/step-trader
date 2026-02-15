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
    @State private var selection: Int = Tab.gallery.rawValue
    var theme: AppTheme = .system
    @State private var selectedCategory: EnergyCategory? = nil
    @State private var metricOverlay: MetricOverlayKind? = nil
    @State private var topCardHeight: CGFloat = 0

    private enum Tab: Int, CaseIterable {
        case gallery = 0
        case tickets = 1
        case me = 2
        case guides = 3
        case settings = 4

        var icon: String {
            switch self {
            case .tickets: return "square.grid.2x2"
            case .gallery: return "hand.point.up.left.fill"
            case .me: return "person.circle"
            case .guides: return "questionmark.circle"
            case .settings: return "gearshape"
            }
        }

        var title: String {
            switch self {
            case .tickets: return "My Tickets"
            case .gallery: return "My Gallery"
            case .me: return "Me"
            case .guides: return "Guides"
            case .settings: return "Settings"
            }
        }
        
        var shortTitle: String {
            switch self {
            case .tickets: return "Tickets"
            case .gallery: return "Gallery"
            case .me: return "Me"
            case .guides: return "Guides"
            case .settings: return "Settings"
            }
        }
        
        var accessibilityId: String {
            switch self {
            case .tickets: return "tab_tickets"
            case .gallery: return "tab_gallery"
            case .me: return "tab_me"
            case .guides: return "tab_guides"
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
                // 0: My Gallery (default) — canvas goes full-bleed behind card
                NavigationStack {
                    GalleryView(model: model, metricOverlay: $metricOverlay)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: topCardHeight)
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.gallery.rawValue)

                // 1: My Tickets
                AppsPageSimplified(model: model)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.tickets.rawValue)

                // 2: Me
                MeView(model: model)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.me.rawValue)

                // 3: Guides (same as manuals)
                ManualsPage(model: model)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.guides.rawValue)
                
                // 4: Settings
                SettingsSheet(model: model, embeddedInTab: true)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.settings.rawValue)
            }
            .environment(\.topCardHeight, topCardHeight)
            .animation(.easeInOut(duration: 0.2), value: selection)
            .safeAreaInset(edge: .bottom) {
                customTabBar
            }
            .background(Color.clear)
            .onAppear {
                model.recalculateDailyEnergy()
            }
            .sheet(item: $selectedCategory) { category in
                CategoryDetailView(model: model, category: category, outerWorldSteps: 0)
                .onAppear {
                    print("🟢 MainTabView: Showing CategoryDetailView for category: \(category.rawValue)")
                    print("🟢 CategoryDetailView appeared for category: \(category.rawValue)")
                }
            }
        }
        .overlay(alignment: .top) {
            StepBalanceCard(
                remainingSteps: model.userEconomyStore.totalStepsBalance,
                totalSteps: model.healthStore.baseEnergyToday + model.userEconomyStore.bonusSteps,
                spentSteps: model.spentStepsToday,
                healthKitSteps: model.userEconomyStore.stepsBalance,
                outerWorldSteps: 0,
                grantedSteps: model.userEconomyStore.bonusSteps,
                dayEndHour: model.dayEndHour,
                dayEndMinute: model.dayEndMinute,
                showDetails: selection == Tab.gallery.rawValue,
                stepsPoints: model.stepsPointsToday,
                sleepPoints: model.sleepPointsToday,
                bodyPoints: model.activityPointsToday,
                mindPoints: model.creativityPointsToday,
                heartPoints: model.joysCategoryPointsToday,
                baseEnergyToday: model.healthStore.baseEnergyToday,
                onStepsTap: {
                    if selection == Tab.gallery.rawValue {
                        metricOverlay = .steps
                    }
                },
                onSleepTap: {
                    if selection == Tab.gallery.rawValue {
                        metricOverlay = .sleep
                    }
                },
                onMoveTap: {
                    if selection == Tab.gallery.rawValue {
                        metricOverlay = .category(.body)
                    } else {
                        selectedCategory = .body
                    }
                },
                onRebootTap: {
                    if selection == Tab.gallery.rawValue {
                        metricOverlay = .category(.mind)
                    } else {
                        selectedCategory = .mind
                    }
                },
                onJoyTap: {
                    if selection == Tab.gallery.rawValue {
                        metricOverlay = .category(.heart)
                    } else {
                        selectedCategory = .heart
                    }
                }
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
        }
        .onPreferenceChange(TopCardHeightPreferenceKey.self) { topCardHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.open.modules"))) { _ in
            selection = Tab.tickets.rawValue
        }
        .onChange(of: selection) { _, newValue in
            if newValue != Tab.gallery.rawValue {
                metricOverlay = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenTicketSettings"))) { notification in
            print("🔧 Received OpenTicketSettings notification")
            // Navigate to tickets tab.
            selection = Tab.tickets.rawValue
            if let bundleId = notification.userInfo?["bundleId"] as? String {
                print("🔧 Will open ticket for bundleId: \(bundleId)")
                // Post delayed notification to open specific ticket
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔧 Posting OpenTicketForBundle notification")
                    NotificationCenter.default.post(
                        name: .init("OpenTicketForBundle"),
                        object: nil,
                        userInfo: ["bundleId": bundleId]
                    )
                }
            }
        }
    }

    private var customTabBar: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassTabBar
                    .background(.clear)
                    .onAppear {
                        print("🔵 Using Liquid Glass tab bar (iOS 26+)")
                    }
            } else {
                legacyTabBar
                    .onAppear {
                        print("🟠 Using legacy tab bar (iOS < 26)")
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
                        
                        Text(tab.shortTitle)
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
                        
                        Text(tab.shortTitle)
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
    
    private var remainingStepsToday: Int {
        max(0, Int(model.effectiveStepsToday) - model.spentStepsToday)
    }
}

// MARK: - Shared energy gradient + grain background (used by every tab)

struct EnergyGradientBackground: View {
    let sleepPoints: Int
    let stepsPoints: Int

    var body: some View {
        Canvas { context, size in
            drawUnifiedGradient(context: &context, size: size)
        }
        .ignoresSafeArea()
        .overlay {
            Image("grain 1")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(0.4)
                .blendMode(.overlay)
        }
    }

    private func drawUnifiedGradient(context: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width)
        let h = Double(size.height)
        let dim = min(w, h)

        let stepsNorm = Double(min(max(stepsPoints, 0), 20)) / 20.0
        let sleepNorm = Double(min(max(sleepPoints, 0), 20)) / 20.0

        let gold = Color(hex: "#FFBF65")
        let coral = Color(hex: "#FD8973")
        let navy = Color(hex: "#003A6C")
        let night = Color(hex: "#13181B")

        let goldOpacity = 0.35 + stepsNorm * 0.55
        let coralOpacity = 0.3 + stepsNorm * 0.4
        let navyOpacity = 0.3 + sleepNorm * 0.5
        let nightOpacity = 0.5 + sleepNorm * 0.5

        let center = CGPoint(x: w * 0.5, y: h * 0.5)
        let gradient = Gradient(stops: [
            .init(color: gold.opacity(goldOpacity), location: 0.0),
            .init(color: coral.opacity(coralOpacity), location: 0.25),
            .init(color: navy.opacity(navyOpacity), location: 0.55),
            .init(color: night.opacity(nightOpacity), location: 0.85),
            .init(color: night.opacity(nightOpacity), location: 1.0)
        ])

        let canvasRect = CGRect(x: 0, y: 0, width: w, height: h)
        let maxReach = max(w, h)
        context.fill(
            Path(canvasRect),
            with: .radialGradient(
                gradient,
                center: center,
                startRadius: 0,
                endRadius: maxReach * 0.7
            )
        )

        let secondaryGrad = Gradient(colors: [
            gold.opacity(goldOpacity * 0.2),
            coral.opacity(coralOpacity * 0.08),
            .clear
        ])
        let glowRadius = dim * 0.4
        let shading = GraphicsContext.Shading.radialGradient(
            secondaryGrad,
            center: center,
            startRadius: 0,
            endRadius: glowRadius
        )
        context.drawLayer { ctx in
            ctx.opacity = 0.5
            ctx.fill(
                Ellipse().path(in: CGRect(
                    x: center.x - glowRadius,
                    y: center.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )),
                with: shading
            )
        }
    }
}

