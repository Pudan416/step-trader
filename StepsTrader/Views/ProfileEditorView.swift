import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var avatarImage: UIImage?
    @State private var showImagePicker: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var imagePickerError: String?
    
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
                                        .font(.geist(.title2).weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.geist(14))
                                            .foregroundStyle(.white)
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
                            .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(email)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(String(localized: "Email", comment: "ProfileEditor – email label"))
                    } footer: {
                        Text(String(localized: "Email is managed by Apple ID", comment: "ProfileEditor – email hint"))
                    }
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
            .onAppear { loadCurrentProfile() }
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
    
}

#Preview {
    ProfileEditorView(authService: AuthenticationService.shared)
}
