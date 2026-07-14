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

    @State private var loadedInitial = false

    struct DraftDate: Identifiable {
        let id = UUID()
        var label = ""
        var date = Date.now
    }

    struct DraftFamilyMember: Identifiable {
        let id = UUID()
        var name = ""
        var relation = "Mother"
    }

    enum PickTarget: Identifiable {
        case partner
        case member(Int)
        var id: String {
            switch self {
            case .partner: return "partner"
            case .member(let index): return "member-\(index)"
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
                    Picker("They're your…", selection: $relationshipToUser) {
                        Text("Not set").tag("")
                        ForEach(FamilyRelation.presets, id: \.self) { label in
                            Text(label).tag(label)
                        }
                    }
                } header: {
                    Text("Relationship to You")
                } footer: {
                    Text("Places them on your family tree, which builds itself from these labels.")
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
                    TextField("Children", text: $childrenNames, axis: .vertical)
                    TextField("Other family (parents, siblings…)", text: $otherFamily, axis: .vertical)
                    ForEach(draftFamilyMembers.indices, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $draftFamilyMembers[index].name)
                            Button {
                                pickerTarget = .member(index)
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Theme.aegean)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Link an existing person")
                            Picker("", selection: $draftFamilyMembers[index].relation) {
                                ForEach(FamilyRelation.presets, id: \.self) { label in
                                    Text(label).tag(label)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .onDelete { draftFamilyMembers.remove(atOffsets: $0) }
                    Button {
                        draftFamilyMembers.append(DraftFamilyMember())
                    } label: {
                        Label("Add Family Member", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Family")
                } footer: {
                    Text("Named members (with their relation to this person) build their family tree; partner and children join automatically. Tap \u{1F50D} to link someone already in Memento — the relationship is written to their profile too, so it shows both ways.")
                }

                Section("Work") {
                    TextField("Job title", text: $jobTitle)
                    TextField("Company", text: $company)
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

                Section("Contact") {
                    TextField("Phone", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Address", text: $address, axis: .vertical)
                }

                importantDatesSection

                Section {
                    Toggle("Mark as deceased", isOn: $isDeceased)
                } header: {
                    Text("Remembrance")
                } footer: {
                    Text("Grays their profile across the app and hides birthday countdowns.")
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
                    case .member(let index):
                        if draftFamilyMembers.indices.contains(index) {
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

    private var importantDatesSection: some View {
        Section {
            ForEach($draftDates) { $draft in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Label (e.g. Wedding anniversary)", text: $draft.label)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
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
            Text("Anniversaries, kids' birthdays, big events — anything worth remembering.")
        }
    }

    // MARK: - Setup

    private func loadInitial() {
        guard !loadedInitial else { return }
        loadedInitial = true
        guard let person else { return }

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
        draftFamilyMembers = person.familyMembersArray.map {
            DraftFamilyMember(name: $0.name, relation: $0.relation)
        }
        draftDates = person.importantDatesArray
            .sorted { $0.date < $1.date }
            .map { DraftDate(label: $0.label, date: $0.date) }
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
        target.relationshipToUser = relationshipToUser

        // Replace important dates with the edited set.
        let oldDates = target.importantDatesArray
        for old in oldDates {
            context.delete(old)
        }
        for draft in draftDates {
            let label = draft.label.trimmed.isEmpty ? "Important date" : draft.label.trimmed
            target.importantDatesArray.append(ImportantDate(label: label, date: draft.date))
        }

        // Replace family members with the edited set.
        let oldMembers = target.familyMembersArray
        for old in oldMembers {
            context.delete(old)
        }
        for member in draftFamilyMembers where !member.name.trimmed.isEmpty {
            target.familyMembersArray.append(FamilyMember(name: member.name.trimmed, relation: member.relation))
        }

        applyReciprocalLinks(around: target)

        try? context.save()
        NotificationManager.refreshFromContext(context)
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
