import SwiftUI

// MARK: - Resistance tab
// Philosophy: You're not alone. No rankings, no scores, just presence.
struct ResistanceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var users: [AuthenticationService.ResistanceUser] = []
    @State private var isLoading = false
    @State private var loadError: Bool = false

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                loadingView
            } else if users.isEmpty {
                emptyStateView
            } else {
                usersList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(loc(appLanguage, "Resistance"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadUsers()
        }
        .refreshable {
            await loadUsers()
        }
    }
    
    // MARK: - Loading State
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(loc(appLanguage, "Loading..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State (ContentUnavailableView style)
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.3")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text(loc(appLanguage, "No one here yet"))
                    .font(.title3.weight(.semibold))
                
                Text(loc(appLanguage, "People resisting doomscrolling will appear here."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if loadError {
                Button {
                    Task { await loadUsers() }
                } label: {
                    Label(loc(appLanguage, "Try Again"), systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Users List
    private var usersList: some View {
        List {
            // Header section
            Section {
                headerCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            
            // Users section
            Section {
                ForEach(users) { user in
                    ResistanceUserRow(user: user)
                }
            } header: {
                HStack {
                    Text(loc(appLanguage, "People"))
                        .textCase(nil)
                    Spacer()
                    Text("\(users.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppColors.brandPink.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.brandPink)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "You're not alone"))
                        .font(.headline)
                    
                    Text(loc(appLanguage, "Others are choosing presence too."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Load Users
    private func loadUsers() async {
        isLoading = true
        loadError = false
        do {
            users = try await AuthenticationService.shared.fetchResistanceUsers(limit: 50)
        } catch {
            print("❌ Failed to load resistance users: \(error)")
            loadError = true
        }
        isLoading = false
    }
}

// MARK: - User Row
struct ResistanceUserRow: View {
    let user: AuthenticationService.ResistanceUser
    
    private var initials: String {
        let words = user.nickname.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(user.nickname.prefix(2)).uppercased()
    }
    
    private var avatarColor: Color {
        // Deterministic color based on user id
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint
        ]
        let hash = user.id.hashValue
        return colors[abs(hash) % colors.count].opacity(0.8)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            Circle()
                .fill(avatarColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(initials)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(avatarColor)
                )
            
            // Name
            Text(user.nickname)
                .font(.body)
            
            Spacer()
            
            // Subtle indicator — present, not ranked
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ResistanceView(model: DIContainer.shared.makeAppModel())
    }
}
