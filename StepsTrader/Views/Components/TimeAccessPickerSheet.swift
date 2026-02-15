import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct TimeAccessPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FamilyActivitySelection
    let appName: String

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose app for \(appName)")
                    .font(.headline)
                    .padding(.horizontal)

                #if canImport(FamilyControls)
                FamilyActivityPicker(selection: $selection)
                    .ignoresSafeArea(edges: .bottom)
                #else
                Text("Family Controls not available on this build.")
                    .padding()
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
}
