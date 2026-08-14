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
    @State private var isFetchingContacts = false
    // Both import paths confirm first — a mis-tap on "Import All" could
    // otherwise pour hundreds of contacts into the store with no way back
    // but deleting them one by one.
    @State private var pendingImport: PendingImport?

    enum PendingImport: Identifiable {
        case selection(count: Int)   // the toolbar's "Import N" — ticked rows only
        case everyone(count: Int)    // "Import All" — every new row plus hand-ticked duplicates
        var id: String {
            switch self {
            case .selection(let count): return "selection-\(count)"
            case .everyone(let count): return "everyone-\(count)"
            }
        }
        var count: Int {
            switch self {
            case .selection(let count), .everyone(let count): return count
            }
        }
    }

    /// The system contact picker (CNContactPickerViewController) presents
    /// nothing when the iOS app runs on a Mac ("Designed for iPad"), so the
    /// Mac reads the Contacts database directly instead — which, unlike the
    /// picker, requires the Contacts permission. The review list is the
    /// picker there: everything is fetched, nothing imports unticked.
    private var usesDirectContactsFetch: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    struct ImportCandidate: Identifiable {
        let id = UUID()
        var name: String
        // Every value comes along; the first of each kind becomes the
        // primary field on the Person, the rest become extra ContactFields.
        var phones: [String] = []
        var emails: [String] = []
        var addresses: [String] = []
        var birthday: Date?
        var photoData: Data?
        var include = true
        var alreadyExists = false
    }

    private var selectedCount: Int {
        candidates.filter(\.include).count
    }

    /// Imports join whichever workspace is open — preview avatars in the
    /// matching palette.
    private var importsAsBusiness: Bool {
        UserDefaults.standard.string(forKey: Workspace.storageKey) == Workspace.business.rawValue
    }

    private var newCandidateCount: Int {
        candidates.filter { !$0.alreadyExists }.count
    }

    /// What "Import All" would actually bring in: every new candidate,
    /// plus any duplicate the user ticked by hand.
    private var bulkImportCount: Int {
        candidates.filter { !$0.alreadyExists || $0.include }.count
    }

    // "All" means everyone not already in Memento — those default to
    // unticked precisely to avoid duplicate imports, and Select All
    // shouldn't quietly undo that. They can still be ticked by hand.
    private var allSelected: Bool {
        let newCandidates = candidates.filter { !$0.alreadyExists }
        // With nothing new to select, deselecting is the only useful
        // action, so offer it whenever anything is ticked.
        guard !newCandidates.isEmpty else { return candidates.contains(where: \.include) }
        return newCandidates.allSatisfy(\.include)
    }

    private func setAllIncluded(_ included: Bool) {
        for index in candidates.indices where !included || !candidates[index].alreadyExists {
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
                        Button("Import \(selectedCount)") {
                            pendingImport = .selection(count: selectedCount)
                        }
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
            .alert(
                pendingImport.map { "Import \($0.count) \($0.count == 1 ? "Contact" : "Contacts")?" } ?? "",
                isPresented: Binding(
                    get: { pendingImport != nil },
                    set: { if !$0 { pendingImport = nil } }
                ),
                presenting: pendingImport
            ) { pending in
                Button("Import") {
                    if case .everyone = pending { setAllIncluded(true) }
                    importSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(selectedGroup.map { "They'll be added to the “\($0.name)” folder." }
                    ?? "They won't be filed in a folder — you can organize them later.")
            }
        }
    }

    // MARK: - Source options

    private var sourceOptions: some View {
        ScrollView {
            VStack(spacing: 14) {
                optionCard(
                    icon: "person.crop.circle.badge.plus",
                    title: isFetchingContacts ? "Loading Contacts…" : "From Contacts",
                    subtitle: usesDirectContactsFetch
                        ? "Reads the contacts on this Mac — names, photos, birthdays and every number, email and address come along. You'll tick exactly who to keep on the next screen."
                        : "Pick exactly who to import — names, photos, birthdays and every number, email and address come along. WhatsApp uses your phone's contacts, so this covers your WhatsApp people too."
                ) {
                    if usesDirectContactsFetch {
                        fetchAllContacts()
                    } else {
                        showingContactPicker = true
                    }
                }
                .disabled(isFetchingContacts)

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

            // One-tap bulk import — the alternative to ticking each person.
            // "All" means everyone not already in Memento; duplicate rows
            // stay out unless ticked by hand (and a hand-ticked one still
            // comes along).
            Section {
                Button {
                    pendingImport = .everyone(count: bulkImportCount)
                } label: {
                    Label(
                        newCandidateCount == candidates.count
                            ? "Import All \(newCandidateCount)"
                            : "Import All \(newCandidateCount) New",
                        systemImage: "square.and.arrow.down.on.square"
                    )
                }
                .disabled(newCandidateCount == 0)
            } header: {
                TipHeader(
                    title: "",
                    tip: newCandidateCount == candidates.count
                        ? "Brings everyone in at once — or tick people individually and use Import at the top."
                        : "Brings in everyone not already in Memento — \"Already in Memento\" rows stay out unless you tick them."
                )
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach($candidates) { $candidate in
                    Toggle(isOn: $candidate.include) {
                        HStack(spacing: 12) {
                            AvatarView(data: candidate.photoData, name: candidate.name, size: 40, business: importsAsBusiness)
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
        if let phone = candidate.phones.first.map({ PhoneNumberFormatter.display($0) }) {
            parts.append(candidate.phones.count > 1 ? "\(phone) +\(candidate.phones.count - 1)" : phone)
        }
        if let birthday = candidate.birthday {
            parts.append("🎂 " + birthday.appFormattedMonthDay())
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Contacts (direct fetch — Mac, where the picker can't present)

    /// Requests Contacts access and reads every contact into the review
    /// list. Only used on the Mac: on iOS/iPadOS the system picker imports
    /// without any Contacts permission, which is the more private path.
    private func fetchAllContacts() {
        guard !isFetchingContacts else { return }
        isFetchingContacts = true
        errorMessage = nil
        Task { @MainActor in
            defer { isFetchingContacts = false }
            let store = CNContactStore()
            let granted = (try? await store.requestAccess(for: .contacts)) ?? false
            guard granted else {
                errorMessage = "Turn on Contacts access for Memento in System Settings → Privacy & Security → Contacts, then try again."
                return
            }
            // Enumerate off the main thread — a big Contacts database with
            // photos takes long enough to hitch the sheet.
            let contacts: [CNContact] = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let keys = [
                        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                        CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey,
                        CNContactBirthdayKey, CNContactImageDataKey, CNContactThumbnailImageDataKey
                    ] as [CNKeyDescriptor]
                    let request = CNContactFetchRequest(keysToFetch: keys)
                    request.sortOrder = .userDefault
                    var results: [CNContact] = []
                    try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                        results.append(contact)
                    }
                    continuation.resume(returning: results)
                }
            }
            guard !contacts.isEmpty else {
                errorMessage = "No contacts were found on this Mac."
                return
            }
            // Everything arrives (there was no picker step), so nothing is
            // pre-ticked — the review list is where the choosing happens.
            handlePicked(contacts, preselectNew: false)
        }
    }

    // MARK: - Contacts (system picker — iPhone/iPad, no permission needed)

    private func handlePicked(_ contacts: [CNContact], preselectNew: Bool = true) {
        var results: [ImportCandidate] = []
        for contact in contacts {
            var candidate = ImportCandidate(name: displayName(for: contact))
            guard !candidate.name.trimmed.isEmpty else { continue }

            if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
                candidate.phones = uniqueValues(contact.phoneNumbers.map { $0.value.stringValue })
            }
            if contact.isKeyAvailable(CNContactEmailAddressesKey) {
                candidate.emails = uniqueValues(contact.emailAddresses.map { $0.value as String })
            }
            if contact.isKeyAvailable(CNContactPostalAddressesKey) {
                candidate.addresses = uniqueValues(contact.postalAddresses.map { postal in
                    CNPostalAddressFormatter
                        .string(from: postal.value, style: .mailingAddress)
                        .replacingOccurrences(of: "\n", with: ", ")
                })
            }
            if contact.isKeyAvailable(CNContactBirthdayKey),
               let comps = contact.birthday,
               let month = comps.month, let day = comps.day {
                // Contacts can store a birthday without a year; the
                // placeholder year keeps the month/day working while
                // displays hide it (see Date.placeholderYear). It's a leap
                // year, so a Feb 29 birthday still constructs a valid date
                // instead of silently failing.
                // Built with the Gregorian calendar explicitly — CNContact
                // components are Gregorian, and the placeholder year only
                // means 1904 there.
                candidate.birthday = Date.gregorian.date(
                    from: DateComponents(year: comps.year ?? Date.placeholderYear, month: month, day: day)
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
        setCandidates(results, preselectNew: preselectNew)
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

    /// Contacts often repeat one value under several labels (e.g. the same
    /// number as "mobile" and "iPhone") — drop exact repeats, keep order.
    private func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.map { $0.trimmed }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Files (Facebook export / CSV)

    /// A generous ceiling for a contacts export — thousands of contacts are
    /// still only a few MB. Beyond this we refuse rather than slurp an
    /// arbitrarily large "Open in Memento" file whole into memory on the
    /// main thread (parseCSVRows then copies it into a `[Character]`), which
    /// a malicious or mistaken file could turn into an out-of-memory crash.
    private static let maxImportBytes = 10 * 1024 * 1024

    private func handleFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > Self.maxImportBytes {
                errorMessage = "That file is too large to import (over 10 MB). Export just your contacts and try again."
                return
            }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "json" {
                parseFacebookJSON(data)
            } else if let text = decodeImportText(data) {
                parseCSV(text)
            } else {
                errorMessage = "That file's text encoding wasn't recognized. Re-export it as UTF-8 and try again."
            }
        } catch {
            errorMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    /// CSVs don't declare their encoding, and Excel/Outlook on Windows
    /// commonly save "ANSI" (Windows-1252) — decoding that with the
    /// never-failing repairing UTF-8 decoder turned every accented
    /// character into U+FFFD, corrupting names for good and defeating
    /// duplicate matching. Strict UTF-8 first, then a UTF-16 byte-order
    /// mark, then the common Windows single-byte encodings.
    private func decodeImportText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            // Excel's "CSV UTF-8" variant writes a byte-order mark; keep
            // it out of the first header cell.
            return utf8.hasPrefix("\u{FEFF}") ? String(utf8.dropFirst()) : utf8
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            // .utf16 honors (and strips) the byte-order mark.
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
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
            // An exact header wins outright. Among substring matches,
            // Google-style exports pair "Phone 1 - Type" with
            // "Phone 1 - Value" — binding the first "phone" hit meant
            // every import stored junk like "Mobile" as the number.
            if let exact = headers.firstIndex(where: { options.contains($0) }) { return exact }
            let candidates = headers.indices.filter { index in
                options.contains { headers[index].contains($0) }
            }
            return candidates.first { headers[$0].contains("value") }
                ?? candidates.first { !headers[$0].contains("type") }
                ?? candidates.first
        }
        // A combined "Name" column wins outright (Google's export leads
        // with one). Outlook-style exports instead split the name across
        // "First Name" / "Middle Name" / "Last Name" — the substring
        // fallback would bind "First Name" alone and import every contact
        // as a bare given name, so find the parts and join them per row.
        let hasCombinedNameColumn = headers.contains("name")
        let namePartIndices: [Int] = hasCombinedNameColumn ? [] : [
            ["first name", "given name"],
            ["middle name", "additional name"],
            ["last name", "family name", "surname"]
        ].compactMap { options in
            headers.firstIndex { header in options.contains { header.contains($0) } }
        }
        let nameIndex = columnIndex(matching: ["name"])
        guard nameIndex != nil || namePartIndices.count > 1 else {
            errorMessage = "Couldn't find a \"name\" column in that CSV."
            return
        }
        let birthdayIndex = columnIndex(matching: ["birthday", "birth", "dob"])
        let phoneIndex = columnIndex(matching: ["phone", "mobile", "number"])
        let emailIndex = columnIndex(matching: ["email", "e-mail"])
        let addressIndex = columnIndex(matching: ["address"])

        // Slash birthdays ("03/07/1990") are ambiguous row by row but a
        // single export uses one convention throughout, so settle
        // day/month order once from the whole file before parsing.
        let slashOrder = slashDateOrder(inferringFrom: rows.dropFirst().map { fields in
            guard let birthdayIndex, birthdayIndex < fields.count else { return "" }
            return fields[birthdayIndex]
        })

        var results: [ImportCandidate] = []
        for fields in rows.dropFirst() {
            func value(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index]
            }
            let name = namePartIndices.count > 1
                ? namePartIndices.map { value($0) }.filter { !$0.isEmpty }.joined(separator: " ")
                : value(nameIndex)
            guard !name.isEmpty else { continue }
            var candidate = ImportCandidate(name: name)
            candidate.phones = uniqueValues([value(phoneIndex)])
            candidate.emails = uniqueValues([value(emailIndex)])
            candidate.addresses = uniqueValues([value(addressIndex)])
            candidate.birthday = parseBirthday(value(birthdayIndex), slashOrder: slashOrder)
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
                } else if character == "\r" {
                    // Normalize CRLF/CR inside a quoted field to "\n" so
                    // stored values don't carry stray carriage returns.
                    if !(i + 1 < characters.count && characters[i + 1] == "\n") {
                        current.append("\n")
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                insideQuotes = true
            } else if character == "," {
                endField()
            } else if character == "\r" {
                // Bare-CR files (classic exports) end rows on "\r"; in CRLF
                // files the following "\n" then ends an empty row, which
                // endRow() already skips.
                endRow()
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

    /// Which side of a numeric slash date holds the day — the one genuinely
    /// ambiguous birthday shape a CSV can contain.
    private enum SlashDateOrder {
        case dayFirst    // "03/07/1990" is 3 July (UK/EU exports)
        case monthFirst  // "03/07/1990" is March 7 (US/Outlook exports)
    }

    /// A CSV is one export, so it uses one date convention throughout —
    /// which means a single row valid in only one reading (a day over 12,
    /// e.g. "25/12/1990") pins the order for every row in the file. A file
    /// whose rows are all ambiguous (every value ≤ 12) follows the device
    /// region's day/month order rather than a hardcoded guess.
    private func slashDateOrder(inferringFrom strings: [String]) -> SlashDateOrder {
        var dayFirstEvidence = false
        var monthFirstEvidence = false
        for string in strings {
            guard let (first, second) = slashDateComponents(string) else { continue }
            let readsAsDayFirst = (1...31).contains(first) && (1...12).contains(second)
            let readsAsMonthFirst = (1...12).contains(first) && (1...31).contains(second)
            // Only a value valid in exactly one reading is evidence —
            // junk numbers pin nothing.
            if readsAsDayFirst && !readsAsMonthFirst { dayFirstEvidence = true }
            if readsAsMonthFirst && !readsAsDayFirst { monthFirstEvidence = true }
        }
        switch (dayFirstEvidence, monthFirstEvidence) {
        case (true, false): return .dayFirst
        case (false, true): return .monthFirst
        // No evidence either way — or contradictory rows, which is no
        // single convention at all. The locale breaks the tie; either
        // way each unambiguous row still lands correctly via the
        // runner-up format in parseBirthday.
        default: return localeSlashOrder
        }
    }

    /// The device region's day/month order (en_US puts the month first;
    /// most of the world, the day).
    private var localeSlashOrder: SlashDateOrder {
        let template = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: .current) ?? "d/M"
        if let month = template.firstIndex(of: "M"),
           let day = template.firstIndex(of: "d"),
           month < day {
            return .monthFirst
        }
        return .dayFirst
    }

    /// The two leading numbers of a three-part slash date, e.g.
    /// "03/07/1990" → (3, 7). Anything else — ISO dates, month names,
    /// junk — returns nil.
    private func slashDateComponents(_ string: String) -> (first: Int, second: Int)? {
        let parts = string.trimmed.split(separator: "/")
        guard parts.count == 3,
              let first = Int(parts[0]),
              let second = Int(parts[1]) else { return nil }
        return (first, second)
    }

    private func parseBirthday(_ string: String, slashOrder: SlashDateOrder) -> Date? {
        let trimmed = string.trimmed
        guard !trimmed.isEmpty else { return nil }
        // Google's CSV export writes a year-less birthday as "--MM-DD"
        // (e.g. "--04-15"); keep it via the placeholder year, exactly as
        // the Contacts path does for year-less CNContact birthdays.
        if trimmed.hasPrefix("--") {
            let parts = trimmed.dropFirst(2).split(separator: "-")
            guard parts.count == 2,
                  let month = Int(parts[0]), (1...12).contains(month),
                  let day = Int(parts[1]), (1...31).contains(day) else { return nil }
            return Date.gregorian.date(
                from: DateComponents(year: Date.placeholderYear, month: month, day: day)
            )
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // ISO first — it's unambiguous — then both slash readings in the
        // file's inferred order. The runner-up still runs: a row only it
        // fits has a day over 12 in the pinned format's month slot, so
        // the runner-up reading is the correct one for that row.
        let slashFormats = slashOrder == .dayFirst
            ? ["dd/MM/yyyy", "MM/dd/yyyy"]
            : ["MM/dd/yyyy", "dd/MM/yyyy"]
        for format in ["yyyy-MM-dd"] + slashFormats + ["d MMMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return pivotingTwoDigitYear(date) }
        }
        return nil
    }

    /// `yyyy` parses a two-digit year as the literal number, so "5/6/90"
    /// landed in the year 90 AD. A two-digit year in a birthday means the
    /// recent past: pivot it into the century that keeps it at or before
    /// today (90 → 1990, 08 → 2008 — never a future year).
    private func pivotingTwoDigitYear(_ date: Date) -> Date {
        var comps = Date.gregorian.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, year < 100 else { return date }
        let currentYear = Date.gregorian.component(.year, from: .now)
        let pivoted = 2000 + year
        comps.year = pivoted > currentYear ? pivoted - 100 : pivoted
        return Date.gregorian.date(from: comps) ?? date
    }

    // MARK: - Shared

    /// `preselectNew: false` starts every candidate unticked — used when the
    /// whole address book arrives at once (the Mac's direct fetch) rather
    /// than a hand-picked selection.
    private func setCandidates(_ results: [ImportCandidate], preselectNew: Bool = true) {
        // Only visible contacts count as duplicates — a hidden tree ghost
        // sharing a contact's name would otherwise flag "Already in
        // Memento" for someone the user has never seen in any list.
        let existingNames = Set(existingPeople.filter { !$0.isSelf && !$0.isGhost }.map { $0.name.lowercased() })
        var prepared = results
        for index in prepared.indices {
            let exists = existingNames.contains(prepared[index].name.trimmed.lowercased())
            prepared[index].alreadyExists = exists
            if exists || !preselectNew { prepared[index].include = false }
        }
        errorMessage = nil
        candidates = prepared.sorted { $0.name < $1.name }
    }

    private func importSelected() {
        // Imports join whichever workspace is currently open.
        let isBusiness = UserDefaults.standard.string(forKey: Workspace.storageKey) == Workspace.business.rawValue
        var imported: [Person] = []
        for candidate in candidates where candidate.include {
            let person = Person(name: candidate.name.trimmed, group: selectedGroup)
            person.phoneNumber = candidate.phones.first ?? ""
            person.email = candidate.emails.first ?? ""
            person.address = candidate.addresses.first ?? ""
            person.birthday = candidate.birthday
            person.profilePhotoData = candidate.photoData
            person.isBusiness = isBusiness
            context.insert(person)

            // Everything beyond the first of each kind lands as extra
            // contact fields, same as adding them by hand in the editor.
            var sortOrder = 0
            for (kind, extras) in [
                (ContactField.Kind.phone, candidate.phones.dropFirst()),
                (.email, candidate.emails.dropFirst()),
                (.address, candidate.addresses.dropFirst())
            ] {
                for extra in extras {
                    person.contactFieldsArray.append(ContactField(kind: kind, value: extra, sortOrder: sortOrder))
                    sortOrder += 1
                }
            }
            imported.append(person)
        }
        // Same pass every editor save runs: folds a namesake ghost onto the
        // arriving profile so the pedigree doesn't chart the person twice —
        // without this, a ghost "Sam" stays separate until Sam's profile
        // happens to be re-saved by hand.
        for person in imported {
            FamilyEdgeSync.apply(around: person, context: context)
        }
        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
        UsageAnalytics.recordContactsCreated(imported.count)
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
