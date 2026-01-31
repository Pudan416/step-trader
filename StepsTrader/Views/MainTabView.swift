import SwiftUI

struct MainTabView: View {
    @ObservedObject var model: AppModel
    @State private var selection: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    var theme: AppTheme = .system
    @State private var selectedCategory: EnergyCategory? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StepBalanceCard(
                    remainingSteps: model.totalStepsBalance,
                    totalSteps: model.baseEnergyToday + model.bonusSteps,
                    spentSteps: model.spentStepsToday,
                    healthKitSteps: model.stepsBalance,
                    dayEndHour: model.dayEndHour,
                    dayEndMinute: model.dayEndMinute,
                    showDetails: selection == 1,
                    movePoints: model.activityPointsToday,
                    rebootPoints: model.recoveryPointsToday,
                    joyPoints: model.joysCategoryPointsToday,
                    baseEnergyToday: model.baseEnergyToday,
                    onMoveTap: selection == 1 ? nil : {
                        selectedCategory = .activity
                    },
                    onRebootTap: selection == 1 ? nil : {
                        selectedCategory = .recovery
                    },
                    onJoyTap: selection == 1 ? nil : {
                        selectedCategory = .joys
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                TabView(selection: $selection) {
                    // 0: Shields
                    AppsPageSimplified(model: model)
                        .tabItem {
                            Image(systemName: "square.grid.2x2")
                            Text(loc(appLanguage, "Shields"))
                        }
                        .tag(0)

                    // 1: Choice
                    NavigationStack {
                        ChoiceView(model: model)
                    }
                    .tabItem {
                        Image(systemName: "hand.point.up.left.fill")
                        Text(loc(appLanguage, "Choices"))
                    }
                    .tag(1)

                    // 2: Resistance (center tab)
                    NavigationStack {
                        ResistanceView(model: model)
                    }
                    .tabItem {
                        Image(systemName: "person.3.fill")
                        Text(loc(appLanguage, "Resistance"))
                    }
                    .tag(2)
                    
                    // 3: Manuals
                    ManualsPage(model: model)
                        .tabItem {
                            Image(systemName: "questionmark.circle")
                            Text(loc(appLanguage, "Manuals"))
                        }
                        .tag(3)
                    
                    // 4: You (user + calendar; settings in toolbar)
                    MeView(model: model)
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text(loc(appLanguage, "You"))
                        }
                        .tag(4)
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
            .background(Color(.systemBackground))
            .sheet(item: $selectedCategory) { category in
                CategoryDetailView(model: model, category: category)
                .onAppear {
                    print("🟢 MainTabView: Showing CategoryDetailView for category: \(category.rawValue)")
                    print("🟢 CategoryDetailView appeared for category: \(category.rawValue)")
                }
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
