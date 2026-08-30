import SwiftUI

struct DayEndSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsEnergyPage(model: model)
    }
}

#Preview {
    NavigationStack {
        DayEndSettingsView(model: DIContainer.shared.makeAppModel())
    }
}
