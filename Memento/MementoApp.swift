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
            FamilyMember.self,
            ContactField.self,
            Project.self,
            Parentage.self,
            Partnership.self
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
    @AppStorage(Workspace.storageKey) private var storedWorkspace = Workspace.personal.rawValue
    // Only lock when a PIN actually exists to unlock with. The enabled flag
    // lives in UserDefaults (restored onto a new device by backup/migration)
    // but the PIN is ThisDeviceOnly in the Keychain (not restored) — locking
    // on the flag alone would brick the app until a delete-and-reinstall.
    @State private var isLocked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
        && AppLock.storedPIN != nil

    // Activation-driven refresh is throttled: on the Mac every window-focus
    // change is an activation, and a full EventKit rebuild per focus would
    // be constant churn. Save paths still refresh immediately.
    private static var lastActivationRefresh = Date.distantPast
    private static let activationRefreshInterval: TimeInterval = 15 * 60

    var body: some Scene {
        WindowGroup {
            RootView()
                // Tint follows the active workspace so every control in
                // the app speaks the current mode's accent.
                .tint((Workspace(rawValue: storedWorkspace) ?? .personal).accent)
                // The lock lives in its own UIWindow (LockScreenPresenter)
                // rather than an in-hierarchy overlay: SwiftUI sheets are
                // presented above the root view, so an overlay would leave
                // any open sheet visible and tappable while "locked".
                .onAppear {
                    if isLocked {
                        LockScreenPresenter.show { isLocked = false }
                    }
                }
                .onChange(of: isLocked) { _, locked in
                    if locked {
                        LockScreenPresenter.show { isLocked = false }
                    } else {
                        LockScreenPresenter.hide()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // On iPhone/iPad, lock on any departure from .active so
                    // an app-switcher snapshot never shows real notes. On
                    // the Mac, .inactive fires every time another app's
                    // window takes focus — locking there would demand the
                    // PIN on every app switch, so lock only when the app is
                    // actually hidden/minimized (.background); the Mac's own
                    // session lock covers the rest.
                    let shouldLock = ProcessInfo.processInfo.isiOSAppOnMac
                        ? newPhase == .background
                        : newPhase != .active
                    if shouldLock && appLockEnabled && AppLock.storedPIN != nil {
                        isLocked = true
                    }
                    if newPhase == .active,
                       Date.now.timeIntervalSince(Self.lastActivationRefresh) > Self.activationRefreshInterval {
                        Self.lastActivationRefresh = .now
                        // Pending notifications and the synced calendar are
                        // device-local snapshots taken at the last local
                        // save — without this, edits synced from another
                        // device keep firing stale reminders forever, and
                        // dates that grow into the nearest-60 window are
                        // never scheduled.
                        NotificationManager.refreshFromContext(container.mainContext)
                        CalendarSyncManager.refreshFromContext(container.mainContext)
                    }
                }
        }
        .modelContainer(container)
    }
}

/// Hosts the main list and seeds the four starter folders on first launch.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var groups: [PersonGroup]
    // The hidden "You" node(s) the family tree roots on. Queried so first
    // launch (and a post-reset launch) can recreate it, and so duplicates
    // created by two devices seeding before sync can be folded together.
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfNodes: [Person]
    @AppStorage("didSeedDefaultGroups") private var didSeedDefaultGroups = false

    var body: some View {
        PeopleListView()
            .onAppear {
                seedDefaultGroupsIfNeeded()
                mergeDuplicateBuiltInGroups()
                ensureSelfNode()
                #if DEBUG
                StressSeeder.seedIfRequested(context)
                #endif
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    mergeDuplicateBuiltInGroups()
                    ensureSelfNode()
                }
            }
    }

    /// Guarantees exactly one hidden self node. Creates it when none exists
    /// (first launch, or after a full reset); if two devices each seeded one
    /// before syncing, keeps the earliest and removes edgeless duplicates —
    /// the same convention as the built-in folders.
    private func ensureSelfNode() {
        if selfNodes.isEmpty {
            let me = Person(name: "You")
            me.isSelf = true
            context.insert(me)
            try? context.save()
        } else if selfNodes.count > 1 {
            let survivors = selfNodes.sorted { $0.createdAt < $1.createdAt }
            var changed = false
            for extra in survivors.dropFirst() where extra.edgesAsParentArray.isEmpty
                && extra.edgesAsChildArray.isEmpty
                && extra.partnershipsAsAArray.isEmpty
                && extra.partnershipsAsBArray.isEmpty {
                context.delete(extra)
                changed = true
            }
            if changed { try? context.save() }
        }
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

    /// A second device seeds its own starter folders before the first
    /// device's records sync down (the seed flag is device-local and
    /// CloudKit can't enforce uniqueness), leaving two of each built-in
    /// folder. Fold empty duplicates into the copy people are filed in.
    /// Only empty copies are ever deleted, and only when a non-empty
    /// same-name copy exists — an indistinguishable empty-empty pair is
    /// left alone, because two devices deleting "either one" concurrently
    /// could sync away both.
    private func mergeDuplicateBuiltInGroups() {
        var byName: [String: [PersonGroup]] = [:]
        for group in groups where group.isBuiltIn {
            byName[group.name.trimmed.lowercased(), default: []].append(group)
        }
        var changed = false
        for copies in byName.values where copies.count > 1 {
            guard copies.contains(where: { !$0.peopleArray.isEmpty }) else { continue }
            for copy in copies where copy.peopleArray.isEmpty {
                context.delete(copy)
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }
}
