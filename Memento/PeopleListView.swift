import SwiftUI
import SwiftData

/// The app's main scaffold: a split view that collapses to a stack on
/// iPhone and shows the people list beside the open profile on iPad
/// and Mac.
struct PeopleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\PersonGroup.sortOrder)]) private var groups: [PersonGroup]
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]
    // The hidden self node backs the "You" avatar in the pinned bar.
    @Query(filter: #Predicate<Person> { $0.isSelf }) private var selfNodes: [Person]

    @State private var selectedPerson: Person?
    @State private var searchText = ""
    // People unpinned from the list stay in the Pinned section until the
    // user leaves the list, so a stray tap on the pin is easy to undo in
    // place instead of the row instantly jumping back to its folder.
    @State private var recentlyUnpinned: Set<PersistentIdentifier> = []
    @State private var showingAddPerson = false
    // Row deletion asks first, matching the detail view's confirmation —
    // deleting a person permanently destroys their notes and photos.
    @State private var personPendingDelete: Person?
    @State private var showingFolders = false
    @State private var showingSettings = false
    @State private var showingCalendar = false
    @State private var showingMyProfile = false
    @AppStorage("logoColorScheme") private var storedColorScheme = LogoColorScheme.default.rawValue
    @AppStorage(Workspace.storageKey) private var storedWorkspace = Workspace.personal.rawValue

    private var logoColorScheme: LogoColorScheme {
        LogoColorScheme(rawValue: storedColorScheme) ?? .default
    }

    private var workspace: Workspace {
        Workspace(rawValue: storedWorkspace) ?? .personal
    }

    private var workspacePeople: [Person] {
        // Hidden family-tree nodes (the "You" self node and un-profiled ghost
        // relatives) carry edges but are never listed as contacts.
        people.filter { $0.isBusiness == (workspace == .business) && !$0.isSelf && !$0.isGhost }
    }

    /// True while any sheet covers the list — the moment the user has
    /// "navigated away" and pending unpins can settle into their folders.
    private var isCoveredBySheet: Bool {
        showingAddPerson || showingFolders || showingSettings
            || showingCalendar || showingMyProfile
    }

    private func showsInPinnedSection(_ person: Person) -> Bool {
        person.isPinned || recentlyUnpinned.contains(person.persistentModelID)
    }

    private var filteredPeople: [Person] {
        // Match on the trimmed query too — a trailing space (easy via
        // dictation or QuickType) would otherwise hide exact-name matches.
        let query = searchText.trimmed
        guard !query.isEmpty else { return workspacePeople }
        return workspacePeople.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.company.localizedCaseInsensitiveContains(query)
            || $0.jobTitle.localizedCaseInsensitiveContains(query)
            || $0.hobbies.localizedCaseInsensitiveContains(query)
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Bound so our custom header's collapse button can hide the sidebar —
    // the system's own toggle lived in the navigation bar we no longer
    // show. Starts at .all: .automatic resolves to detail-only in iPad
    // portrait, which would launch the app to an empty "Pick Someone".
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let person = selectedPerson, !person.isDeleted {
                NavigationStack {
                    PersonDetailView(person: person)
                }
            } else {
                detailPlaceholder
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            PersonEditorView(person: nil)
        }
        .sheet(isPresented: $showingFolders) {
            GroupsManagerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarView()
        }
        .sheet(isPresented: $showingMyProfile) {
            if let selfNode = selfNodes.canonicalSelfNode {
                MyProfileSheet(person: selfNode)
            }
        }
        .onChange(of: isCoveredBySheet) { _, covered in
            if covered {
                recentlyUnpinned.removeAll()
            }
        }
    }

    private func row(for person: Person) -> some View {
        PersonRow(
            person: person,
            isSelected: selectedPerson?.persistentModelID == person.persistentModelID,
            onDelete: { personPendingDelete = person },
            onTogglePin: { togglePin(person) }
        )
        .tag(person)
    }

    // MARK: - Sidebar (people list)

    private var sidebar: some View {
        List(selection: $selectedPerson) {
            // Pinned people ride at the very top, across every folder, until
            // unpinned — handy for someone you're about to see.
            let pinned = filteredPeople.filter { showsInPinnedSection($0) }
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { person in
                        row(for: person)
                    }
                } header: {
                    Label("Pinned", systemImage: "pin.fill")
                }
            }

            ForEach(groups) { group in
                let members = filteredPeople.filter {
                    !showsInPinnedSection($0) && $0.group?.persistentModelID == group.persistentModelID
                }
                if !members.isEmpty {
                    Section {
                        ForEach(members) { person in
                            row(for: person)
                        }
                    } header: {
                        Text("\(group.name) · \(members.count)")
                    }
                }
            }

            let ungrouped = filteredPeople.filter { !showsInPinnedSection($0) && $0.group == nil }
            if !ungrouped.isEmpty {
                Section("Ungrouped") {
                    ForEach(ungrouped) { person in
                        row(for: person)
                    }
                }
            }
        }
        .onDisappear {
            recentlyUnpinned.removeAll()
        }
        .confirmationDialog(
            personPendingDelete.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { personPendingDelete != nil },
                set: { if !$0 { personPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: personPendingDelete
        ) { person in
            Button("Delete", role: .destructive) { delete(person) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("All notes and photos for this person will be deleted too.")
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(workspace.background)
        // The sidebar's navigation bar is hidden entirely: its height caps
        // any toolbar view (the Mac titlebar clipped a row-sized avatar),
        // and its auto-generated "…" overflow is broken there anyway. The
        // pinned bar below is the header now — full-size profile circle,
        // wordmark, sidebar toggle and search, all on one designed surface.
        .toolbar(.hidden, for: .navigationBar)
        .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        .overlay {
            if workspacePeople.isEmpty {
                ContentUnavailableView {
                    Label(
                        workspace == .business ? "No Business Contacts Yet" : "No People Yet",
                        systemImage: workspace.icon
                    )
                } description: {
                    Text(workspace == .business
                        ? "Add the people you meet through work — clients, colleagues, networking contacts — and keep notes on them just like everyone else."
                        : "Add your first person to start keeping notes about the people in your life.")
                } actions: {
                    Button("Add Person") { showingAddPerson = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if !searchText.trimmed.isEmpty && filteredPeople.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        // Pinned above the list rather than a toolbar item: the toolbar
        // collapses into an overflow "…" menu when space is tight (always
        // on iPad and the Mac), which hid which workspace you were in.
        // This bar makes the active mode readable at a glance and the
        // switch a single visible tap, on every device.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                // Header row: your circle at full row-avatar size in the
                // top-left corner, the wordmark beside it, and (in regular
                // width) a collapse button standing in for the system
                // toggle the hidden navigation bar used to provide.
                HStack(spacing: 12) {
                    myProfileButton
                    Text("Memento")
                        .font(.system(.title3, design: workspace.displayFontDesign, weight: .semibold))
                    Spacer()
                    if horizontalSizeClass == .regular {
                        Button {
                            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                        } label: {
                            Image(systemName: "sidebar.leading")
                                .font(.title3)
                                .foregroundStyle(workspace.accent)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hide sidebar")
                    }
                }
                searchField
                // The switcher owns this row (with the "+"): full width
                // keeps "Personal"/"Business" from wrapping at any sidebar
                // width.
                HStack(spacing: 10) {
                    workspaceSwitcher
                    addPersonButton
                }
                // Tree and calendar sit on their own row as two wide icon
                // tiles: crammed onto the switcher's row they squeeze it
                // until "Personal"/"Business" wrap. A dedicated row keeps
                // them direct, generously tappable, and balanced at any
                // sidebar width.
                HStack(spacing: 10) {
                    calendarButton
                    foldersButton
                    settingsButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(workspace.background)
        }
    }

    /// Your own circle — the same 48pt as every row avatar, so it reads as
    /// a peer of the other portraits. Opens My Profile (edit + share).
    private var myProfileButton: some View {
        Button {
            showingMyProfile = true
        } label: {
            AvatarView(
                data: selfNodes.canonicalSelfNode?.profilePhotoData,
                name: myProfileDisplayName,
                size: 48
            )
            .overlay(Circle().strokeBorder(workspace.accent.opacity(0.45), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My profile")
    }

    /// Replaces .searchable, which rendered inside the navigation bar this
    /// sidebar no longer shows. Always visible, same card treatment as the
    /// pinned tiles.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by name, company, hobby", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(workspace.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    /// The pinned bar's tiles (the family tree moved into My Profile — it's
    /// your family it draws): calendar, folders, settings.
    private var calendarButton: some View {
        Button {
            showingCalendar = true
        } label: {
            secondaryPinnedIcon("calendar")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Important dates calendar")
    }

    /// Folders and settings live in the pinned bar for the same reason as the
    /// tree and calendar: as toolbar items they'd collapse into the
    /// non-functional "…" overflow menu on iPad and the Mac.
    private var foldersButton: some View {
        Button {
            showingFolders = true
        } label: {
            secondaryPinnedIcon("folder")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage folders")
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            secondaryPinnedIcon("gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    /// Shared look for the pinned bar's secondary actions: a card-filled
    /// square with an accent glyph and hairline border, so they read as
    /// siblings of the "+" without competing with its filled emphasis.
    private func secondaryPinnedIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.headline)
            .foregroundStyle(workspace.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(workspace.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Lives in the pinned bar for the same reason as the switcher: a
    /// toolbar "+" disappears into the overflow "…" menu on iPad and the
    /// Mac, and adding someone is the app's most basic action.
    private var addPersonButton: some View {
        Button {
            showingAddPerson = true
        } label: {
            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(workspace.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add person")
    }

    private var myProfileDisplayName: String {
        let name = selfNodes.canonicalSelfNode?.name.trimmed ?? ""
        return name.isEmpty ? "You" : name
    }

    private var workspaceSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Workspace.allCases, id: \.self) { option in
                let isActive = option == workspace
                Button {
                    // Re-picking the active workspace is a no-op; don't
                    // throw away the open person for it.
                    guard option != workspace else { return }
                    storedWorkspace = option.rawValue
                    selectedPerson = nil
                    recentlyUnpinned.removeAll()
                } label: {
                    Label(option.title, systemImage: option.icon)
                        // Both segments use one font (Business's sans) rather
                        // than each option's own display design — otherwise
                        // "Personal" renders in serif and "Business" in sans,
                        // which reads as a mismatch inside a single control.
                        .font(.system(.subheadline, design: Workspace.business.displayFontDesign).weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? .white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isActive ? option.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Memento \(option.title)")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(3)
        .background(workspace.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    private var detailPlaceholder: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                LogoMark(size: 56, colorScheme: logoColorScheme)
                Text("Pick Someone")
                    .font(.system(.title3, design: workspace.displayFontDesign, weight: .semibold))
            }
        } description: {
            Text("Choose a person to see their details, family tree and notes.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(workspace.background)
    }

    private func delete(_ person: Person) {
        if selectedPerson?.persistentModelID == person.persistentModelID {
            selectedPerson = nil
        }
        context.delete(person)
        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
    }

    private func togglePin(_ person: Person) {
        if person.isPinned {
            person.isPinned = false
            recentlyUnpinned.insert(person.persistentModelID)
        } else {
            person.isPinned = true
            recentlyUnpinned.remove(person.persistentModelID)
        }
        try? context.save()
    }
}

// MARK: - Row

struct PersonRow: View {
    let person: Person
    var isSelected = false
    var onDelete: () -> Void
    var onTogglePin: () -> Void

    /// Selection paints the row in the workspace accent, so every color in
    /// the row is chosen explicitly against it — relying on `.primary` /
    /// `.secondary` is what made selected names vanish on the Mac, where the
    /// system flips row content to white over our custom row background.
    private var selectionAccent: Color {
        person.isBusiness ? Theme.graphite : Theme.aegean
    }

    private var nameColor: Color {
        if isSelected { return .white }
        return person.isDeceased ? Color.secondary : Color.primary
    }

    private var detailColor: Color {
        isSelected ? Color.white.opacity(0.8) : Color.secondary
    }

    private var pinColor: Color {
        if person.isPinned {
            return isSelected ? .white : Theme.gold
        }
        return isSelected ? Color.white.opacity(0.55) : Color.secondary.opacity(0.45)
    }

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(
                data: person.profilePhotoData,
                name: person.name,
                size: 48,
                desaturated: person.isDeceased
            )
            // Belt and braces against the accent fill: even a photo that
            // happens to be selection-blue keeps a visible edge.
            .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(person.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(nameColor)
                    if person.isDeceased {
                        Image(systemName: "leaf")
                            .font(.caption2)
                            .foregroundStyle(detailColor)
                    }
                }
                if !person.subtitle.isEmpty {
                    Text(person.subtitle)
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !person.isDeceased, let days = person.daysUntilNextBirthday, days <= 14 {
                Text(days == 0 ? "🎂 today" : "🎂 \(days)d")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Theme.bougainvillea)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isSelected ? Color.white.opacity(0.18) : Theme.bougainvillea.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }

            Button(action: onTogglePin) {
                Image(systemName: person.isPinned ? "pin.fill" : "pin")
                    .font(.callout)
                    .foregroundStyle(pinColor)
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            // Borderless keeps the tap on the pin itself — a default button
            // inside a List row would swallow taps meant to select the row.
            .buttonStyle(.borderless)
            .accessibilityLabel(person.isPinned ? "Unpin \(person.name)" : "Pin \(person.name) to top")
        }
        // Generous row height: 3pt of breathing room read as cramped, and
        // left the first row's avatar hugging its card's top edge.
        .padding(.vertical, 9)
        // The default separator starts past the avatar and all but
        // disappears — full-width and warm-tinted, it gives unselected
        // rows a discernible boundary.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .listRowSeparatorTint(Theme.bark.opacity(0.25))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onTogglePin) {
                Label(person.isPinned ? "Unpin" : "Pin", systemImage: person.isPinned ? "pin.slash" : "pin")
            }
            .tint(Theme.gold)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onTogglePin) {
                Label(person.isPinned ? "Unpin" : "Pin to Top", systemImage: person.isPinned ? "pin.slash" : "pin")
            }
        }
        .listRowBackground(isSelected ? selectionAccent : person.workspace.card)
    }
}
