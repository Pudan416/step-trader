import SwiftUI

enum SettingsAccountFailurePresentation {
    enum Operation {
        case deletion
        case profileSaving
        case other
    }

    static func message(for operation: Operation) -> String {
        switch operation {
        case .deletion:
            String(localized: "We couldn't delete your account. Check your connection and try again.")
        case .profileSaving:
            String(localized: "We couldn't save your profile. Your previous details are still intact.")
        case .other:
            String(localized: "Something went wrong. Please try again.")
        }
    }
}

struct SettingsAccountPage: View {
    @ObservedObject var authService: AuthenticationService
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showProfileEditor = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let coral = Color(red: 1, green: 0.47, blue: 0.40)

    private var user: AppUser? { authService.currentUser }

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    profileHeader
                        .padding(.horizontal, 30)
                        .padding(.top, 12)

                    accountSection(String(localized: "SYNC", comment: "Settings account section header")) {
                        HStack {
                            Text(String(localized: "Automatic sync", comment: "Settings account sync status label"))
                                .font(.geist(.subheadline))
                                .foregroundStyle(theme.adaptivePrimaryText)
                            Spacer()
                            Text(String(localized: "On", comment: "Settings account sync status value"))
                                .font(.geist(.subheadline).weight(.semibold))
                                .foregroundStyle(theme.adaptiveSecondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .accessibilityIdentifier("settings.account.automaticSync")
                    } footer: {
                        SettingsFooter(text: String(localized: "Settings and history sync automatically across your devices.", comment: "Settings account sync footer"))
                    }

                    accountSection(String(localized: "ACCOUNT", comment: "Settings account section header")) {
                        Button {
                            authService.signOut()
                            dismiss()
                        } label: {
                            accountActionLabel(String(localized: "Sign out", comment: "Settings account sign-out button"))
                        }
                        .buttonStyle(MattePressStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier("settings.account.signOut")
                    }

                    accountSection(String(localized: "DANGER ZONE", comment: "Settings account section header")) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                if isDeleting {
                                    ProgressView()
                                } else {
                                    Text(String(localized: "Delete account", comment: "Settings account delete button"))
                                        .font(.geist(.subheadline).weight(.semibold))
                                }
                                Spacer()
                            }
                            .foregroundStyle(coral)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MattePressStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier("settings.account.delete")
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .settingsDetailPage(title: String(localized: "Account", comment: "Settings account page title"))
        .sheet(isPresented: $showProfileEditor) {
            ProfileEditorView(authService: authService)
        }
        .alert(String(localized: "Error", comment: "ProfileEditor – error alert title"), isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK", comment: "ProfileEditor – alert dismiss button")) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "Delete Account", comment: "ProfileEditor – delete confirmation title"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Account", comment: "ProfileEditor – delete confirmation title"), role: .destructive) {
                Task { await performAccountDeletion() }
            }
            Button(String(localized: "Cancel", comment: "ProfileEditor – dismiss button"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will permanently delete your account, profile, and all data. This action cannot be undone.", comment: "ProfileEditor – delete confirmation message"))
        }
    }

    private var profileHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    profileIdentity
                    editProfileButton
                        .padding(.leading, 66)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        profileIdentity
                        Spacer(minLength: 12)
                        editProfileButton
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        profileIdentity
                        editProfileButton
                            .padding(.leading, 66)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.account.profileHeader")
    }

    private var profileIdentity: some View {
        HStack(alignment: .center, spacing: 14) {
            accountAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(user?.displayName ?? String(localized: "User", comment: "Settings account fallback name"))
                    .font(.geist(.title2).weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(user?.email ?? String(localized: "—", comment: "Settings account unavailable email"))
                    .font(.geist(.subheadline))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var editProfileButton: some View {
        Button(String(localized: "Edit profile", comment: "Settings account edit profile button")) {
            showProfileEditor = true
        }
        .font(.geist(.subheadline).weight(.semibold))
        .foregroundStyle(AppColors.brandAccent)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .buttonStyle(MattePressStyle())
        .accessibilityIdentifier("settings.account.editProfile")
    }

    private var accountAvatar: some View {
        Group {
            if let data = user?.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(SettingsAccountPresentation.initials(for: user?.displayName ?? String(localized: "User", comment: "Settings account fallback name")))
                        .font(.geist(.subheadline).weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func accountSection<Content: View, Footer: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsLabeledGroup(title: title, content: content)

            footer()
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
    }

    private func accountActionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.geist(.subheadline).weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @MainActor
    private func performAccountDeletion() async {
        isDeleting = true
        do {
            try await authService.deleteAccount()
            dismiss()
        } catch {
            AppLogger.auth.error("Account deletion failed: \(error.localizedDescription)")
            errorMessage = SettingsAccountFailurePresentation.message(for: .deletion)
            isDeleting = false
        }
    }
}

#Preview {
    NavigationStack {
        SettingsAccountPage(
            authService: AuthenticationService.shared,
            model: DIContainer.shared.makeAppModel()
        )
    }
}
