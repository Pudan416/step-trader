import SwiftUI
import UIKit

struct ProfileEditorView: View {
    @ObservedObject var authService: AuthenticationService
    @StateObject private var locationManager = ProfileLocationManager()
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var selectedCountryCode: String = ""
    @State private var showCountryPicker: Bool = false
    @State private var avatarImage: UIImage?
    @State private var showImagePicker: Bool = false
    @State private var showImageSourcePicker: Bool = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    
    // All countries sorted by localized name
    private var countries: [(code: String, name: String)] {
        let codes = Locale.Region.isoRegions.map { $0.identifier }
        let locale = Locale(identifier: "en_US")
        return codes.compactMap { code -> (String, String)? in
            guard let name = locale.localizedString(forRegionCode: code), !name.isEmpty else { return nil }
            return (code, name)
        }.sorted { $0.name < $1.name }
    }
    
    private var selectedCountryName: String {
        if selectedCountryCode.isEmpty { return "" }
        let locale = Locale(identifier: "en_US")
        return locale.localizedString(forRegionCode: selectedCountryCode) ?? selectedCountryCode
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        Button {
                            showImageSourcePicker = true
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
                                        Image(systemName: "camera.fill")
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
                                Text("Remove Photo")
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
                        TextField("Nickname", text: $nickname)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Nickname")
                } footer: {
                    Text("This name will be displayed instead of my real name")
                }
                
                // Location section
                Section {
                    // Use my location button
                    Button {
                        locationManager.requestCountryCode { detectedCountryCode in
                            if let cc = detectedCountryCode { selectedCountryCode = cc }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("Detect my country")
                                .foregroundColor(.blue)
                            Spacer()
                            if locationManager.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(locationManager.isLoading)
                    
                    // Country picker
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Country")
                                .foregroundColor(.primary)
                            Spacer()
                            if !selectedCountryCode.isEmpty {
                                Text(selectedCountryName)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Select")
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if let error = locationManager.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    }
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
                        Text("Email")
                    } footer: {
                        Text("Email is managed by Apple ID")
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
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
            .alert("Error", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog(
                "Choose Photo",
                isPresented: $showImageSourcePicker,
                titleVisibility: .visible
            ) {
                Button("Camera") {
                    imageSourceType = .camera
                    showImagePicker = true
                }
                Button("Photo Library") {
                    imageSourceType = .photoLibrary
                    showImagePicker = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $avatarImage, sourceType: imageSourceType)
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerView(
                    selectedCountryCode: $selectedCountryCode,
                    countries: countries
                )
            }
        }
    }
    
    private func loadCurrentProfile() {
        if let user = authService.currentUser {
            nickname = user.nickname ?? ""
            if let storedCountry = user.country, countries.contains(where: { $0.code == storedCountry }) {
                selectedCountryCode = storedCountry
            } else {
                selectedCountryCode = user.country ?? ""
            }
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
                country: selectedCountryCode.isEmpty ? nil : selectedCountryCode,
                avatarData: avatarData
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        
        isSaving = false
    }
}
