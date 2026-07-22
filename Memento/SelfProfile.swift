import SwiftUI
import SwiftData

// MARK: - Profile card (share format)

/// The shareable profile: a structured plain-text card. Plain text on
/// purpose — AirDrop needs a type the receiving OS already knows, so a
/// friend *without* Memento can still read the card or keep it in Apple
/// Notes, while a friend *with* Memento gets "Open in Memento" (the app
/// registers as a plain-text viewer) and can add the person in a tap.
enum ProfileCard {
    static let marker = "MEMENTO PROFILE"

    /// Fixed-locale birthday formats: the card must parse on the receiving
    /// device whatever language either phone speaks.
    private static func birthdayFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    // MARK: Writing

    static func text(for person: Person) -> String {
        var lines: [String] = [marker, ""]
        func add(_ key: String, _ value: String) {
            // The card is line-oriented; an interior newline (the address
            // field is multi-line in the editor) would truncate the value
            // on parse — or let a continuation line that happens to read
            // "Company: …" masquerade as another key on the receiver.
            let flattened = value
                .replacingOccurrences(of: "\r\n", with: ", ")
                .replacingOccurrences(of: "\n", with: ", ")
                .replacingOccurrences(of: "\r", with: ", ")
                .trimmed
            guard !flattened.isEmpty else { return }
            lines.append("\(key): \(flattened)")
        }
        add("Name", person.name)
        if let birthday = person.birthday {
            // A placeholder-year birthday has no real year to share.
            let format = birthday.hasPlaceholderYear ? "d MMMM" : "d MMMM yyyy"
            add("Birthday", birthdayFormatter(format).string(from: birthday))
        }
        add("Phone", person.phoneNumber)
        add("Email", person.email)
        add("Address", person.address)
        add("Job title", person.jobTitle)
        add("Company", person.company)
        add("Hobbies", person.hobbies)
        add("Hometown", person.hometown)
        add("Food & drink", person.foodPreferences)
        add("Partner", person.partnerName)
        add("Children", person.childrenNames)
        lines.append("")
        lines.append("Shared from Memento — a personal notebook for the people in your life.")
        return lines.joined(separator: "\n")
    }

    /// Writes the card into a shareable temp file named after the person.
    static func writeTemporaryFile(for person: Person) -> URL? {
        let safeName = person.name.trimmed.replacingOccurrences(of: "/", with: "-")
        let filename = "\(safeName.isEmpty ? "My" : safeName) — Memento Profile.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text(for: person).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Reading

    static func load(from url: URL) -> ParsedProfile? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        // The app opens arbitrary plain text ("Open in Memento"); a real
        // card is a few hundred bytes, so refuse to slurp a huge file into
        // memory on the main thread just to discover it isn't one.
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 64_000 {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> ParsedProfile? {
        let lines = text.components(separatedBy: .newlines).map(\.trimmed)
        guard lines.first(where: { !$0.isEmpty }) == marker else { return nil }

        var profile = ParsedProfile()
        for line in lines {
            guard let colon = line.range(of: ": ") else { continue }
            let key = String(line[..<colon.lowerBound]).lowercased()
            let value = String(line[colon.upperBound...]).trimmed
            guard !value.isEmpty else { continue }
            switch key {
            case "name": profile.name = value
            case "birthday": profile.birthday = parseBirthday(value)
            case "phone": profile.phone = value
            case "email": profile.email = value
            case "address": profile.address = value
            case "job title": profile.jobTitle = value
            case "company": profile.company = value
            case "hobbies": profile.hobbies = value
            case "hometown": profile.hometown = value
            case "food & drink": profile.foodPreferences = value
            case "partner": profile.partnerName = value
            case "children": profile.childrenNames = value
            default: break
            }
        }
        return profile.name.isEmpty ? nil : profile
    }

    private static func parseBirthday(_ value: String) -> Date? {
        if let full = birthdayFormatter("d MMMM yyyy").date(from: value) {
            return full
        }
        // A year-less card line ("14 March") lands on the placeholder year,
        // the same convention as contact import — via the Gregorian
        // calendar explicitly, where 1904 means 1904 (and is a leap year)
        // regardless of the device's calendar setting.
        if let partial = birthdayFormatter("d MMMM").date(from: value) {
            var comps = Date.gregorian.dateComponents([.month, .day], from: partial)
            comps.year = Date.placeholderYear
            return Date.gregorian.date(from: comps)
        }
        return nil
    }
}

/// One parsed profile card, ready to preview and add.
struct ParsedProfile: Identifiable {
    let id = UUID()
    var name = ""
    var birthday: Date?
    var phone = ""
    var email = ""
    var address = ""
    var jobTitle = ""
    var company = ""
    var hobbies = ""
    var hometown = ""
    var foodPreferences = ""
    var partnerName = ""
    var childrenNames = ""
}

// MARK: - My Profile (the sheet behind the sidebar's avatar circle)

/// The self profile's home: edit it with the same editor every other
/// profile uses, or share it as a profile card.
struct MyProfileSheet: View {
    let person: Person

    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var shareURL: URL?

    /// The self node starts life as a hidden "You" — treat that as unset.
    private var hasRealName: Bool {
        let name = person.name.trimmed
        return !name.isEmpty && name.caseInsensitiveCompare("You") != .orderedSame
    }

    private var displayName: String {
        hasRealName ? person.name : "You"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Button {
                        showingEditor = true
                    } label: {
                        AvatarView(data: person.profilePhotoData, name: displayName, size: 110)
                            .overlay(Circle().stroke(Theme.gold.opacity(0.7), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit your profile photo and details")

                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        if hasRealName {
                            let work = [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !work.isEmpty {
                                Text(work)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Add your name and details — they travel with your shared profile.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit My Profile", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if let shareURL {
                            ShareLink(
                                item: shareURL,
                                preview: SharePreview("\(displayName) — Memento Profile")
                            ) {
                                Label("Share My Profile", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasRealName)
                        }

                        Text("Shares a small profile card by AirDrop, Messages or Mail. Friends with Memento can add you in a tap; anyone else can read it or keep it in Apple Notes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditor, onDismiss: regenerateShareFile) {
                PersonEditorView(person: person)
            }
            .onAppear(perform: regenerateShareFile)
        }
    }

    /// The card mirrors the saved profile; rebuild it whenever the sheet
    /// appears or the editor closes so a stale file is never shared.
    private func regenerateShareFile() {
        shareURL = ProfileCard.writeTemporaryFile(for: person)
    }
}

// MARK: - Receiving a shared profile card

/// Preview-and-confirm for a profile card opened from AirDrop/Files —
/// nothing lands in the store until "Add to Memento".
struct ProfileImportSheet: View {
    let profile: ParsedProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var people: [Person]

    private var alreadyExists: Bool {
        people.contains {
            !$0.isSelf && !$0.isGhost &&
            $0.name.compare(profile.name, options: .caseInsensitive) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AvatarView(data: nil, name: profile.name, size: 84)
                    Text(profile.name)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Shared Memento profile")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        if let birthday = profile.birthday {
                            InfoRow(icon: "gift", label: "Birthday", value: birthday.hasPlaceholderYear
                                ? birthday.formatted(.dateTime.month(.wide).day())
                                : birthday.formatted(date: .long, time: .omitted))
                        }
                        row("phone", "Phone", profile.phone)
                        row("envelope", "Email", profile.email)
                        row("mappin", "Address", profile.address)
                        row("briefcase", "Work", [profile.jobTitle, profile.company].filter { !$0.isEmpty }.joined(separator: " · "))
                        row("star", "Hobbies", profile.hobbies)
                        row("house", "Hometown", profile.hometown)
                        row("fork.knife", "Food & Drink", profile.foodPreferences)
                        row("heart", "Partner", profile.partnerName)
                        row("figure.2.and.child.holdinghands", "Children", profile.childrenNames)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mementoCard()

                    if alreadyExists {
                        Text("You already have someone called \(profile.name) in Memento — adding will create a second profile.")
                            .font(.footnote)
                            .foregroundStyle(Theme.terracotta)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: add) {
                        Label("Add to Memento", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            InfoRow(icon: icon, label: label, value: value)
        }
    }

    private func add() {
        let person = Person(name: profile.name)
        // Join whichever workspace is open, same as the contacts importer —
        // a card accepted while in Business would otherwise land invisibly
        // in Personal.
        person.isBusiness = UserDefaults.standard.string(forKey: Workspace.storageKey) == Workspace.business.rawValue
        person.birthday = profile.birthday
        person.phoneNumber = profile.phone
        person.email = profile.email
        person.address = profile.address
        person.jobTitle = profile.jobTitle
        person.company = profile.company
        person.hobbies = profile.hobbies
        person.hometown = profile.hometown
        person.foodPreferences = profile.foodPreferences
        person.partnerName = profile.partnerName
        person.childrenNames = profile.childrenNames
        context.insert(person)
        FamilyEdgeSync.apply(around: person, context: context)
        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
        dismiss()
    }
}
