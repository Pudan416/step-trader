import SwiftUI

struct LegacyDeviceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var history: LegacyDeviceHistory?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let history {
                    List {
                        Section {
                            ForEach(history.days) { day in
                                NavigationLink {
                                    LegacyDeviceHistoryDayView(day: day, archive: history.archive)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(day.id)
                                        if !day.titles.isEmpty {
                                            Text(day.titles.joined(separator: ", "))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } footer: {
                            Text("Saved on this iPhone. This history is separate from your account.")
                        }
                    }
                } else if failed {
                    ContentUnavailableView("History unavailable", systemImage: "externaldrive", description: Text("Your saved files are still on this iPhone. Please try again."))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Previous device history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                guard let archive = try AccountHistoryStorage.makeVault().legacyArchive() else {
                    failed = true
                    return
                }
                history = try LegacyDeviceHistory(archive: archive)
            } catch {
                failed = true
            }
        }
    }
}

private struct LegacyDeviceHistoryDayView: View {
    let day: LegacyDeviceHistory.Day
    let archive: AccountHistoryVault.LegacyArchive
    @State private var preview: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Saved canvas")
                }
                ForEach(Array(day.titles.enumerated()), id: \.offset) { _, title in
                    Text(title)
                }
                if let spent = day.spent {
                    Text("\(spent) colors spent")
                        .foregroundStyle(.secondary)
                }
                if day.titles.isEmpty && preview == nil && day.spent == nil {
                    Text("Saved canvas files are preserved on this iPhone.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(day.id)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let path = day.previewPath else { return }
            if let bytes = try? archive.fileData(at: path) { preview = UIImage(data: bytes) }
        }
    }
}
