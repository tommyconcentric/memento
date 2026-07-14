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

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.enabledKey) private var appLockEnabled = false
    @State private var isLocked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .tint(Theme.aegean)
                if isLocked {
                    AppLockView(onUnlock: { isLocked = false })
                        .transition(.opacity)
                }
            }
            // Lock on any departure from .active, not just .background, so an
            // app-switcher snapshot never shows real notes unlocked.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active && appLockEnabled {
                    isLocked = true
                }
            }
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
        // Only latch the flag once the insert is durably saved, so a failed
        // save (e.g. a CloudKit hiccup on first launch) retries next launch
        // instead of permanently skipping the starter folders.
        if (try? context.save()) != nil {
            didSeedDefaultGroups = true
        }
    }
}
