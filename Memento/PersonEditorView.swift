import SwiftUI
import SwiftData
import PhotosUI

/// Creates a new person, or edits an existing one when `person` is set.
/// Covers the profile photo, folder and every quick-info field.
struct PersonEditorView: View {
    let person: Person?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PersonGroup.sortOrder)]) private var groups: [PersonGroup]

    // Profile
    @State private var name = ""
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var pickerTarget: PickTarget?
    @State private var selectedGroup: PersonGroup?
    @State private var isDeceased = false
    @State private var isBusiness = false
    @AppStorage(Workspace.storageKey) private var storedWorkspace = Workspace.personal.rawValue

    // Quick info
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    @State private var partnerName = ""
    @State private var childrenNames = ""
    @State private var otherFamily = ""
    @State private var jobTitle = ""
    @State private var company = ""
    @State private var hobbies = ""
    @State private var hometown = ""
    @State private var howWeMet = ""
    @State private var foodPreferences = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var address = ""
    @State private var relationshipToUser = ""
    @State private var draftFamilyMembers: [DraftFamilyMember] = []
    @State private var draftDates: [DraftDate] = []
    @State private var draftContacts: [DraftContact] = []
    @State private var draftProjects: [DraftProject] = []

    @State private var loadedInitial = false

    // "Other…" reveals a free-text box; the typed label is stored in the
    // same relationshipToUser field but never charts (see isChartable).
    @State private var isOtherRelationship = false
    @State private var customRelationship = ""
    private static let otherRelationshipTag = "__other__"

    /// Business profiles pick from working relationships (they build the
    /// corporate ladder); personal ones keep the family vocabulary.
    private var relationshipPresets: [String] {
        isBusiness ? BusinessRelation.presets : FamilyRelation.presets
    }

    /// Routes the "Other…" row into the free-text state; preset picks land
    /// in relationshipToUser directly.
    private var relationshipPickerBinding: Binding<String> {
        Binding(
            get: { isOtherRelationship ? Self.otherRelationshipTag : relationshipToUser },
            set: { picked in
                if picked == Self.otherRelationshipTag {
                    isOtherRelationship = true
                } else {
                    isOtherRelationship = false
                    relationshipToUser = picked
                }
            }
        )
    }

    /// Values that don't fit the current workspace's presets (a custom
    /// label, or one picked before the workspace toggle was flipped)
    /// present as "Other…" with the text box pre-filled.
    private func adoptCustomRelationshipIfNeeded() {
        guard !relationshipToUser.isEmpty, !relationshipPresets.contains(relationshipToUser) else { return }
        isOtherRelationship = true
        customRelationship = relationshipToUser
    }

    // Legacy free-text family fields are only shown when they already
    // hold data from an earlier version — new profiles record family
    // through named members instead. Captured once at load so a field
    // doesn't vanish mid-edit the moment it's cleared.
    @State private var showsLegacyChildren = false
    @State private var showsLegacyOtherFamily = false

    struct DraftDate: Identifiable {
        let id = UUID()
        var label = ""
        var date = Date.now
        // Carried through the save's delete-and-recreate so an edit doesn't
        // silently reset the per-date reminder toggle from Quick Info.
        var remindersEnabled = true
    }

    struct DraftContact: Identifiable {
        let id = UUID()
        var kind: ContactField.Kind = .phone
        var value = ""
        var starred = false
    }

    struct DraftFamilyMember: Identifiable {
        let id = UUID()
        var name = ""
        var relation = "Mother"
    }

    struct DraftProject: Identifiable {
        let id = UUID()
        var name = ""
        var isCompleted = false
    }

    enum PickTarget: Identifiable {
        case partner
        case member(UUID)
        var id: String {
            switch self {
            case .partner: return "partner"
            case .member(let memberID): return "member-\(memberID.uuidString)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section("Name & Folder") {
                    TextField("Name", text: $name)
                    Picker("Folder", selection: $selectedGroup) {
                        Text("None").tag(PersonGroup?.none)
                        ForEach(groups) { group in
                            Text(group.name).tag(Optional(group))
                        }
                    }
                }

                Section {
                    Picker("Shown in", selection: $isBusiness) {
                        Text("Memento Personal").tag(false)
                        Text("Memento Business").tag(true)
                    }
                } header: {
                    Text("Workspace")
                } footer: {
                    Text("Business contacts live in Memento Business; switch from the badge by the logo.")
                }

                Section {
                    Picker("They're your…", selection: relationshipPickerBinding) {
                        Text("Not set").tag("")
                        ForEach(relationshipPresets, id: \.self) { label in
                            Text(label).tag(label)
                        }
                        Text("Other…").tag(Self.otherRelationshipTag)
                    }
                    if isOtherRelationship {
                        TextField(
                            isBusiness ? "e.g. Co-founder at my old startup" : "e.g. Childhood neighbour",
                            text: $customRelationship
                        )
                    }
                } header: {
                    Text(isBusiness ? "Working Relationship to You" : "Family Relationship to You")
                } footer: {
                    Text(isBusiness
                        ? "Places them on your corporate ladder. Other… is custom and won't join the ladder."
                        : "For relatives only — places them on your family tree. Leave “Not set” for non-family; Other… is custom and won't join the tree.")
                }

                Section("Birthday") {
                    Toggle("Set a birthday", isOn: $hasBirthday.animation())
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                Section {
                    HStack {
                        TextField("Partner / spouse", text: $partnerName)
                        Button {
                            pickerTarget = .partner
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.aegean)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Link an existing person as partner")
                    }
                    // Identified by the draft's stable id, like the other
                    // draft lists — index-based identity shifts every later
                    // row's bindings when one is removed mid-edit.
                    ForEach($draftFamilyMembers) { $member in
                        HStack {
                            TextField("Name", text: $member.name)
                            Button {
                                pickerTarget = .member(member.id)
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Theme.aegean)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Link an existing person")
                            Picker("", selection: $member.relation) {
                                ForEach(FamilyRelation.presets, id: \.self) { label in
                                    Text(label).tag(label)
                                }
                            }
                            .labelsHidden()
                            rowDeleteButton(label: "Remove this family member") {
                                draftFamilyMembers.removeAll { $0.id == member.id }
                            }
                        }
                    }
                    .onDelete { draftFamilyMembers.remove(atOffsets: $0) }
                    Button {
                        draftFamilyMembers.append(DraftFamilyMember())
                    } label: {
                        Label("Add Family Member", systemImage: "plus.circle")
                    }
                    if showsLegacyChildren {
                        TextField("Children", text: $childrenNames, axis: .vertical)
                    }
                    if showsLegacyOtherFamily {
                        TextField("Other family (parents, siblings…)", text: $otherFamily, axis: .vertical)
                    }
                } header: {
                    Text("Family")
                } footer: {
                    Text("Builds this person's family tree. Tap \u{1F50D} to link someone in Memento — the link is written both ways.")
                }

                Section("Work") {
                    TextField("Job title", text: $jobTitle)
                    TextField("Company", text: $company)
                }

                if isBusiness {
                    projectsSection
                }

                Section("Hobbies & Interests") {
                    TextField("Running, jazz, board games…", text: $hobbies, axis: .vertical)
                }

                Section("Background") {
                    TextField("Hometown", text: $hometown)
                    TextField("How we met", text: $howWeMet, axis: .vertical)
                }

                Section("Food & Drink") {
                    TextField("Favourites, allergies, coffee order…", text: $foodPreferences, axis: .vertical)
                }

                Section {
                    TextField("Phone", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Address", text: $address, axis: .vertical)

                    ForEach($draftContacts) { $draft in
                        HStack {
                            Picker("", selection: $draft.kind) {
                                ForEach(ContactField.Kind.allCases, id: \.self) { kind in
                                    Image(systemName: kind.icon).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            TextField(draft.kind.label, text: $draft.value, axis: draft.kind == .address ? .vertical : .horizontal)
                                .keyboardType(keyboard(for: draft.kind))
                                .textInputAutocapitalization(draft.kind == .email ? .never : .sentences)
                                .autocorrectionDisabled(draft.kind == .email)
                            Button {
                                toggleStar(draft.id)
                            } label: {
                                Image(systemName: draft.starred ? "star.fill" : "star")
                                    .foregroundStyle(draft.starred ? Theme.gold : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(draft.starred
                                ? "Remove preference from this \(draft.kind.label.lowercased())"
                                : "Prefer this \(draft.kind.label.lowercased())")
                            rowDeleteButton(label: "Remove this \(draft.kind.label.lowercased())") {
                                draftContacts.removeAll { $0.id == draft.id }
                            }
                        }
                    }
                    .onDelete { draftContacts.remove(atOffsets: $0) }

                    Menu {
                        ForEach(ContactField.Kind.allCases, id: \.self) { kind in
                            Button {
                                draftContacts.append(DraftContact(kind: kind))
                            } label: {
                                Label("Add \(kind.label)", systemImage: kind.icon)
                            }
                        }
                    } label: {
                        Label("Add Phone, Email or Address", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Contact")
                } footer: {
                    Text("The first phone, email and address show in Quick Info. Tap ★ to move another to the top.")
                }

                importantDatesSection

                Section {
                    Toggle("Mark as deceased", isOn: $isDeceased)
                } header: {
                    Text("Remembrance")
                } footer: {
                    Text("Grays their profile and hides birthday countdowns.")
                }
            }
            .navigationTitle(person == nil ? "New Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear(perform: loadInitial)
            .onChange(of: isBusiness) { _, _ in
                // Flipping the workspace swaps the preset list; a value
                // that no longer fits carries over as a custom "Other"
                // instead of silently blanking.
                if !isOtherRelationship {
                    adoptCustomRelationshipIfNeeded()
                }
            }
            .onChange(of: photoItem) { _, item in
                loadPhoto(item)
            }
            .sheet(isPresented: Binding(
                get: { pendingCropImage != nil },
                set: { if !$0 { pendingCropImage = nil } }
            )) {
                if let image = pendingCropImage {
                    PhotoCropperView(image: image) { data in
                        photoData = data
                    }
                }
            }
            .sheet(item: $pickerTarget) { target in
                PersonPickerSheet(excludeID: person?.persistentModelID) { picked in
                    switch target {
                    case .partner:
                        partnerName = picked.name
                    case .member(let memberID):
                        if let index = draftFamilyMembers.firstIndex(where: { $0.id == memberID }) {
                            draftFamilyMembers[index].name = picked.name
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    AvatarView(
                        data: photoData,
                        name: name.trimmed.isEmpty ? "?" : name,
                        size: 96
                    )
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(photoData == nil ? "Add Photo" : "Change Photo")
                            .font(.callout.weight(.medium))
                    }
                    if photoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            photoData = nil
                            photoItem = nil
                        }
                        .font(.footnote)
                    }
                }
                Spacer()
            }
        }
        .listRowBackground(Color.clear)
    }

    /// A click-reachable delete for repeating rows. Swipe-to-delete stays,
    /// but it's the only affordance a Mac mouse can't perform (the editor
    /// has no edit mode), which left rows unremovable on the Mac.
    private func rowDeleteButton(label: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(Theme.terracotta)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    /// One starred entry per kind: starring a row clears the star from its
    /// siblings of the same kind; tapping a starred row removes the star,
    /// falling back to the primary field as the preferred one.
    private func toggleStar(_ id: UUID) {
        guard let index = draftContacts.firstIndex(where: { $0.id == id }) else { return }
        let turningOn = !draftContacts[index].starred
        if turningOn {
            let kind = draftContacts[index].kind
            for sibling in draftContacts.indices where draftContacts[sibling].kind == kind {
                draftContacts[sibling].starred = false
            }
        }
        draftContacts[index].starred = turningOn
    }

    private func keyboard(for kind: ContactField.Kind) -> UIKeyboardType {
        switch kind {
        case .phone: return .phonePad
        case .email: return .emailAddress
        case .address: return .default
        }
    }

    private var projectsSection: some View {
        Section {
            ForEach($draftProjects) { $draft in
                HStack {
                    TextField("Project name", text: $draft.name)
                    Picker("", selection: $draft.isCompleted) {
                        Text("Ongoing").tag(false)
                        Text("Completed").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    rowDeleteButton(label: "Remove this project") {
                        draftProjects.removeAll { $0.id == draft.id }
                    }
                }
            }
            .onDelete { draftProjects.remove(atOffsets: $0) }

            Button {
                draftProjects.append(DraftProject())
            } label: {
                Label("Add Project", systemImage: "plus.circle")
            }
        } header: {
            Text("Projects")
        } footer: {
            Text("Work you share. Mark Completed when it wraps; it stays as history.")
        }
    }

    private var importantDatesSection: some View {
        Section {
            ForEach($draftDates) { $draft in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Label (e.g. Wedding anniversary)", text: $draft.label)
                        DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    }
                    rowDeleteButton(label: "Remove this date") {
                        draftDates.removeAll { $0.id == draft.id }
                    }
                }
            }
            .onDelete { draftDates.remove(atOffsets: $0) }

            Button {
                draftDates.append(DraftDate())
            } label: {
                Label("Add Important Date", systemImage: "plus.circle")
            }
        } header: {
            Text("Important Dates")
        } footer: {
            Text("Anniversaries, birthdays and big events.")
        }
    }

    // MARK: - Setup

    private func loadInitial() {
        guard !loadedInitial else { return }
        loadedInitial = true
        guard let person else {
            // New people join whichever workspace is currently open.
            isBusiness = storedWorkspace == Workspace.business.rawValue
            return
        }
        isBusiness = person.isBusiness

        name = person.name
        photoData = person.profilePhotoData
        selectedGroup = person.group
        isDeceased = person.isDeceased
        hasBirthday = person.birthday != nil
        if let existingBirthday = person.birthday {
            birthday = existingBirthday
        }
        partnerName = person.partnerName
        childrenNames = person.childrenNames
        otherFamily = person.otherFamily
        showsLegacyChildren = !person.childrenNames.trimmed.isEmpty
        showsLegacyOtherFamily = !person.otherFamily.trimmed.isEmpty
        jobTitle = person.jobTitle
        company = person.company
        hobbies = person.hobbies
        hometown = person.hometown
        howWeMet = person.howWeMet
        foodPreferences = person.foodPreferences
        phoneNumber = person.phoneNumber
        email = person.email
        address = person.address
        relationshipToUser = person.relationshipToUser
        adoptCustomRelationshipIfNeeded()
        draftFamilyMembers = person.familyMembersArray.map {
            DraftFamilyMember(name: $0.name, relation: $0.relation)
        }
        draftDates = person.importantDatesArray
            .sorted { $0.date < $1.date }
            .map { DraftDate(label: $0.label, date: $0.date, remindersEnabled: $0.remindersEnabled) }
        draftContacts = person.contactFieldsArray
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DraftContact(kind: ContactField.Kind(rawValue: $0.kind) ?? .phone, value: $0.value, starred: $0.isPreferred) }
        draftProjects = person.projectsArray
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DraftProject(name: $0.name, isCompleted: $0.isCompleted) }
    }

    // MARK: - Photo loading

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                pendingCropImage = uiImage
            }
            photoItem = nil
        }
    }

    // MARK: - Save

    private func save() {
        let target: Person
        if let person {
            target = person
        } else {
            let newPerson = Person(name: name.trimmed)
            context.insert(newPerson)
            target = newPerson
        }

        target.name = name.trimmed
        target.profilePhotoData = photoData
        target.group = selectedGroup
        target.isDeceased = isDeceased
        target.isBusiness = isBusiness
        target.birthday = hasBirthday ? birthday : nil
        target.partnerName = partnerName.trimmed
        target.childrenNames = childrenNames.trimmed
        target.otherFamily = otherFamily.trimmed
        target.jobTitle = jobTitle.trimmed
        target.company = company.trimmed
        target.hobbies = hobbies.trimmed
        target.hometown = hometown.trimmed
        target.howWeMet = howWeMet.trimmed
        target.foodPreferences = foodPreferences.trimmed
        target.phoneNumber = phoneNumber.trimmed
        target.email = email.trimmed
        target.address = address.trimmed
        target.relationshipToUser = isOtherRelationship ? customRelationship.trimmed : relationshipToUser

        // Replace important dates with the edited set.
        let oldDates = target.importantDatesArray
        for old in oldDates {
            context.delete(old)
        }
        for draft in draftDates {
            let label = draft.label.trimmed.isEmpty ? "Important date" : draft.label.trimmed
            let date = ImportantDate(label: label, date: draft.date)
            date.remindersEnabled = draft.remindersEnabled
            target.importantDatesArray.append(date)
        }

        // Replace family members with the edited set.
        let oldMembers = target.familyMembersArray
        for old in oldMembers {
            context.delete(old)
        }
        for member in draftFamilyMembers where !member.name.trimmed.isEmpty {
            target.familyMembersArray.append(FamilyMember(name: member.name.trimmed, relation: member.relation))
        }

        // Replace extra contact fields with the edited set (blank ones dropped).
        let oldContacts = target.contactFieldsArray
        for old in oldContacts {
            context.delete(old)
        }
        // A row's kind can change after it was starred, so two same-kind
        // stars are possible in the drafts — keep only the first per kind.
        var starredKinds: Set<String> = []
        for (index, draft) in draftContacts.enumerated() where !draft.value.trimmed.isEmpty {
            let field = ContactField(kind: draft.kind, value: draft.value.trimmed, sortOrder: index)
            if draft.starred, !starredKinds.contains(draft.kind.rawValue) {
                field.isPreferred = true
                starredKinds.insert(draft.kind.rawValue)
            }
            target.contactFieldsArray.append(field)
        }

        // Replace projects with the edited set (blank ones dropped).
        let oldProjects = target.projectsArray
        for old in oldProjects {
            context.delete(old)
        }
        for (index, draft) in draftProjects.enumerated() where !draft.name.trimmed.isEmpty {
            target.projectsArray.append(Project(name: draft.name.trimmed, isCompleted: draft.isCompleted, sortOrder: index))
        }

        applyReciprocalLinks(around: target)
        // Mirror the edited relationship/partner/children/family fields into
        // the Parentage/Partnership graph — the default pedigree tree draws
        // only from edges, and the one-time migration won't run again.
        FamilyEdgeSync.apply(around: target, context: context)

        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
        dismiss()
    }

    /// If a family member or partner names someone already in Memento,
    /// write the inverse relationship onto their profile so the link
    /// shows from both sides.
    private func applyReciprocalLinks(around target: Person) {
        let everyone = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        func find(_ name: String) -> Person? {
            let trimmed = name.trimmed
            guard !trimmed.isEmpty else { return nil }
            let matches = everyone.filter {
                $0.persistentModelID != target.persistentModelID &&
                $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }
            // Only auto-link on an unambiguous match — guessing among
            // several people sharing a name risks writing a fabricated
            // family member onto the wrong profile.
            return matches.count == 1 ? matches.first : nil
        }
        for member in target.familyMembersArray {
            guard let other = find(member.name) else { continue }
            let inverse = FamilyRelation.inverse(of: member.relation)
            if let existing = other.familyMembersArray.first(where: {
                $0.name.compare(target.name, options: .caseInsensitive) == .orderedSame
            }) {
                // Keep the reciprocal relation in sync if it was already
                // linked but the relation type changed since.
                existing.relation = inverse
            } else {
                other.familyMembersArray.append(FamilyMember(name: target.name, relation: inverse))
            }
        }
        if let other = find(target.partnerName), other.partnerName.trimmed.isEmpty {
            other.partnerName = target.name
        }
    }
}
