import SwiftUI
#if canImport(FamilyControls)
import FamilyControls

// MARK: - App Icon View (gets icon from ApplicationToken)
struct AppIconView: View {
    let token: ApplicationToken
    
    var body: some View {
        // FamilyControls Label automatically displays the app icon
        Label(token)
            .labelStyle(.iconOnly)
    }
}

// MARK: - Category Icon View (gets icon from ActivityCategoryToken)
struct CategoryIconView: View {
    let token: ActivityCategoryToken
    
    var body: some View {
        // FamilyControls Label automatically displays the category icon
        Label(token)
            .labelStyle(.iconOnly)
    }
}

struct AppSelectionSheet: View {
    @Binding var selection: FamilyActivitySelection
    let appLanguage: String = "en"
    let templateApp: String?
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Instruction text for template shields
                if let templateApp = templateApp {
                    let appName = TargetResolver.displayName(for: templateApp)
                    Text("choose \(appName) from the list")
                        .font(AppFonts.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                
                // FamilyActivityPicker (apps and categories only)
                FamilyActivityPicker(selection: $selection)
            }
            .navigationTitle("Select Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
#endif
