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
    let templateApp: String?
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var validationMessage: String? {
        guard templateApp != nil else { return nil }
        return TargetResolver.singleAppPresetValidationMessage(
            for: selection,
            templateBundleId: templateApp
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let templateApp = templateApp {
                    let appName = TargetResolver.displayName(for: templateApp)
                    Text(String(localized: "Choose only \(appName) from the list", comment: "AppSelection – single app hint"))
                        .font(AppFonts.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }

                FamilyActivityPicker(selection: $selection)
            }
            .animation(.easeInOut(duration: 0.2), value: validationMessage != nil)
            .navigationTitle(String(localized: "Select Apps", comment: "AppSelection – navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "AppSelection – dismiss button")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "AppSelection – done button")) {
                        onDone()
                    }
                    .fontWeight(.semibold)
                    .disabled(validationMessage != nil)
                }
            }
        }
    }
}
#endif
