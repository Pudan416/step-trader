import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct TimeAccessPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FamilyActivitySelection
    let appName: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Choose app for \(appName)", comment: "TimeAccessPicker – title with app name"))
                    .font(.headline)
                    .padding(.horizontal)

                #if canImport(FamilyControls)
                FamilyActivityPicker(selection: $selection)
                    .ignoresSafeArea(edges: .bottom)
                #else
                Text(String(localized: "Family Controls not available on this build.", comment: "TimeAccessPicker – unavailable message"))
                    .padding()
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "TimeAccessPicker – dismiss button")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
}
