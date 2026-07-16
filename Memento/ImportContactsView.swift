import SwiftUI
import SwiftData
import Contacts
import ContactsUI
import UniformTypeIdentifiers
import UIKit

/// Import people from iOS Contacts (which is also where WhatsApp keeps its
/// contacts) or from a Facebook "Download Your Information" export / CSV.
/// You pick exactly who comes in and which folder they land in — nothing
/// imports without review.
struct ImportContactsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PersonGroup.sortOrder)]) private var groups: [PersonGroup]
    @Query private var existingPeople: [Person]

    @State private var candidates: [ImportCandidate] = []
    @State private var selectedGroup: PersonGroup?
    @State private var showingContactPicker = false
    @State private var showingFilePicker = false
    @State private var errorMessage: String?

    struct ImportCandidate: Identifiable {
        let id = UUID()
        var name: String
        var phone = ""
        var email = ""
        var address = ""
        var birthday: Date?
        var photoData: Data?
        var include = true
        var alreadyExists = false
    }

    private var selectedCount: Int {
        candidates.filter(\.include).count
    }

    private var allSelected: Bool {
        !candidates.isEmpty && candidates.allSatisfy(\.include)
    }

    private func setAllIncluded(_ included: Bool) {
        for index in candidates.indices {
            candidates[index].include = included
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    sourceOptions
                } else {
                    reviewList
                }
            }
            .background(Theme.background)
            .navigationTitle("Import Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !candidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(selectedCount)") { importSelected() }
                            .disabled(selectedCount == 0)
                    }
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker { handlePicked($0) }
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText]
            ) { result in
                handleFile(result)
            }
        }
    }

    // MARK: - Source options

    private var sourceOptions: some View {
        ScrollView {
            VStack(spacing: 14) {
                optionCard(
                    icon: "person.crop.circle.badge.plus",
                    title: "From iOS Contacts",
                    subtitle: "Pick exactly who to import — names, photos, numbers, emails, addresses and birthdays come along. WhatsApp uses your phone's contacts, so this covers your WhatsApp people too."
                ) {
                    showingContactPicker = true
                }

                optionCard(
                    icon: "doc.badge.plus",
                    title: "From Facebook Export or CSV",
                    subtitle: "Facebook no longer offers a live friends API, so use its \"Download Your Information\" export (the friends JSON — names import, add details after) or any CSV with name, birthday, phone, email, address columns."
                ) {
                    showingFilePicker = true
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.terracotta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("You'll review the list, untick anyone you don't want, and choose a folder before anything is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    private func optionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Theme.aegean)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .mementoCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review

    private var reviewList: some View {
        List {
            Section("Add To Folder") {
                Picker("Folder", selection: $selectedGroup) {
                    Text("None").tag(PersonGroup?.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group))
                    }
                }
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach($candidates) { $candidate in
                    Toggle(isOn: $candidate.include) {
                        HStack(spacing: 12) {
                            AvatarView(data: candidate.photoData, name: candidate.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .font(.body.weight(.medium))
                                let details = candidateDetails(candidate)
                                if !details.isEmpty {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if candidate.alreadyExists {
                                    Text("Already in Memento")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.terracotta)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(candidates.count) found · \(selectedCount) selected")
                    Spacer()
                    // Flip everyone at once. When anything is unticked the
                    // action selects all; once everything's on it becomes
                    // Deselect All.
                    Button(allSelected ? "Deselect All" : "Select All") {
                        setAllIncluded(!allSelected)
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Button("Choose a Different Source") {
                    candidates = []
                    errorMessage = nil
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
    }

    private func candidateDetails(_ candidate: ImportCandidate) -> String {
        var parts: [String] = []
        if !candidate.phone.isEmpty { parts.append(candidate.phone) }
        if let birthday = candidate.birthday {
            parts.append("🎂 " + birthday.formatted(.dateTime.day().month(.abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - iOS Contacts

    private func handlePicked(_ contacts: [CNContact]) {
        var results: [ImportCandidate] = []
        for contact in contacts {
            var candidate = ImportCandidate(name: displayName(for: contact))
            guard !candidate.name.trimmed.isEmpty else { continue }

            if contact.isKeyAvailable(CNContactPhoneNumbersKey),
               let phone = contact.phoneNumbers.first {
                candidate.phone = phone.value.stringValue
            }
            if contact.isKeyAvailable(CNContactEmailAddressesKey),
               let email = contact.emailAddresses.first {
                candidate.email = email.value as String
            }
            if contact.isKeyAvailable(CNContactPostalAddressesKey),
               let postal = contact.postalAddresses.first {
                candidate.address = CNPostalAddressFormatter
                    .string(from: postal.value, style: .mailingAddress)
                    .replacingOccurrences(of: "\n", with: ", ")
            }
            if contact.isKeyAvailable(CNContactBirthdayKey),
               let comps = contact.birthday,
               let month = comps.month, let day = comps.day {
                // Contacts can store a birthday without a year; 1904 keeps
                // the month/day working while the age display stays hidden
                // (QuickInfoView only shows age < 120). Unlike 1900, 1904 is
                // a leap year, so a Feb 29 birthday still constructs a valid
                // date instead of silently failing.
                candidate.birthday = Calendar.current.date(
                    from: DateComponents(year: comps.year ?? 1904, month: month, day: day)
                )
            }
            if contact.isKeyAvailable(CNContactImageDataKey), let data = contact.imageData {
                candidate.photoData = compressedPhoto(data)
            } else if contact.isKeyAvailable(CNContactThumbnailImageDataKey),
                      let data = contact.thumbnailImageData {
                candidate.photoData = data
            }
            results.append(candidate)
        }
        setCandidates(results)
    }

    private func displayName(for contact: CNContact) -> String {
        var name = ""
        if contact.isKeyAvailable(CNContactGivenNameKey) {
            name = contact.givenName
        }
        if contact.isKeyAvailable(CNContactFamilyNameKey) {
            name = (name + " " + contact.familyName).trimmed
        }
        if name.isEmpty, contact.isKeyAvailable(CNContactOrganizationNameKey) {
            name = contact.organizationName
        }
        return name.trimmed
    }

    private func compressedPhoto(_ data: Data) -> Data {
        UIImage(data: data)?.compressedData(maxDimension: 900) ?? data
    }

    // MARK: - Files (Facebook export / CSV)

    private func handleFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "json" {
                parseFacebookJSON(data)
            } else {
                parseCSV(String(decoding: data, as: UTF8.self))
            }
        } catch {
            errorMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func parseFacebookJSON(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "That JSON file wasn't recognized."
            return
        }
        let array = (object["friends_v2"] ?? object["friends"]) as? [[String: Any]] ?? []
        let names = array.compactMap { $0["name"] as? String }
        guard !names.isEmpty else {
            errorMessage = "No friends found in that file. In Facebook, use Settings → Download Your Information and include Friends (JSON format)."
            return
        }
        setCandidates(names.map { ImportCandidate(name: $0) })
    }

    private func parseCSV(_ text: String) {
        let rows = parseCSVRows(text)
        guard rows.count > 1 else {
            errorMessage = "That CSV needs a header row and at least one contact."
            return
        }
        let headers = rows[0].map { $0.lowercased() }
        func columnIndex(matching options: [String]) -> Int? {
            headers.firstIndex { header in options.contains { header.contains($0) } }
        }
        guard let nameIndex = columnIndex(matching: ["name"]) else {
            errorMessage = "Couldn't find a \"name\" column in that CSV."
            return
        }
        let birthdayIndex = columnIndex(matching: ["birthday", "birth", "dob"])
        let phoneIndex = columnIndex(matching: ["phone", "mobile", "number"])
        let emailIndex = columnIndex(matching: ["email", "e-mail"])
        let addressIndex = columnIndex(matching: ["address"])

        var results: [ImportCandidate] = []
        for fields in rows.dropFirst() {
            func value(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index]
            }
            let name = value(nameIndex)
            guard !name.isEmpty else { continue }
            var candidate = ImportCandidate(name: name)
            candidate.phone = value(phoneIndex)
            candidate.email = value(emailIndex)
            candidate.address = value(addressIndex)
            candidate.birthday = parseBirthday(value(birthdayIndex))
            results.append(candidate)
        }
        guard !results.isEmpty else {
            errorMessage = "No contacts found in that CSV."
            return
        }
        setCandidates(results)
    }

    /// Parses the whole file as one quote-aware stream (rather than
    /// splitting into lines first), so a quoted field containing an
    /// embedded newline — legal CSV, common in exported addresses — isn't
    /// torn in half. Also collapses a doubled `""` into a literal `"`
    /// instead of dropping both quote characters.
    private func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var fields: [String] = []
        var current = ""
        var insideQuotes = false

        func endField() {
            fields.append(current.trimmed)
            current = ""
        }
        func endRow() {
            endField()
            if !(fields.count == 1 && fields[0].isEmpty) {
                rows.append(fields)
            }
            fields = []
        }

        let characters = Array(text)
        var i = 0
        while i < characters.count {
            let character = characters[i]
            if insideQuotes {
                if character == "\"" {
                    if i + 1 < characters.count, characters[i + 1] == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                insideQuotes = true
            } else if character == "," {
                endField()
            } else if character == "\r" {
                // No-op; a following "\n" (if present) ends the row.
            } else if character == "\n" {
                endRow()
            } else {
                current.append(character)
            }
            i += 1
        }
        if !current.isEmpty || !fields.isEmpty {
            endRow()
        }
        return rows
    }

    private func parseBirthday(_ string: String) -> Date? {
        let trimmed = string.trimmed
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "d MMMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    // MARK: - Shared

    private func setCandidates(_ results: [ImportCandidate]) {
        let existingNames = Set(existingPeople.map { $0.name.lowercased() })
        var prepared = results
        for index in prepared.indices {
            let exists = existingNames.contains(prepared[index].name.trimmed.lowercased())
            prepared[index].alreadyExists = exists
            if exists { prepared[index].include = false }
        }
        errorMessage = nil
        candidates = prepared.sorted { $0.name < $1.name }
    }

    private func importSelected() {
        // Imports join whichever workspace is currently open.
        let isBusiness = UserDefaults.standard.string(forKey: Workspace.storageKey) == Workspace.business.rawValue
        for candidate in candidates where candidate.include {
            let person = Person(name: candidate.name.trimmed, group: selectedGroup)
            person.phoneNumber = candidate.phone.trimmed
            person.email = candidate.email.trimmed
            person.address = candidate.address.trimmed
            person.birthday = candidate.birthday
            person.profilePhotoData = candidate.photoData
            person.isBusiness = isBusiness
            context.insert(person)
        }
        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
        dismiss()
    }
}

// MARK: - System contact picker (no Contacts permission needed)

struct ContactPicker: UIViewControllerRepresentable {
    var onSelect: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: ([CNContact]) -> Void

        init(onSelect: @escaping ([CNContact]) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onSelect(contacts)
        }
    }
}
