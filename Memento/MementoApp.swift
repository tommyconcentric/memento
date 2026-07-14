import SwiftUI
import SwiftData

@main
struct MementoApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            Person.self,
            PersonGroup.self,
            NoteEntry.self,
            EventPhoto.self,
            ImportantDate.self,
            FamilyMember.self
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.aegean)
        }
        .modelContainer(container)
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
