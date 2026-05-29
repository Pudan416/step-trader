import SwiftUI

// MARK: - MeView support types
//
// Extracted from `MeView.swift` (§9.2): the week-summary value type, the
// day-key identifier wrapper, and the two view-modifiers that own MeView's
// lifecycle (snapshot loading / day-boundary refresh) and sheet presentation.

struct MeWeekSummary {
    var avgSteps: Int = 0
    var avgSleep: Double = 0
    var topBody: [String] = []
    var topMind: [String] = []
    var topHeart: [String] = []
}

struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

struct MeLifecycleModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @Binding var cachedDayKeys: [String]
    @Binding var hasLoadedSnapshots: Bool
    @Binding var loadTask: Task<Void, Never>?
    @Binding var serverFetchTask: Task<Void, Never>?
    let onLoad: () -> Void
    let onDayEndChange: () -> Void
    let onTopConsumersChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasLoadedSnapshots else { return }
                hasLoadedSnapshots = true
                cachedDayKeys = MeView.computeDayKeys()
                onLoad()
            }
            .onChange(of: model.baseEnergyToday) { _, _ in
                let newKeys = MeView.computeDayKeys()
                if newKeys != cachedDayKeys {
                    cachedDayKeys = newKeys
                    onLoad()
                }
            }
            .onChange(of: model.dayEndHour) { _, _ in onDayEndChange() }
            .onChange(of: model.dayEndMinute) { _, _ in onDayEndChange() }
            .onChange(of: model.appStepsSpentByDay) { _, _ in onTopConsumersChange() }
            .onChange(of: model.ticketGroups.map(\.id)) { _, _ in onTopConsumersChange() }
            .onDisappear {
                loadTask?.cancel()
                serverFetchTask?.cancel()
            }
    }
}

struct MeSheetsModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @Binding var showLogin: Bool
    @Binding var showProfileEditor: Bool
    @Binding var selectedDayKey: String?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService, model: model)
            }
            .fullScreenCover(item: Binding(
                get: { selectedDayKey.map { MeDayKeyWrapper(key: $0) } },
                set: { selectedDayKey = $0?.key }
            )) { wrapper in
                DayCanvasViewerView(model: model, dayKey: wrapper.key)
            }
    }
}
