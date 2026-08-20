import SwiftUI
import SwiftData
import UIKit

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
    // but the PIN is ThisDeviceOnly in the Keychain (not restored). Locking
    // on the flag alone would brick the app until a delete-and-reinstall.
    @State private var isLocked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
        && AppLock.storedPIN != nil

    // Activation-driven refresh is throttled: on the Mac every window-focus
    // change is an activation, and a full EventKit rebuild per focus would
    // be constant churn. Save paths still refresh immediately.
    private static var lastActivationRefresh = Date.distantPast
    private static let activationRefreshInterval: TimeInterval = 15 * 60

    /// A backup restore or migration carries the UserDefaults flags to the
    /// new device but not the ThisDeviceOnly Keychain PIN. That leaves
    /// Settings claiming "Require a PIN" is ON while the app (correctly, see
    /// `isLocked` above) never locks. Reset the flags to match reality so
    /// Settings tells the truth and re-enabling routes through PIN setup;
    /// biometrics can't stay on without a PIN behind it.
    private func reconcileOrphanedLockFlag() {
        if appLockEnabled && AppLock.storedPIN == nil {
            appLockEnabled = false
            UserDefaults.standard.set(false, forKey: AppLock.useBiometricsKey)
        }
    }

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
                    reconcileOrphanedLockFlag()
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
                    // window takes focus. Locking there would demand the
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
                        // save. Without this, edits synced from another
                        // device keep firing stale reminders forever, and
                        // dates that grow into the nearest-60 window are
                        // never scheduled.
                        NotificationManager.refreshFromContext(container.mainContext)
                        CalendarSyncManager.refreshFromContext(container.mainContext)
                    }
                    // Anonymous session counting. Its own 30-minute gap
                    // logic keeps Mac focus churn from inflating anything.
                    if newPhase == .active {
                        UsageAnalytics.appBecameActive()
                    } else {
                        UsageAnalytics.appLeftForeground()
                    }
                }
        }
        .modelContainer(container)
    }
}

/// Guarantees exactly one hidden self node. Creates it when none exists
/// (first launch, or after a full reset). When two devices each seeded and
/// *used* their own "You" before CloudKit merged, deleting only edgeless
/// duplicates left both forever. The pedigree, My Profile and new edges
/// could then each land on a different one. Duplicates are now merged:
/// their edges re-point onto the canonical (earliest-created) node, profile
/// fields the keeper lacks carry over, and only then is the duplicate
/// deleted.
enum SelfNodeMaintenance {
    static func ensure(_ context: ModelContext, selfNodes: [Person]) {
        guard !selfNodes.isEmpty else {
            let me = Person(name: "You")
            me.isSelf = true
            context.insert(me)
            try? context.save()
            return
        }
        guard selfNodes.count > 1, let keeper = selfNodes.canonicalSelfNode else { return }

        for extra in selfNodes where extra !== keeper {
            // Re-point the duplicate's edges onto the keeper; an edge the
            // keeper already has (or one that would self-link) is dropped
            // rather than duplicated.
            for edge in extra.edgesAsParentArray {
                if let child = edge.child, child !== keeper,
                   !keeper.edgesAsParentArray.contains(where: { $0.child === child }) {
                    edge.parent = keeper
                } else {
                    context.delete(edge)
                }
            }
            for edge in extra.edgesAsChildArray {
                if let parent = edge.parent, parent !== keeper,
                   !keeper.edgesAsChildArray.contains(where: { $0.parent === parent }) {
                    edge.child = keeper
                } else {
                    context.delete(edge)
                }
            }
            for edge in extra.partnershipsAsAArray {
                if let other = edge.b, other !== keeper,
                   !keeper.partnershipsAsAArray.contains(where: { $0.b === other }),
                   !keeper.partnershipsAsBArray.contains(where: { $0.a === other }) {
                    edge.a = keeper
                } else {
                    context.delete(edge)
                }
            }
            for edge in extra.partnershipsAsBArray {
                if let other = edge.a, other !== keeper,
                   !keeper.partnershipsAsAArray.contains(where: { $0.b === other }),
                   !keeper.partnershipsAsBArray.contains(where: { $0.a === other }) {
                    edge.b = keeper
                } else {
                    context.delete(edge)
                }
            }

            // My Profile may have been filled in on the other device, so
            // carry anything the keeper is missing before deleting.
            let keeperUnnamed = keeper.name.trimmed.isEmpty || keeper.name == "You"
            if keeperUnnamed, !extra.name.trimmed.isEmpty, extra.name != "You" {
                keeper.name = extra.name
            }
            if keeper.profilePhotoData == nil { keeper.profilePhotoData = extra.profilePhotoData }
            if keeper.birthday == nil { keeper.birthday = extra.birthday }
            if keeper.phoneNumber.isEmpty { keeper.phoneNumber = extra.phoneNumber }
            if keeper.email.isEmpty { keeper.email = extra.email }
            if keeper.address.isEmpty { keeper.address = extra.address }
            if keeper.jobTitle.isEmpty { keeper.jobTitle = extra.jobTitle }
            if keeper.company.isEmpty { keeper.company = extra.company }
            if keeper.hobbies.isEmpty { keeper.hobbies = extra.hobbies }
            if keeper.hometown.isEmpty { keeper.hometown = extra.hometown }
            if keeper.foodPreferences.isEmpty { keeper.foodPreferences = extra.foodPreferences }
            if keeper.partnerName.isEmpty { keeper.partnerName = extra.partnerName }
            if keeper.childrenNames.isEmpty { keeper.childrenNames = extra.childrenNames }
            if keeper.otherFamily.isEmpty { keeper.otherFamily = extra.otherFamily }
            if keeper.howWeMet.isEmpty { keeper.howWeMet = extra.howWeMet }

            // The duplicate's to-many rows (important dates, contact fields,
            // family rows, notes, projects) cascade-delete with it, so
            // re-home them onto the keeper. Nothing entered on the other
            // device is lost that way. A row the keeper already holds an
            // identical copy of (both devices entered the same thing)
            // cascades away instead of duplicating.
            for date in extra.importantDatesArray
            where !keeper.importantDatesArray.contains(where: {
                $0.label == date.label && $0.date == date.date
            }) {
                date.person = keeper
            }
            for member in extra.familyMembersArray
            where !keeper.familyMembersArray.contains(where: {
                $0.name == member.name && $0.relation == member.relation
            }) {
                member.person = keeper
            }
            for field in extra.contactFieldsArray
            where !keeper.contactFieldsArray.contains(where: {
                $0.kind == field.kind && $0.value == field.value
            }) {
                field.person = keeper
            }
            for note in extra.notesArray {
                note.person = keeper
            }
            for project in extra.projectsArray
            where !keeper.projectsArray.contains(where: {
                $0.name == project.name && $0.isCompleted == project.isCompleted
            }) {
                project.person = keeper
            }

            context.delete(extra)
        }
        try? context.save()
    }
}

/// Hosts the main list and seeds the four starter folders on first launch.
struct RootView: View {
    // Mirrors MementoApp's activation-refresh throttle (see the comment
    // there) for the family-graph dedupe pass.
    private static var lastGraphDedupe = Date.distantPast
    private static let graphDedupeInterval: TimeInterval = 15 * 60

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var groups: [PersonGroup]
    // The hidden "You" node(s) the family tree roots on. Queried so first
    // launch (and a post-reset launch) can recreate it, and so duplicates
    // created by two devices seeding before sync can be folded together.
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfNodes: [Person]
    @AppStorage("didSeedDefaultGroups") private var didSeedDefaultGroups = false
    @AppStorage("didAdoptStarterFolderOrder") private var didAdoptStarterFolderOrder = false
    // A profile card arriving via AirDrop/"Open in Memento" (the app is
    // registered as a plain-text viewer for exactly this).
    @State private var incomingProfile: ParsedProfile?
    @State private var showingUnrecognizedFile = false

    var body: some View {
        PeopleListView()
            .onOpenURL { url in
                if let profile = ProfileCard.load(from: url) {
                    incomingProfile = profile
                } else {
                    // The user deliberately opened a file in Memento; a
                    // silent no-op would read as the app being broken.
                    showingUnrecognizedFile = true
                }
            }
            .sheet(item: $incomingProfile) { profile in
                ProfileImportSheet(profile: profile)
            }
            .alert("Not a Memento Profile", isPresented: $showingUnrecognizedFile) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Memento can open profile cards shared from another Memento. This text file isn't one.")
            }
            .onAppear {
                retireLogoColorScheme()
                seedDefaultGroupsIfNeeded()
                adoptStarterFolderOrderIfUntouched()
                mergeDuplicateBuiltInGroups()
                ensureSelfNode()
                #if DEBUG
                StressSeeder.seedIfRequested(context)
                #endif
                FamilyGraphMigration.runIfNeeded(context)
                // Two devices migrating/editing before first sync can mint
                // the same ghost (and its edges) twice. CloudKit merges
                // the records but never dedups them.
                FamilyGraphMaintenance.dedupe(context)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    mergeDuplicateBuiltInGroups()
                    ensureSelfNode()
                    // Throttled like the app-level refreshers: on the Mac
                    // every window focus is an activation, and a full-graph
                    // dedupe per focus would be constant churn (and could
                    // race an open links editor's unsaved draft ghosts).
                    if Date.now.timeIntervalSince(Self.lastGraphDedupe) > Self.graphDedupeInterval {
                        Self.lastGraphDedupe = .now
                        FamilyGraphMaintenance.dedupe(context)
                    }
                }
            }
    }

    private func ensureSelfNode() {
        SelfNodeMaintenance.ensure(context, selfNodes: selfNodes)
    }

    /// The icon-recolor feature is gone. One-time cleanup: forget any stored
    /// scheme and restore the primary Home Screen icon, so every logo is
    /// the default again, in-app and on the Home Screen.
    private func retireLogoColorScheme() {
        if UserDefaults.standard.object(forKey: "logoColorScheme") != nil {
            UserDefaults.standard.removeObject(forKey: "logoColorScheme")
        }
        if UIApplication.shared.supportsAlternateIcons,
           UIApplication.shared.alternateIconName != nil {
            UIApplication.shared.setAlternateIconName(nil)
        }
    }

    /// Existing installs were seeded with Family last. Move it to the top,
    /// but only for someone who never touched the order, which means the
    /// folders must still be exactly the four originals, still in exactly the
    /// order they were seeded in. Any rename, addition, deletion or drag and
    /// this leaves well alone: their arrangement is theirs.
    private func adoptStarterFolderOrderIfUntouched() {
        guard !didAdoptStarterFolderOrder else { return }
        didAdoptStarterFolderOrder = true

        let legacyOrder = ["Close Friends", "Friends", "Work Colleagues", "Family"]
        let current = groups.sorted { $0.sortOrder < $1.sortOrder }
        guard current.map(\.name) == legacyOrder, current.allSatisfy(\.isBuiltIn) else { return }

        for group in current {
            guard let index = PersonGroup.starterFolderNames.firstIndex(of: group.name) else { return }
            group.sortOrder = index
        }
        try? context.save()
    }

    private func seedDefaultGroupsIfNeeded() {
        guard !didSeedDefaultGroups else { return }
        guard groups.isEmpty else {
            // Folders already exist (synced down from another device).
            // Latch the flag so this device never "helpfully" re-seeds the
            // built-ins after the user deliberately deletes every folder.
            didSeedDefaultGroups = true
            return
        }
        for (index, name) in PersonGroup.starterFolderNames.enumerated() {
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
    /// same-name copy exists. An indistinguishable empty-empty pair is left
    /// alone, because two devices deleting "either one" concurrently could
    /// sync away both.
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
