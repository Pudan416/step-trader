import SwiftUI
#if canImport(FamilyControls)
import FamilyControls

// MARK: - App Icon View (получает иконку из ApplicationToken)
struct AppIconView: View {
    let token: ApplicationToken
    
    var body: some View {
        // FamilyControls Label автоматически отображает иконку приложения
        Label(token)
            .labelStyle(.iconOnly)
    }
}

// MARK: - Category Icon View (получает иконку из ActivityCategoryToken)
struct CategoryIconView: View {
    let token: ActivityCategoryToken
    
    var body: some View {
        // FamilyControls Label автоматически отображает иконку категории
        Label(token)
            .labelStyle(.iconOnly)
    }
}

struct AppSelectionSheet: View {
    @Binding var selection: FamilyActivitySelection
    let appLanguage: String
    let templateApp: String?
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Instruction text for template shields
                if let templateApp = templateApp {
                    let appName = TargetResolver.displayName(for: templateApp)
                    Text(loc(appLanguage, "choose #APPNAME from the list").replacingOccurrences(of: "#APPNAME", with: appName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                
                // FamilyActivityPicker (apps and categories only)
                FamilyActivityPicker(selection: $selection)
            }
            .navigationTitle(loc(appLanguage, "Select Apps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done")) {
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
#endif
