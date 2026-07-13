import SwiftUI
import SwiftData

@main
struct MementoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.aegean)
        }
        .modelContainer(for: [
            Person.self,
            PersonGroup.self,
            NoteEntry.self,
            EventPhoto.self,
            ImportantDate.self,
            FamilyMember.self
        ])
    }
}

/// Hosts the main list and seeds the four starter folders on first launch.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var groups: [PersonGroup]
    @AppStorage("didSeedDefaultGroups") private var didSeedDefaultGroups = false

    var body: some View {
        PeopleListView()
            .onAppear(perform: seedDefaultGroupsIfNeeded)
    }

    private func seedDefaultGroupsIfNeeded() {
        guard !didSeedDefaultGroups, groups.isEmpty else { return }
        let names = ["Close Friends", "Friends", "Work Colleagues", "Family"]
        for (index, name) in names.enumerated() {
            context.insert(PersonGroup(name: name, sortOrder: index, isBuiltIn: true))
        }
        didSeedDefaultGroups = true
        try? context.save()
    }
}
