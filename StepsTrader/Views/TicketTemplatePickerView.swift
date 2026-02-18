import SwiftUI
import UIKit

// MARK: - Ticket Template Picker
struct TicketTemplatePickerView: View {
    @ObservedObject var model: AppModel
    let appLanguage: String = "en"
    let onTemplateSelected: (String) -> Void
    let onCustomSelected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    private struct Template {
        let bundleId: String
        let name: String
        let imageName: String
    }
    
    @MainActor private static var imageCache: [String: UIImage] = [:]

    @MainActor private static func resolvedTemplateImage(_ name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }
        let img = UIImage(named: name)
            ?? UIImage(named: name.lowercased())
            ?? UIImage(named: name.capitalized)
        if let img { imageCache[name] = img }
        return img
    }

    private static let allTemplates: [Template] = {
        let bundleIds = [
            "com.burbn.instagram", "com.zhiliaoapp.musically", "com.google.ios.youtube",
            "com.toyopagroup.picaboo", "com.reddit.Reddit", "com.atebits.Tweetie2",
            "com.facebook.Facebook", "com.linkedin.LinkedIn",
            "com.pinterest", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp"
        ]
        return bundleIds.compactMap { bid in
            TargetResolver.imageName(for: bid).map { imageName in
                Template(bundleId: bid, name: TargetResolver.displayName(for: bid), imageName: imageName)
            }
        }
    }()
    
    private var availableTemplates: [Template] {
        let usedTemplateApps = Set(model.blockingStore.ticketGroups.compactMap { $0.templateApp })
        return Self.allTemplates.filter { !usedTemplateApps.contains($0.bundleId) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Button {
                        onCustomSelected()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .ultraLight))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Custom Ticket")
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("Choose your own apps")
                                    .font(.system(size: 12, weight: .light, design: .rounded))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .ultraLight))
                                .foregroundStyle(Color.primary.opacity(0.3))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Templates")
                            .font(.system(size: 14, weight: .light, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .padding(.horizontal, 4)
                        
                        if availableTemplates.isEmpty {
                            Text("All templates in use")
                                .font(.system(size: 13, weight: .light, design: .rounded))
                                .foregroundStyle(Color.primary.opacity(0.3))
                                .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(availableTemplates, id: \.bundleId) { template in
                                    templateCard(template: template)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func templateCard(template: Template) -> some View {
        Button {
            onTemplateSelected(template.bundleId)
        } label: {
            VStack(spacing: 8) {
                let uiImage = Self.resolvedTemplateImage(template.imageName)
                if let uiImage = uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 18, weight: .ultraLight))
                                .foregroundStyle(Color.primary.opacity(0.3))
                        )
                }
                
                Text(template.name)
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }
}
