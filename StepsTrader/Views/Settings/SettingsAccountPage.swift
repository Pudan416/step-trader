import SwiftUI

struct SettingsAccountPage: View {
    @ObservedObject var authService: AuthenticationService
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme
    @State private var showProfileEditor = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let coral = Color(red: 1, green: 0.47, blue: 0.40)

    private var user: AppUser? { authService.currentUser }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DetailHeader(title: "Account")
                        .padding(.horizontal, 16)

                    profileSummary

                    accountSection("PROFILE") {
                        DetailInfoRow(label: "Display name", value: user?.displayName ?? "User")
                        DetailDivider()
                        DetailInfoRow(label: "Email", value: user?.email ?? "—")
                    }

                    accountSection("SYNC") {
                        HStack {
                            Text("Automatic sync")
                                .font(.subheadline)
                                .foregroundStyle(theme.adaptivePrimaryText)
                            Spacer()
                            Text("On")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.adaptiveSecondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .accessibilityIdentifier("settings.account.automaticSync")
                    } footer: {
                        SettingsFooter(text: "Settings and history sync automatically across your devices.")
                    }

                    accountSection("ACCOUNT") {
                        Button {
                            authService.signOut()
                            dismiss()
                        } label: {
                            accountActionLabel("Sign out")
                        }
                        .buttonStyle(MattePressStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier("settings.account.signOut")
                    }

                    accountSection("DANGER ZONE") {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                if isDeleting {
                                    ProgressView()
                                } else {
                                    Text("Delete account")
                                        .font(.subheadline.weight(.semibold))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
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

    private var profileSummary: some View {
        HStack(spacing: 14) {
            accountAvatar

            Text(user?.displayName ?? "User")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)

            Spacer()

            Button("Edit profile") {
                showProfileEditor = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.brandAccent)
            .buttonStyle(MattePressStyle())
        }
        .padding(.horizontal, 30)
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
                    Text(SettingsAccountPresentation.initials(for: user?.displayName ?? "User"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private func accountSection<Content: View, Footer: View>(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: title)
                .padding(.horizontal, 30)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)

            footer()
                .padding(.horizontal, 20)
        }
    }

    private func accountActionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
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
            errorMessage = error.localizedDescription
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
