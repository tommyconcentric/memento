import SwiftUI
import SwiftData

/// Manage the folders people are grouped into. The four starter folders
/// are created on first launch; add, rename, reorder or delete any folder.
struct GroupsManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PersonGroup.sortOrder)]) private var groups: [PersonGroup]

    @State private var showingAdd = false
    @State private var newName = ""
    @State private var showingRename = false
    @State private var renameTarget: PersonGroup?
    @State private var renameText = ""
    @State private var showingRenameCollision = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups) { group in
                        Button {
                            renameTarget = group
                            renameText = group.name
                            showingRename = true
                        } label: {
                            HStack {
                                Label {
                                    Text(group.name)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "folder")
                                }
                                Spacer()
                                Text("\(group.peopleArray.count)")
                                    .foregroundStyle(.secondary)
                                // The drag affordance sits in the row itself,
                                // not only behind Edit: a list that reorders is
                                // invisible until you already know it does.
                                Image(systemName: "line.3.horizontal")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                } header: {
                    TipHeader(
                        title: "Drag ≡ to reorder",
                        tip: "Folders show in this order everywhere, with Ungrouped last. Tap a folder to rename it. Deleting a folder keeps its people — they move to Ungrouped."
                    )
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add folder")
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Folder", isPresented: $showingAdd) {
                TextField("Folder name", text: $newName)
                Button("Add", action: addGroup)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Folder", isPresented: $showingRename) {
                TextField("Folder name", text: $renameText)
                Button("Save", action: renameGroup)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Name Already Used", isPresented: $showingRenameCollision) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Another starter folder is already called “\(renameText.trimmed)”. Give this one a different name.")
            }
        }
    }

    // MARK: - Actions

    private func addGroup() {
        let trimmed = newName.trimmed
        guard !trimmed.isEmpty else { return }
        // Slot it in alphabetically among its peers rather than dumping it at
        // the bottom. Only an insert — every existing folder keeps its
        // relative position, so a hand-dragged order survives.
        let newRank = PersonGroup.defaultRank(of: trimmed)
        let ordered = groups.sorted { $0.sortOrder < $1.sortOrder }
        let insertion = ordered.firstIndex {
            let rank = PersonGroup.defaultRank(of: $0.name)
            if rank != newRank { return rank > newRank }
            return $0.name.localizedStandardCompare(trimmed) == .orderedDescending
        } ?? ordered.count

        let group = PersonGroup(name: trimmed, sortOrder: insertion)
        context.insert(group)
        var reordered = ordered
        reordered.insert(group, at: insertion)
        for (index, folder) in reordered.enumerated() {
            folder.sortOrder = index
        }
        try? context.save()
        newName = ""
    }

    private func renameGroup() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmed
        guard !trimmed.isEmpty else { return }
        // Two built-in folders sharing a name is the exact shape the
        // duplicate-seed sweep (mergeDuplicateBuiltInGroups) folds on the
        // next activation — it would silently delete whichever copy is
        // empty. Refuse the collision here instead of letting a rename
        // make a folder vanish later.
        if target.isBuiltIn {
            let collides = groups.contains { other in
                other.isBuiltIn
                    && other.persistentModelID != target.persistentModelID
                    && other.name.trimmed.lowercased() == trimmed.lowercased()
            }
            if collides {
                showingRenameCollision = true
                return
            }
        }
        // A hidden folder that gets renamed un-hides (documented behavior),
        // so retire the old name from the filter — otherwise a future folder
        // re-using it would be born hidden.
        removeFromHiddenFilters(target.name)
        target.name = trimmed
        try? context.save()
    }

    /// Drops a folder name from the sidebar's hidden-folders filter (stored
    /// name-keyed in AppStorage by PeopleListView).
    private func removeFromHiddenFilters(_ name: String) {
        let key = "hiddenFolderNames"
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: key) ?? ""
        let remaining = stored.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != name }
        defaults.set(remaining.joined(separator: "\n"), forKey: key)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            // A deleted folder leaves the hidden-folders filter too — a
            // later folder with the same name must not be born hidden.
            removeFromHiddenFilters(groups[index].name)
            context.delete(groups[index])
        }
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = Array(groups)
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, group) in ordered.enumerated() {
            group.sortOrder = index
        }
        try? context.save()
    }
}
