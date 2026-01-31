import SwiftUI

struct CustomActivityEditorView: View {
    let category: EnergyCategory
    let appLanguage: String
    let initialTitle: String?
    let initialIcon: String?
    let isEditing: Bool
    let onSave: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var selectedIcon: String = ""
    @FocusState private var isFieldFocused: Bool
    
    private let maxCharacters = 30
    
    private var availableIcons: [String] {
        CustomActivityIcons.icons(for: category)
    }
    
    private var categoryColor: Color {
        switch category {
        case .activity: return .green
        case .recovery: return .blue
        case .joys: return .orange
        }
    }
    
    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !selectedIcon.isEmpty
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
                        TextField(loc(appLanguage, "Activity name"), text: $title)
                            .focused($isFieldFocused)
                            .onChange(of: title) { _, newValue in
                                if newValue.count > maxCharacters {
                                    title = String(newValue.prefix(maxCharacters))
                                }
                            }
                        
                        HStack {
                            Spacer()
                            Text("\(title.count)/\(maxCharacters)")
                                .font(.caption)
                                .foregroundStyle(title.count >= maxCharacters ? .orange : .secondary)
                        }
                    }
                } header: {
                    Text(loc(appLanguage, "Name"))
                }
                
                Section {
                    iconGrid
                } header: {
                    Text(loc(appLanguage, "Icon"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isEditing ? loc(appLanguage, "Edit activity") : loc(appLanguage, "Add activity"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Save")) {
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
                selectedIcon = initialIcon ?? (availableIcons.first ?? "pencil")
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
                
                Image(systemName: selectedIcon.isEmpty ? "questionmark" : selectedIcon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(categoryColor.opacity(0.2))
                
                VStack {
                    Spacer()
                    Text(title.isEmpty ? loc(appLanguage, "Preview") : title)
                        .font(.system(size: 11, weight: .medium))
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
                    .fill(selectedIcon == icon ? categoryColor : Color(.tertiarySystemFill))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(selectedIcon == icon ? .white : .primary)
            }
            .overlay(
                Circle()
                    .stroke(selectedIcon == icon ? categoryColor : Color.clear, lineWidth: 2)
                    .scaleEffect(1.1)
            )
        }
        .buttonStyle(.plain)
    }
}
