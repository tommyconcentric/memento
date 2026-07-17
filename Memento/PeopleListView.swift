import SwiftUI
import SwiftData

/// The app's main scaffold: a split view that collapses to a stack on
/// iPhone and shows the people list beside the open profile on iPad
/// and Mac.
struct PeopleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\PersonGroup.sortOrder)]) private var groups: [PersonGroup]
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]

    @State private var selectedPerson: Person?
    @State private var searchText = ""
    // People unpinned from the list stay in the Pinned section until the
    // user leaves the list, so a stray tap on the pin is easy to undo in
    // place instead of the row instantly jumping back to its folder.
    @State private var recentlyUnpinned: Set<PersistentIdentifier> = []
    @State private var showingAddPerson = false
    @State private var showingFolders = false
    @State private var showingSettings = false
    @State private var showingTree = false
    @State private var showingCalendar = false
    @State private var showingImport = false
    @State private var showingAbout = false
    @AppStorage("logoColorScheme") private var storedColorScheme = LogoColorScheme.default.rawValue
    @AppStorage(Workspace.storageKey) private var storedWorkspace = Workspace.personal.rawValue

    private var logoColorScheme: LogoColorScheme {
        LogoColorScheme(rawValue: storedColorScheme) ?? .default
    }

    private var workspace: Workspace {
        Workspace(rawValue: storedWorkspace) ?? .personal
    }

    private var workspacePeople: [Person] {
        people.filter { $0.isBusiness == (workspace == .business) }
    }

    /// True while any sheet covers the list — the moment the user has
    /// "navigated away" and pending unpins can settle into their folders.
    private var isCoveredBySheet: Bool {
        showingAddPerson || showingFolders || showingSettings || showingTree
            || showingCalendar || showingImport || showingAbout
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

    var body: some View {
        NavigationSplitView {
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
        .sheet(isPresented: $showingTree) {
            MyFamilyTreeView()
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarView()
        }
        .sheet(isPresented: $showingImport) {
            ImportContactsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
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
            onDelete: { delete(person) },
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Memento")
        .searchable(text: $searchText, prompt: "Search by name, company, hobby")
        .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    showingAbout = true
                } label: {
                    LogoMark(size: 27, colorScheme: logoColorScheme)
                }
                .accessibilityLabel("About Memento")
                Menu {
                    ForEach(Workspace.allCases, id: \.self) { option in
                        Button {
                            // Re-picking the active workspace is a no-op;
                            // don't throw away the open person for it.
                            guard option != workspace else { return }
                            storedWorkspace = option.rawValue
                            selectedPerson = nil
                            recentlyUnpinned.removeAll()
                        } label: {
                            if option == workspace {
                                Label("Memento \(option.title)", systemImage: "checkmark")
                            } else {
                                Label("Memento \(option.title)", systemImage: option.icon)
                            }
                        }
                    }
                } label: {
                    // HStack rather than Label: toolbars collapse Labels
                    // to their icon, and the whole point of this badge is
                    // the word next to the logo.
                    HStack(spacing: 4) {
                        Image(systemName: workspace.icon)
                        Text(workspace.title)
                    }
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(workspace.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(workspace.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .accessibilityLabel("Switch between Memento Personal and Memento Business")
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                Button {
                    showingFolders = true
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Manage folders")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingTree = true
                } label: {
                    Image(systemName: "tree")
                }
                .accessibilityLabel("My family tree")
                Button {
                    showingCalendar = true
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Important dates calendar")
                Menu {
                    Button("New Person", systemImage: "person.badge.plus") {
                        showingAddPerson = true
                    }
                    Button("Import Contacts…", systemImage: "square.and.arrow.down") {
                        showingImport = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add or import people")
            }
        }
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
    }

    private var detailPlaceholder: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                LogoMark(size: 56, colorScheme: logoColorScheme)
                Text("Pick Someone")
                    .font(.system(.title3, design: .serif, weight: .semibold))
            }
        } description: {
            Text("Choose a person to see their details, family tree and notes.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
        .padding(.vertical, 3)
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
        .listRowBackground(isSelected ? selectionAccent : Theme.card)
    }
}
