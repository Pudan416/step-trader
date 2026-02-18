import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CustomActivityEditorView: View {
    let category: EnergyCategory
    let initialTitle: String?
    let initialIcon: String?
    let isEditing: Bool
    let onSave: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var selectedIcon: String = ""
    @FocusState private var isFieldFocused: Bool
    
    private let maxCharacters = 30
    
    private var catalogImageNames: [String] {
        GalleryImageCatalog.imageNames(for: category)
    }
    
    private var availableIcons: [String] {
        CustomActivityIcons.icons(for: category)
    }
    
    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !selectedIcon.isEmpty
    }
    
    /// Show image from Assets (true) or SF Symbol (false)
    private var selectedIsAssetImage: Bool {
        #if canImport(UIKit)
        return loadCatalogImage(named: selectedIcon) != nil
        #else
        return false
        #endif
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    previewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Activity name", text: $title)
                            .focused($isFieldFocused)
                            .onChange(of: title) { _, newValue in
                                if newValue.count > maxCharacters {
                                    title = String(newValue.prefix(maxCharacters))
                                }
                            }
                        
                        HStack {
                            Spacer()
                            Text("\(title.count)/\(maxCharacters)")
                                .font(AppFonts.caption)
                                .foregroundStyle(title.count >= maxCharacters ? .orange : .secondary)
                        }
                    }
                } header: {
                    Text("Name")
                }
                
                Section {
                    catalogImageGrid
                } header: {
                    Text("Image")
                } footer: {
                    Text("Add image sets to Assets with these names to see them here.")
                }
                
                Section {
                    iconGrid
                } header: {
                    Text("Icon (fallback)")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isEditing ? "Edit activity" : "Add activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed, selectedIcon)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                title = initialTitle ?? ""
                selectedIcon = initialIcon ?? (catalogImageNames.first ?? availableIcons.first ?? "pencil")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFieldFocused = true
                }
            }
        }
    }
    
    private var previewCard: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 96, height: 112)
                
                if selectedIsAssetImage, let uiImage = loadCatalogImage(named: selectedIcon) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: selectedIcon.isEmpty ? "questionmark" : selectedIcon)
                        .font(.systemSerif(32, weight: .light))
                        .foregroundColor(category.color.opacity(0.2))
                }
                
                VStack {
                    Spacer()
                    Text(title.isEmpty ? "Preview" : title)
                        .font(.systemSerif(11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: 96, height: 112)
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    private var catalogImageGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(catalogImageNames, id: \.self) { name in
                catalogImageButton(name)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func catalogImageButton(_ name: String) -> some View {
        let isSelected = selectedIcon == name
        let uiImage = loadCatalogImage(named: name)
        
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedIcon = name
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? category.color.opacity(0.3) : Color(.tertiarySystemFill))
                    .frame(width: 64, height: 64)
                
                if let uiImage = uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? category.color : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    /// Load from Assets trying exact name, then lowercase, then capitalized (same as shields/gallery).
    private func loadCatalogImage(named name: String) -> UIImage? {
        UIImage(named: name) ?? UIImage(named: name.lowercased()) ?? UIImage(named: name.capitalized)
    }
    
    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            ForEach(availableIcons, id: \.self) { icon in
                iconButton(icon)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func iconButton(_ icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedIcon = icon
            }
        } label: {
            ZStack {
                Circle()
                    .fill(selectedIcon == icon ? category.color : Color(.tertiarySystemFill))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.systemSerif(20))
                    .foregroundColor(selectedIcon == icon ? .white : .primary)
            }
            .overlay(
                Circle()
                    .stroke(selectedIcon == icon ? category.color : Color.clear, lineWidth: 2)
                    .scaleEffect(1.1)
            )
        }
        .buttonStyle(.plain)
    }
}
