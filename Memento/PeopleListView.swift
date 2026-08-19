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
    @State private var showingAddPerson = false
    // Row deletion asks first, matching the detail view's confirmation.
    // Deleting a person permanently destroys their notes and photos.
    @State private var personPendingDelete: Person?
    @State private var showingFolders = false
    @State private var showingSettings = false
    @State private var showingCalendar = false
    @State private var showingMyProfile = false
    @AppStorage(Workspace.storageKey) private var storedWorkspace = Workspace.personal.rawValue

    // MARK: Sort & filter

    enum PeopleSort: String, CaseIterable, Identifiable {
        case alphabetical, age, city
        var id: String { rawValue }
        var label: String {
            switch self {
            case .alphabetical: return "Alphabetical"
            case .age: return "By Age"
            case .city: return "By City"
            }
        }
        var icon: String {
            switch self {
            case .alphabetical: return "textformat"
            case .age: return "birthday.cake"
            case .city: return "building.2"
            }
        }
    }

    @AppStorage("peopleSortOrder") private var sortRaw = PeopleSort.alphabetical.rawValue
    // Newline-joined names. Folder and city names can contain commas.
    // Name-keyed so the filter survives relaunch and sync; a renamed folder
    // simply un-hides, which errs on showing people rather than losing them.
    @AppStorage("hiddenFolderNames") private var hiddenFoldersRaw = ""
    @AppStorage("hiddenCityNames") private var hiddenCitiesRaw = ""
    /// Stands in for "no folder" in the hidden set. A real folder could be
    /// named "Ungrouped".
    private static let ungroupedFilterKey = "\u{1}ungrouped"

    private var sort: PeopleSort { PeopleSort(rawValue: sortRaw) ?? .alphabetical }
    private var hiddenFolders: Set<String> { Self.parseHidden(hiddenFoldersRaw) }
    private var hiddenCities: Set<String> { Self.parseHidden(hiddenCitiesRaw) }
    private var isFiltering: Bool { !hiddenFolders.isEmpty || !hiddenCities.isEmpty }

    private static func parseHidden(_ raw: String) -> Set<String> {
        Set(raw.components(separatedBy: "\n").filter { !$0.isEmpty })
    }

    private func toggleHidden(_ key: String, in raw: inout String) {
        var set = Self.parseHidden(raw)
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        raw = set.sorted().joined(separator: "\n")
    }

    private var workspace: Workspace {
        Workspace(rawValue: storedWorkspace) ?? .personal
    }

    private var workspacePeople: [Person] {
        // Hidden family-tree nodes (the "You" self node and un-profiled ghost
        // relatives) carry edges but are never listed as contacts.
        people.filter { $0.isBusiness == (workspace == .business) && !$0.isSelf && !$0.isGhost }
    }

    private var filteredPeople: [Person] {
        // Hidden folders and cities come out first. Hiding a group hides
        // its people everywhere, pinned included.
        let folders = hiddenFolders
        let cities = hiddenCities
        var result = workspacePeople
        if !folders.isEmpty || !cities.isEmpty {
            result = result.filter { person in
                if folders.contains(person.group?.name ?? Self.ungroupedFilterKey) { return false }
                let city = person.cityLabel
                if !city.isEmpty, cities.contains(city) { return false }
                return true
            }
        }
        // Match on the trimmed query too. A trailing space (easy via
        // dictation or QuickType) would otherwise hide exact-name matches.
        let query = searchText.trimmed
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.company.localizedCaseInsensitiveContains(query)
            || $0.jobTitle.localizedCaseInsensitiveContains(query)
            || $0.hobbies.localizedCaseInsensitiveContains(query)
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Bound so our custom header's collapse button can hide the sidebar.
    // The system's own toggle lived in the navigation bar we no longer
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
        // The editor's "Shown in" picker can move the open person to the
        // other workspace; the sidebar filter drops them instantly, which
        // would strand a Business-styled detail under a Personal list (or
        // vice versa). Clearing the selection when the person moves keeps
        // the switcher's invariant: the selection never crosses
        // workspaces.
        .onChange(of: selectedPerson?.isBusiness) {
            guard let person = selectedPerson, person.workspace != workspace else { return }
            selectedPerson = nil
        }
        // A deleted person must clear the selection, or the split view keeps
        // showing their stale profile: `isDeleted` is only true while the
        // deletion is pending, so the detail's own guard can't catch a
        // deletion that has already saved. The row-swipe path clears the
        // selection by hand; this catches every other route: the editor's
        // Delete Person, Settings' reset, a deletion synced from another
        // device. Keyed on the array, not its count: a synced batch can
        // delete one person and insert another in the same query update.
        .onChange(of: people) {
            guard let selected = selectedPerson,
                  !people.contains(where: { $0.persistentModelID == selected.persistentModelID })
            else { return }
            selectedPerson = nil
        }
    }

    private func row(for person: Person, isLast: Bool, showsAge: Bool = false) -> some View {
        PersonRow(
            person: person,
            isSelected: selectedPerson?.persistentModelID == person.persistentModelID,
            showsAge: showsAge,
            showsDivider: !isLast,
            onDelete: { personPendingDelete = person },
            onTogglePin: { togglePin(person) }
        )
        .tag(person)
    }

    // MARK: - Sidebar sections (one per sort order)

    /// The default view: folder sections in the folders' own order.
    /// Bucketed in a single pass. `filteredPeople` is name-sorted, and
    /// appending preserves that order per bucket.
    @ViewBuilder
    private func folderSections(_ people: [Person]) -> some View {
        let buckets: ([PersistentIdentifier: [Person]], [Person]) = {
            var byGroup: [PersistentIdentifier: [Person]] = [:]
            var ungrouped: [Person] = []
            for person in people {
                if let groupID = person.group?.persistentModelID {
                    byGroup[groupID, default: []].append(person)
                } else {
                    ungrouped.append(person)
                }
            }
            return (byGroup, ungrouped)
        }()

        ForEach(groups) { group in
            let members = buckets.0[group.persistentModelID] ?? []
            if !members.isEmpty {
                peopleSection(members, header: "\(group.name) · \(members.count)")
            }
        }
        if !buckets.1.isEmpty {
            peopleSection(buckets.1, header: "Ungrouped")
        }
    }

    /// Oldest first; anyone without a full birthday (none recorded, or no
    /// year) sits at the bottom, alphabetical among themselves.
    @ViewBuilder
    private func ageSection(_ people: [Person]) -> some View {
        let sorted = people.sorted { left, right in
            switch (left.sortableAge, right.sortableAge) {
            case let (l?, r?) where l != r: return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
        if !sorted.isEmpty {
            peopleSection(sorted, header: "Oldest First · \(sorted.count)", showsAges: true)
        }
    }

    /// City sections stand in for the folders: "City, Country · count",
    /// biggest city first. People with no city land in "No City" at the end.
    @ViewBuilder
    private func citySections(_ people: [Person]) -> some View {
        let buckets: ([(city: String, members: [Person])], [Person]) = {
            var byCity: [String: [Person]] = [:]
            var placeless: [Person] = []
            for person in people {
                let city = person.cityLabel
                if city.isEmpty { placeless.append(person) } else { byCity[city, default: []].append(person) }
            }
            let ordered = byCity
                .map { (city: $0.key, members: $0.value) }
                .sorted {
                    if $0.members.count != $1.members.count { return $0.members.count > $1.members.count }
                    return $0.city.localizedStandardCompare($1.city) == .orderedAscending
                }
            return (ordered, placeless)
        }()

        ForEach(buckets.0, id: \.city) { bucket in
            peopleSection(bucket.members, header: "\(bucket.city) · \(bucket.members.count)")
        }
        if !buckets.1.isEmpty {
            peopleSection(buckets.1, header: "No City · \(buckets.1.count)")
        }
    }

    private func peopleSection(_ members: [Person], header: String, showsAges: Bool = false) -> some View {
        Section(header) {
            ForEach(members) { person in
                row(for: person,
                    isLast: person.persistentModelID == members.last?.persistentModelID,
                    showsAge: showsAges)
            }
        }
    }

    // MARK: - Sidebar (people list)

    private var sidebar: some View {
        let visible = filteredPeople
        let pinned = visible.filter(\.isPinned)
        let unpinned = visible.filter { !$0.isPinned }
        return List(selection: $selectedPerson) {
            // Pinned people ride at the very top, whatever the sort, until
            // unpinned. Handy for someone you're about to see.
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { person in
                        row(for: person, isLast: person.persistentModelID == pinned.last?.persistentModelID)
                    }
                } header: {
                    Label("Pinned", systemImage: "pin.fill")
                }
            }

            switch sort {
            case .alphabetical: folderSections(unpinned)
            case .age: ageSection(unpinned)
            case .city: citySections(unpinned)
            }
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
        // pinned bar below is the header now: full-size profile circle,
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
                        ? "Add the people you meet through work: clients, colleagues, networking contacts. Keep notes on them just like everyone else."
                        : "Add your first person to start keeping notes about the people in your life.")
                } actions: {
                    Button("Add Person") { showingAddPerson = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if !searchText.trimmed.isEmpty && filteredPeople.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if filteredPeople.isEmpty && isFiltering {
                ContentUnavailableView {
                    Label("Everyone's Hidden", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Your filters hide every person in this workspace.")
                } actions: {
                    Button("Show Everyone") {
                        hiddenFoldersRaw = ""
                        hiddenCitiesRaw = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
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
                    filterSortMenu
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

    // MARK: - Filter & sort menu

    /// Every distinct city across the workspace, taken from the
    /// *unfiltered* list so a hidden city stays in the menu to be
    /// un-hidden. Biggest first, matching the city sections.
    private var allCities: [String] {
        var counts: [String: Int] = [:]
        for person in workspacePeople {
            let city = person.cityLabel
            if !city.isEmpty { counts[city, default: 0] += 1 }
        }
        return counts.keys.sorted {
            if counts[$0] != counts[$1] { return (counts[$0] ?? 0) > (counts[$1] ?? 0) }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func folderShownBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenFolders.contains(key) },
            set: { _ in toggleHidden(key, in: &hiddenFoldersRaw) }
        )
    }

    private func cityShownBinding(_ city: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenCities.contains(city) },
            set: { _ in toggleHidden(city, in: &hiddenCitiesRaw) }
        )
    }

    private var filterSortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortRaw) {
                ForEach(PeopleSort.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option.rawValue)
                }
            }
            Section("Show Folders") {
                ForEach(groups) { group in
                    Toggle(group.name, isOn: folderShownBinding(group.name))
                }
                Toggle("Ungrouped", isOn: folderShownBinding(Self.ungroupedFilterKey))
            }
            if !allCities.isEmpty {
                Section("Show Cities") {
                    ForEach(allCities, id: \.self) { city in
                        Toggle(city, isOn: cityShownBinding(city))
                    }
                }
            }
            if isFiltering {
                Button("Show Everyone", systemImage: "eye") {
                    hiddenFoldersRaw = ""
                    hiddenCitiesRaw = ""
                }
            }
        } label: {
            Image(systemName: isFiltering
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(workspace.accent)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isFiltering ? "Filter and sort, filters active" : "Filter and sort")
    }

    /// Your own circle, at the same 48pt as every row avatar, so it reads
    /// as a peer of the other portraits. Opens My Profile (edit + share).
    private var myProfileButton: some View {
        Button {
            showingMyProfile = true
        } label: {
            AvatarView(
                data: selfNodes.canonicalSelfNode?.profilePhotoData,
                name: myProfileDisplayName,
                size: 48,
                business: workspace == .business
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

    /// The pinned bar's tiles: calendar, folders, settings. (The family
    /// tree moved into My Profile, since it's your family it draws.)
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
                } label: {
                    Label(option.title, systemImage: option.icon)
                        // Both segments use one font (Business's sans) rather
                        // than each option's own display design. Otherwise
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
                LogoMark(size: 56)
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
        person.isPinned.toggle()
        try? context.save()
    }
}

// MARK: - Row

struct PersonRow: View {
    let person: Person
    var isSelected = false
    /// Age sort shows each person's age on the row. Without it the order
    /// would look arbitrary.
    var showsAge = false
    /// The last row of a section skips its divider, like a system list.
    var showsDivider = true
    var onDelete: () -> Void
    var onTogglePin: () -> Void

    /// Selection paints the row in the workspace accent, so every color in
    /// the row is chosen explicitly against it. Relying on `.primary` /
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
                desaturated: person.isDeceased,
                business: person.isBusiness
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
                    if person.isYourPartner {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? .white : Theme.terracotta)
                            .accessibilityLabel("Your partner")
                    }
                    if showsAge, let age = person.sortableAge {
                        Text("\(age)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(detailColor)
                            .accessibilityLabel("Age \(age)")
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
            // Borderless keeps the tap on the pin itself. A default button
            // inside a List row would swallow taps meant to select the row.
            .buttonStyle(.borderless)
            .accessibilityLabel(person.isPinned ? "Unpin \(person.name)" : "Pin \(person.name) to top")
        }
        // Generous row height: 3pt of breathing room read as cramped, and
        // left the first row's avatar hugging its card's top edge.
        .padding(.vertical, 10)
        // Zero the list's own vertical insets: they differ per platform
        // (iOS adds ~11pt each side, the Mac idiom nearly none), which put
        // the drawn divider close under a row's text but far above the
        // next row's. With the row's geometry fully ours, the divider sits
        // exactly on the boundary: the same 10pt from both neighbours,
        // everywhere.
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        // The boundary between rows is drawn by hand: SwiftUI's list
        // separators simply don't render on macOS ("Designed for iPad"),
        // so the system separator is hidden everywhere and this hairline
        // renders identically on iPhone, iPad and the Mac. It starts
        // under the text, tinted with the workspace's own neutral.
        .listRowSeparator(.hidden)
        .overlay(alignment: .bottom) {
            if showsDivider && !isSelected {
                Rectangle()
                    .fill((person.isBusiness ? Theme.graphite : Theme.bark).opacity(0.2))
                    .frame(height: 0.8)
                    .padding(.leading, 62)
            }
        }
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
