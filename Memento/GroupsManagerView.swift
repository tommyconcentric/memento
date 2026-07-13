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
                                Text("\(group.people.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                } footer: {
                    Text("Tap a folder to rename it. Deleting a folder keeps its people — they move to Ungrouped.")
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
        }
    }

    // MARK: - Actions

    private func addGroup() {
        let trimmed = newName.trimmed
        guard !trimmed.isEmpty else { return }
        let nextOrder = (groups.map(\.sortOrder).max() ?? -1) + 1
        context.insert(PersonGroup(name: trimmed, sortOrder: nextOrder))
        try? context.save()
        newName = ""
    }

    private func renameGroup() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmed
        guard !trimmed.isEmpty else { return }
        target.name = trimmed
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
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
