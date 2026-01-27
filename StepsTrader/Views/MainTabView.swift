import SwiftUI

struct MainTabView: View {
    @ObservedObject var model: AppModel
    @State private var selection: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    var theme: AppTheme = .system
    @State private var selectedCategory: EnergyCategory? = nil
    @State private var showOuterWorldDetail = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StepBalanceCard(
                    remainingSteps: model.totalStepsBalance,
                    totalSteps: model.baseEnergyToday + model.bonusSteps,
                    spentSteps: model.spentStepsToday,
                    healthKitSteps: model.stepsBalance,
                    outerWorldSteps: model.outerWorldBonusSteps,
                    grantedSteps: model.serverGrantedSteps,
                    dayEndHour: model.dayEndHour,
                    dayEndMinute: model.dayEndMinute,
                    showDetails: selection == 0, // Show category details only on Shields tab
                    movePoints: model.movePointsToday,
                    rebootPoints: model.rebootPointsToday,
                    joyPoints: model.joyCategoryPointsToday,
                    baseEnergyToday: model.baseEnergyToday,
                    onMoveTap: {
                        print("🔵 MainTabView: Move tapped")
                        selectedCategory = .move
                        print("🔵 MainTabView: selectedCategory = \(selectedCategory?.rawValue ?? "nil")")
                    },
                    onRebootTap: {
                        print("🔵 MainTabView: Reboot tapped")
                        selectedCategory = .reboot
                        print("🔵 MainTabView: selectedCategory = \(selectedCategory?.rawValue ?? "nil")")
                    },
                    onJoyTap: {
                        print("🔵 MainTabView: Joy tapped")
                        selectedCategory = .joy
                        print("🔵 MainTabView: selectedCategory = \(selectedCategory?.rawValue ?? "nil")")
                    },
                    onOuterWorldTap: {
                        showOuterWorldDetail = true
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                TabView(selection: $selection) {
                    // 0: Shields (first tab)
                    AppsPageSimplified(model: model)
                        .tabItem {
                            Image(systemName: "square.grid.2x2")
                            Text(loc(appLanguage, "Shields"))
                        }
                        .tag(0)

                    // 1: Status (second tab)
                    StatusView(model: model)
                        .tabItem {
                            Image(systemName: "chart.bar.fill")
                            Text(loc(appLanguage, "Status"))
                        }
                        .tag(1)
                    
                    OuterWorldView(model: model)
                        .tabItem {
                            Image(systemName: "map.fill")
                            Text(loc(appLanguage, "Outer World"))
                        }
                        .tag(2)
                    
                    ManualsPage(model: model)
                        .tabItem {
                            Image(systemName: "questionmark.circle")
                            Text(loc(appLanguage, "Manuals"))
                        }
                        .tag(3)
                    
                    SettingsView(model: model)
                        .tabItem {
                            Image(systemName: "gear")
                            Text(loc(appLanguage, "Settings"))
                        }
                        .tag(4)
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
            .background(Color(.systemBackground))
            .sheet(item: $selectedCategory) { category in
                CategoryDetailView(
                    model: model,
                    category: category,
                    outerWorldSteps: model.outerWorldBonusSteps
                )
                .onAppear {
                    print("🟢 MainTabView: Showing CategoryDetailView for category: \(category.rawValue)")
                    print("🟢 CategoryDetailView appeared for category: \(category.rawValue)")
                }
            }
            .sheet(isPresented: $showOuterWorldDetail) {
                CategoryDetailView(
                    model: model,
                    category: nil,
                    outerWorldSteps: model.outerWorldBonusSteps
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.open.modules"))) { _ in
            selection = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenShieldSettings"))) { notification in
            print("🔧 Received OpenShieldSettings notification")
            // Navigate to shields tab (now first tab)
            selection = 0
            if let bundleId = notification.userInfo?["bundleId"] as? String {
                print("🔧 Will open shield for bundleId: \(bundleId)")
                // Post delayed notification to open specific shield
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔧 Posting OpenShieldForBundle notification")
                    NotificationCenter.default.post(
                        name: .init("OpenShieldForBundle"),
                        object: nil,
                        userInfo: ["bundleId": bundleId]
                    )
                }
            }
        }
    }
    
    private var remainingStepsToday: Int {
        max(0, Int(model.effectiveStepsToday) - model.spentStepsToday)
    }
}
