import SwiftUI

struct HappeningEventExplorer: View {
    let onChoose: (HappeningEventNode) -> Void
    let remaining: Int
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sphere: HappeningEventNode?
    @State private var selected: HappeningEventNode?
    @State private var suggestions: [HappeningEventNode] = []
    @State private var search = ""
    @State private var tab = 0
    private let ink = Color(hex: "24372B")
    private let paper = Color(hex: "F4F5EF")

    private var allResults: [HappeningEventNode] {
        HappeningEventTree.all.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("\(remaining) left today")
                    Spacer()
                    Text("\(10 - remaining) / 10").monospacedDigit()
                }
                .font(.custom("Onest-Medium", size: 14)).foregroundStyle(ink.opacity(0.68))
                .padding(.horizontal, 22).padding(.top, 8)

                Picker("Browse events", selection: $tab) {
                    Text("Tree").tag(0)
                    Text("All").tag(1)
                }.pickerStyle(.segmented).padding(.horizontal, 22)

                if tab == 0 { treeList } else { allList }

                Button {
                    onFinish()
                    dismiss()
                } label: {
                    Text("Finish day")
                        .font(.custom("Onest-SemiBold", size: 16))
                        .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                        .background(ink, in: Capsule())
                }
                .buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 10)
            }
            .background(paper)
            .navigationTitle("What happened?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(ink).preferredColorScheme(.light)
    }

    private var treeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let parent = sphere {
                    HStack(spacing: 5) {
                        Button("Areas") { selected = nil; sphere = nil; suggestions = [] }
                        Image(systemName: "chevron.right").font(.caption2)
                        Text(parent.title).lineLimit(1)
                    }
                    .font(.custom("Onest-Medium", size: 13)).foregroundStyle(ink.opacity(0.65))
                    .padding(.horizontal, 22).padding(.vertical, 12)

                    let rows = parent.children.flatMap(HappeningEventTree.leaves)
                    ForEach(rows) { event in
                        eventRow(event, showsChildren: false) {
                            guard remaining > 0 else { return }
                            onChoose(event)
                            if remaining == 1 { onFinish(); dismiss() }
                            selected = event
                            suggestions = HappeningEventTree.suggestions(for: event, within: parent)
                        }
                    }
                    if selected != nil, !suggestions.isEmpty {
                        Text("You might also")
                            .font(.custom("Onest-SemiBold", size: 16)).foregroundStyle(ink)
                            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
                        ForEach(suggestions) { event in
                            eventRow(event, showsChildren: false) {
                                guard remaining > 0 else { return }
                                onChoose(event)
                                if remaining == 1 { onFinish(); dismiss() }
                                suggestions = HappeningEventTree.suggestions(for: event, within: parent)
                                self.selected = event
                            }
                        }
                    }
                    Button("Choose another area") { sphere = nil; selected = nil; suggestions = [] }
                        .font(.custom("Onest-Medium", size: 14)).foregroundStyle(ink)
                        .padding(22)
                } else {
                    Text("Pick an area of your day")
                        .font(.custom("Onest-SemiBold", size: 18)).foregroundStyle(ink)
                        .padding(.horizontal, 22).padding(.vertical, 14)
                    ForEach(HappeningEventTree.spheres) { item in
                        eventRow(item, showsChildren: true) { sphere = item; selected = nil; suggestions = [] }
                    }
                }
            }
        }
    }

    private var allList: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("Search events", text: $search).autocorrectionDisabled()
            }
            .font(.custom("Onest-Regular", size: 15)).padding(12)
            .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 22)

            List {
                ForEach(HappeningEventTree.spheres) { area in
                    let matching = allResults.filter { isInside($0, area: area) }
                    if !matching.isEmpty {
                        Section(area.title) {
                            ForEach(matching) { event in
                                Button {
                                    guard remaining > 0 else { return }
                                    onChoose(event)
                                    if remaining == 1 { onFinish(); dismiss() }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title).font(.custom("Onest-Medium", size: 15))
                                        Text(path(for: event, in: area).joined(separator: " › "))
                                            .font(.custom("Onest-Regular", size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .disabled(remaining == 0)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func eventRow(_ event: HappeningEventNode, showsChildren: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(event.title).font(.custom("Onest-Medium", size: 15))
                Spacer()
                Image(systemName: showsChildren ? "chevron.right" : "plus.circle")
                    .font(.system(size: showsChildren ? 12 : 18, weight: .medium)).foregroundStyle(ink.opacity(0.48))
            }
            .foregroundStyle(ink).padding(.horizontal, 22).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.08)).frame(height: 1).padding(.leading, 22) }
    }

    private func isInside(_ node: HappeningEventNode, area: HappeningEventNode) -> Bool {
        HappeningEventTree.flatten(area).contains { $0.id == node.id }
    }

    private func path(for node: HappeningEventNode, in area: HappeningEventNode) -> [String] {
        func find(_ current: HappeningEventNode, trail: [String]) -> [String]? {
            let next = trail + [current.title]
            if current.id == node.id { return next }
            for child in current.children { if let found = find(child, trail: next) { return found } }
            return nil
        }
        return Array((find(area, trail: []) ?? [area.title, node.title]).dropFirst())
    }
}
