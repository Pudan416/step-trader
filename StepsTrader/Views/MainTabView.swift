import SwiftUI

struct MainTabView: View {
    @ObservedObject var model: AppModel
    @State private var selection: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    var theme: AppTheme = .system
    @State private var selectedCategory: EnergyCategory? = nil
    @State private var breakdownCategory: EnergyCategory? = nil

    private enum Tab: Int, CaseIterable {
        case tickets = 0
        case gallery = 1
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

        func title(appLanguage: String) -> String {
            switch self {
            case .tickets: return loc(appLanguage, "My Tickets")
            case .gallery: return loc(appLanguage, "My Gallery")
            case .me: return loc(appLanguage, "Me")
            case .guides: return loc(appLanguage, "Guides")
            case .settings: return loc(appLanguage, "Settings")
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

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StepBalanceCard(
                    remainingSteps: model.totalStepsBalance,
                    totalSteps: model.baseEnergyToday + model.bonusSteps,
                    spentSteps: model.spentStepsToday,
                    healthKitSteps: model.stepsBalance,
                    outerWorldSteps: 0,
                    grantedSteps: model.bonusSteps,
                    dayEndHour: model.dayEndHour,
                    dayEndMinute: model.dayEndMinute,
                    showDetails: selection == 1,
                    movePoints: model.activityPointsToday,
                    rebootPoints: model.creativityPointsToday,
                    joyPoints: model.joysCategoryPointsToday,
                    baseEnergyToday: model.baseEnergyToday,
                    onMoveTap: {
                        if selection == 1 {
                            breakdownCategory = .activity
                        } else {
                            selectedCategory = .activity
                        }
                    },
                    onRebootTap: {
                        if selection == 1 {
                            breakdownCategory = .creativity
                        } else {
                            selectedCategory = .creativity
                        }
                    },
                    onJoyTap: {
                        if selection == 1 {
                            breakdownCategory = .joys
                        } else {
                            selectedCategory = .joys
                        }
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                TabView(selection: $selection) {
                    // 0: My Tickets
                    AppsPageSimplified(model: model)
                        .tag(0)

                    // 1: My Gallery
                    NavigationStack {
                        GalleryView(model: model, breakdownCategory: $breakdownCategory)
                    }
                    .tag(1)

                    // 2: Me
                    MeView(model: model)
                        .tag(2)

                    // 3: Guides (same as manuals)
                    ManualsPage(model: model)
                        .tag(3)
                    
                    // 4: Settings
                    NavigationStack {
                        SettingsSheet(model: model, appLanguage: appLanguage, embeddedInTab: true)
                    }
                    .tag(4)
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
            .background(theme.backgroundColor)
            .safeAreaInset(edge: .bottom) {
                customTabBar
            }
            .onAppear {
                UITabBar.appearance().isHidden = true
                model.recalculateDailyEnergy()
            }
            .onDisappear {
                UITabBar.appearance().isHidden = false
            }
            .sheet(item: $selectedCategory) { category in
                CategoryDetailView(model: model, category: category, outerWorldSteps: 0)
                .onAppear {
                    print("🟢 MainTabView: Showing CategoryDetailView for category: \(category.rawValue)")
                    print("🟢 CategoryDetailView appeared for category: \(category.rawValue)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.open.modules"))) { _ in
            selection = 0
        }
        .onChange(of: selection) { _, newValue in
            if newValue != 1 {
                breakdownCategory = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenTicketSettings"))) { notification in
            print("🔧 Received OpenTicketSettings notification")
            // Navigate to tickets tab (now first tab)
            selection = 0
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
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                let isSelected = selection == tab.rawValue
                Button {
                    selection = tab.rawValue
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        if isSelected {
                            Text(tab.title(appLanguage: appLanguage))
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .padding(.horizontal, isSelected ? 14 : 10)
                    .padding(.vertical, 10)
                    .background(isSelected ? theme.backgroundSecondary : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityId)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.backgroundColor)
        .overlay(Divider(), alignment: .top)
    }
    
    private var remainingStepsToday: Int {
        max(0, Int(model.effectiveStepsToday) - model.spentStepsToday)
    }
}
