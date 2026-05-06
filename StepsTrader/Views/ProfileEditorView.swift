import SwiftUI
import UIKit

struct ProfileEditorView: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var avatarImage: UIImage?
    @State private var showImagePicker: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var imagePickerError: String?
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeleting: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        Button {
                            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                                imagePickerError = "Photo library is not available right now."
                                return
                            }
                            showImagePicker = true
                        } label: {
                            ZStack {
                                if let image = avatarImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 96, height: 96)
                                    
                                    Text(String((authService.currentUser?.displayName ?? "U").prefix(2)).uppercased())
                                        .font(.title2.weight(.bold))
                                        .foregroundColor(.white)
                                }
                                
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Image(systemName: "camera")
                                            .font(.systemSerif(14))
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 34, y: 34)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    
                    if avatarImage != nil {
                        Button(role: .destructive) {
                            avatarImage = nil
                        } label: {
                            HStack {
                                Spacer()
                                Text(String(localized: "Remove Photo", comment: "ProfileEditor – remove avatar button"))
                                Spacer()
                            }
                        }
                    }
                }
                
                // Nickname section
                Section {
                    HStack {
                        Image(systemName: "at")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        TextField(String(localized: "Nickname", comment: "ProfileEditor – nickname field"), text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text(String(localized: "Nickname", comment: "ProfileEditor – nickname field"))
                } footer: {
                    Text(String(localized: "This name will be displayed instead of my real name", comment: "ProfileEditor – nickname hint"))
                }
                
                // Email (read-only)
                if let email = authService.currentUser?.email {
                    Section {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(email)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text(String(localized: "Email", comment: "ProfileEditor – email label"))
                    } footer: {
                        Text(String(localized: "Email is managed by Apple ID", comment: "ProfileEditor – email hint"))
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                            } else {
                                Text(String(localized: "Delete Account", comment: "ProfileEditor – delete account button"))
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeleting || isSaving)
                } footer: {
                    Text(String(localized: "Permanently deletes your account, profile, and all associated data. This cannot be undone.", comment: "ProfileEditor – delete warning text"))
                }
            }
            .navigationTitle(String(localized: "Edit Profile", comment: "ProfileEditor – navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "ProfileEditor – dismiss button")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save", comment: "ProfileEditor – save button")) {
                            Task {
                                await saveProfileAsync()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                loadCurrentProfile()
            }
            .alert(String(localized: "Error", comment: "ProfileEditor – error alert title"), isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button(String(localized: "OK", comment: "ProfileEditor – alert dismiss button")) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .alert(String(localized: "Photo Access", comment: "ProfileEditor – photo permission alert title"), isPresented: .init(
                get: { imagePickerError != nil },
                set: { if !$0 { imagePickerError = nil } }
            )) {
                Button(String(localized: "OK", comment: "ProfileEditor – alert dismiss button")) { imagePickerError = nil }
            } message: {
                Text(imagePickerError ?? "")
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $avatarImage, sourceType: .photoLibrary)
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
    }
    
    private func loadCurrentProfile() {
        if let user = authService.currentUser {
            nickname = user.nickname ?? ""
            if let data = user.avatarData, let image = UIImage(data: data) {
                avatarImage = image
            } else {
                avatarImage = nil
            }
        }
    }
    
    @MainActor
    private func saveProfileAsync() async {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarData = avatarImage?.jpegData(compressionQuality: 0.75)
        
        isSaving = true
        saveError = nil
        
        do {
            try await authService.updateProfileAsync(
                nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
                country: nil,
                avatarData: avatarData
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        
        isSaving = false
    }
    
    @MainActor
    private func performAccountDeletion() async {
        isDeleting = true
        do {
            try await authService.deleteAccount()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isDeleting = false
        }
    }
}
