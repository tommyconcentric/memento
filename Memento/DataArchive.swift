import Foundation
import SwiftData

// MARK: - Full data archive (.memento / JSON)

/// Memento's portable backup format: one self-describing JSON file holding
/// **everything** — every person in both workspaces, their profile fields,
/// notes, important dates, family links, projects, extra contacts, the
/// folders, the hidden "You" node and the family-tree edges — with profile
/// photos and note photos embedded as base64.
///
/// ## Compatibility contract (read before changing this file)
///
/// The whole point of this format is that a file written by *any* version of
/// Memento can be read by *any* other version. That holds as long as every
/// change is **additive and optional**:
///
/// - Every field on every archive struct is optional (or has a default), so a
///   file missing a field an app expects just falls back to the default —
///   an **older** file always loads into a **newer** app.
/// - `JSONDecoder` ignores keys it doesn't know, so a file carrying fields a
///   feature added later loads fine into an app that predates them — a
///   **newer** file always loads into an **older** app (it simply drops the
///   parts it has nowhere to store).
///
/// The rules, forever:
/// 1. **Only ever add optional fields.** Never remove a field, never rename
///    one, never change a field's meaning or type. A retired feature's field
///    stays in the struct (kept, ignored) so old files still parse.
/// 2. Bump `formatVersion` only for a genuinely breaking change, and add a
///    migration path keyed on it — never as routine version bumping. The
///    importer refuses a file whose `formatVersion` is above its own rather
///    than import it wrong.
/// 3. Dates are ISO-8601 **without fractional seconds** (both coders use the
///    strict `.iso8601` strategy, which rejects them) and photos are base64,
///    so the file is inspectable and stays valid across time zones and
///    platforms.
///
/// (One honest boundary: an app only preserves fields it understands, so
/// round-tripping a *newer* file *through* an older app drops the newer
/// fields. Importing directly between versions never loses shared data.)
nonisolated struct MementoArchive: Codable {
    /// Marker so a stray JSON file can be told apart from a real archive.
    var format: String? = archiveMarker
    /// Breaking-change gate; additive changes do not bump this.
    var formatVersion: Int? = currentFormatVersion
    var exportedAt: Date? = .now
    var appVersion: String?

    var groups: [ArchiveGroup]? = []
    var people: [ArchivePerson]? = []
    var parentages: [ArchiveParentage]? = []
    var partnerships: [ArchivePartnership]? = []

    static let archiveMarker = "memento-archive"
    static let currentFormatVersion = 1
}

nonisolated struct ArchiveGroup: Codable {
    var id: UUID
    var name: String?
    var sortOrder: Int?
    var isBuiltIn: Bool?
}

nonisolated struct ArchivePerson: Codable {
    /// Archive-local identity, used only to wire up folders, notes and
    /// family edges within this one file (SwiftData's own ids aren't
    /// portable). Never stored back onto the model.
    var id: UUID

    var name: String?
    var isSelf: Bool?
    var isGhost: Bool?
    var isBusiness: Bool?
    var isPinned: Bool?
    var didAutoPinAsPartner: Bool?   // added later; optional so any version reads any file
    var isDeceased: Bool?
    var groupID: UUID?
    var createdAt: Date?

    var birthday: Date?
    var birthdayReminderEnabled: Bool?
    var relationshipToUser: String?
    var partnerName: String?
    var childrenNames: String?
    var otherFamily: String?
    var jobTitle: String?
    var company: String?
    var hobbies: String?
    var hometown: String?
    var currentCity: String?     // added later; optional so any version reads any file
    var howWeMet: String?
    var foodPreferences: String?
    var phoneNumber: String?
    var email: String?
    var address: String?

    var profilePhoto: Data?

    var notes: [ArchiveNote]?
    var importantDates: [ArchiveImportantDate]?
    var familyMembers: [ArchiveFamilyMember]?
    var contactFields: [ArchiveContactField]?
    var projects: [ArchiveProject]?
}

nonisolated struct ArchiveNote: Codable {
    var title: String?
    var text: String?
    var eventDate: Date?
    var location: String?
    var createdAt: Date?
    var photos: [ArchivePhoto]?
}

nonisolated struct ArchivePhoto: Codable {
    var imageData: Data?
    var caption: String?
    var sortOrder: Int?
}

nonisolated struct ArchiveImportantDate: Codable {
    var label: String?
    var date: Date?
    var remindersEnabled: Bool?
}

nonisolated struct ArchiveFamilyMember: Codable {
    var name: String?
    var relation: String?
}

nonisolated struct ArchiveContactField: Codable {
    var kind: String?
    var value: String?
    var isPreferred: Bool?
    var sortOrder: Int?
}

nonisolated struct ArchiveProject: Codable {
    var name: String?
    var isCompleted: Bool?
    var sortOrder: Int?
}

nonisolated struct ArchiveParentage: Codable {
    var parentID: UUID?
    var childID: UUID?
    var kind: String?
}

nonisolated struct ArchivePartnership: Codable {
    var aID: UUID?
    var bID: UUID?
    var kind: String?
}

// MARK: - Summary of what an import did

struct ImportSummary {
    var peopleAdded = 0
    var peopleMerged = 0        // matched an existing person by name + workspace
    var notesAdded = 0
    var photosAdded = 0
    var datesAdded = 0
    var contactsAdded = 0
    var groupsAdded = 0

    var headline: String {
        var parts: [String] = []
        if peopleAdded > 0 { parts.append(counted(peopleAdded, "person", "people") + " added") }
        if peopleMerged > 0 { parts.append("\(peopleMerged) already present") }
        if notesAdded > 0 { parts.append(counted(notesAdded, "note", "notes")) }
        if photosAdded > 0 { parts.append(counted(photosAdded, "photo", "photos")) }
        if datesAdded > 0 { parts.append(counted(datesAdded, "date", "dates")) }
        if contactsAdded > 0 { parts.append(counted(contactsAdded, "contact detail", "contact details")) }
        guard !parts.isEmpty else { return "Nothing new to add — everything in that file is already here" }
        return parts.joined(separator: " · ")
    }

    private func counted(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}

enum DataArchiveError: LocalizedError {
    case notAnArchive
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "That file isn't a Memento backup."
        case .unreadable:
            return "That backup couldn't be read — it may be from a much newer version of Memento, or damaged."
        }
    }
}

// MARK: - Export

enum DataArchiveExport {
    nonisolated private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Builds the full archive from the store. Runs on the main context.
    static func makeArchive(_ context: ModelContext) -> MementoArchive {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let groups = (try? context.fetch(FetchDescriptor<PersonGroup>())) ?? []

        // Stable archive ids for anything an edge or membership points at.
        var personIDs: [PersistentIdentifier: UUID] = [:]
        for person in people { personIDs[person.persistentModelID] = UUID() }
        var groupIDs: [PersistentIdentifier: UUID] = [:]
        for group in groups { groupIDs[group.persistentModelID] = UUID() }

        var archive = MementoArchive()
        archive.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        archive.groups = groups.map { group in
            ArchiveGroup(id: groupIDs[group.persistentModelID] ?? UUID(),
                         name: group.name, sortOrder: group.sortOrder, isBuiltIn: group.isBuiltIn)
        }

        archive.people = people.map { person in
            ArchivePerson(
                id: personIDs[person.persistentModelID] ?? UUID(),
                name: person.name,
                isSelf: person.isSelf ? true : nil,
                isGhost: person.isGhost ? true : nil,
                isBusiness: person.isBusiness ? true : nil,
                isPinned: person.isPinned ? true : nil,
                didAutoPinAsPartner: person.didAutoPinAsPartner ? true : nil,
                isDeceased: person.isDeceased ? true : nil,
                groupID: person.group.flatMap { groupIDs[$0.persistentModelID] },
                createdAt: person.createdAt,
                birthday: person.birthday,
                birthdayReminderEnabled: person.birthdayReminderEnabled ? nil : false,
                relationshipToUser: person.relationshipToUser.nilIfEmpty,
                partnerName: person.partnerName.nilIfEmpty,
                childrenNames: person.childrenNames.nilIfEmpty,
                otherFamily: person.otherFamily.nilIfEmpty,
                jobTitle: person.jobTitle.nilIfEmpty,
                company: person.company.nilIfEmpty,
                hobbies: person.hobbies.nilIfEmpty,
                hometown: person.hometown.nilIfEmpty,
                currentCity: person.currentCity.nilIfEmpty,
                howWeMet: person.howWeMet.nilIfEmpty,
                foodPreferences: person.foodPreferences.nilIfEmpty,
                phoneNumber: person.phoneNumber.nilIfEmpty,
                email: person.email.nilIfEmpty,
                address: person.address.nilIfEmpty,
                profilePhoto: person.profilePhotoData,
                notes: person.notesArray.isEmpty ? nil : person.sortedNotes.map { note in
                    ArchiveNote(
                        title: note.title.nilIfEmpty,
                        text: note.text.nilIfEmpty,
                        eventDate: note.eventDate,
                        location: note.location.nilIfEmpty,
                        createdAt: note.createdAt,
                        photos: note.photosArray.isEmpty ? nil : note.sortedPhotos.map {
                            ArchivePhoto(imageData: $0.imageData, caption: $0.caption.nilIfEmpty, sortOrder: $0.sortOrder)
                        }
                    )
                },
                importantDates: person.importantDatesArray.isEmpty ? nil : person.importantDatesArray.map {
                    ArchiveImportantDate(label: $0.label, date: $0.date,
                                         remindersEnabled: $0.remindersEnabled ? nil : false)
                },
                familyMembers: person.familyMembersArray.isEmpty ? nil : person.familyMembersArray.map {
                    ArchiveFamilyMember(name: $0.name, relation: $0.relation)
                },
                contactFields: person.contactFieldsArray.isEmpty ? nil : person.contactFieldsArray.map {
                    ArchiveContactField(kind: $0.kind, value: $0.value,
                                        isPreferred: $0.isPreferred ? true : nil, sortOrder: $0.sortOrder)
                },
                projects: person.projectsArray.isEmpty ? nil : person.projectsArray.map {
                    ArchiveProject(name: $0.name, isCompleted: $0.isCompleted ? true : nil, sortOrder: $0.sortOrder)
                }
            )
        }

        var parentages: [ArchiveParentage] = []
        var partnerships: [ArchivePartnership] = []
        for person in people {
            for edge in person.edgesAsParentArray {
                guard let child = edge.child,
                      let parentUUID = personIDs[person.persistentModelID],
                      let childUUID = personIDs[child.persistentModelID] else { continue }
                parentages.append(ArchiveParentage(parentID: parentUUID, childID: childUUID, kind: edge.kind))
            }
            for edge in person.partnershipsAsAArray {
                guard let other = edge.b,
                      let aUUID = personIDs[person.persistentModelID],
                      let bUUID = personIDs[other.persistentModelID] else { continue }
                partnerships.append(ArchivePartnership(aID: aUUID, bID: bUUID, kind: edge.kind))
            }
        }
        archive.parentages = parentages
        archive.partnerships = partnerships
        return archive
    }

    /// Encodes an already-built archive (base64-ing every photo — the heavy
    /// part) and writes it to a temp file for the share sheet. Pure value
    /// work, so callers run it off the main thread; build the archive with
    /// `makeArchive` on the main context first.
    nonisolated static func writeArchive(_ archive: MementoArchive) -> URL? {
        guard let data = try? encoder.encode(archive) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Memento Backup \(filenameStamp()).memento")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    nonisolated static func filenameStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}

// MARK: - Import

enum DataArchiveImport {
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Reads an archive file's bytes and merges its contents into the store.
    /// Additive by design: people are matched to existing ones by name +
    /// workspace (so re-importing the same backup doesn't duplicate them),
    /// and only genuinely new people bring in their notes, photos and dates.
    /// Each existing person can be claimed by only one archive person per
    /// run, so two distinct same-named people in a backup restore as two.
    @discardableResult
    static func importArchive(_ data: Data, into context: ModelContext) throws -> ImportSummary {
        // A file that isn't our JSON shape (e.g. a CSV, or any other text)
        // is simply "not an archive" so the caller can try another format.
        guard let archive = try? decoder.decode(MementoArchive.self, from: data),
              archive.format == MementoArchive.archiveMarker else {
            throw DataArchiveError.notAnArchive
        }
        // The one job `formatVersion` has: refuse a file from a future
        // format that deliberately broke compatibility, instead of
        // importing it wrong.
        guard (archive.formatVersion ?? 1) <= MementoArchive.currentFormatVersion else {
            throw DataArchiveError.unreadable
        }

        var summary = ImportSummary()
        var groupByArchiveID: [UUID: PersonGroup] = [:]
        var existingGroups = (try? context.fetch(FetchDescriptor<PersonGroup>())) ?? []

        for ag in archive.groups ?? [] {
            let name = (ag.name ?? "").trimmed
            guard !name.isEmpty else { continue }
            if let match = existingGroups.first(where: { $0.name.trimmed.caseInsensitiveCompare(name) == .orderedSame }) {
                groupByArchiveID[ag.id] = match
            } else {
                let group = PersonGroup(name: name, sortOrder: ag.sortOrder ?? 0, isBuiltIn: ag.isBuiltIn ?? false)
                context.insert(group)
                existingGroups.append(group)
                groupByArchiveID[ag.id] = group
                summary.groupsAdded += 1
            }
        }

        var personByArchiveID: [UUID: Person] = [:]
        var existingPeople = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        // People already claimed by an archive person this run. A backup can
        // legitimately hold two distinct people with the same name, and each
        // must land on its own person: once a name-match is claimed, the
        // next same-named archive person creates a new one instead.
        var claimed = Set<ObjectIdentifier>()

        for ap in archive.people ?? [] {
            let name = (ap.name ?? "").trimmed
            let isBusiness = ap.isBusiness ?? false

            if ap.isSelf == true {
                // Fold the archived self into the device's own hidden node,
                // filling only blanks so a restore never clobbers current
                // "You" data; each collection (notes, dates, family rows,
                // contacts, projects) comes in only where this node has none
                // of its own — addChildren skips any that aren't empty.
                let selfNode = existingPeople.canonicalSelfNode ?? {
                    let node = Person(name: name.isEmpty ? "You" : name)
                    node.isSelf = true
                    context.insert(node)
                    existingPeople.append(node)
                    return node
                }()
                apply(ap, to: selfNode, group: groupByArchiveID[ap.groupID ?? UUID()], fillEmptyOnly: true)
                addChildren(of: ap, to: selfNode, context: context, summary: &summary)
                personByArchiveID[ap.id] = selfNode
                continue
            }

            // A blank name can only come from a hand-edited file; skip the
            // row rather than minting nameless people that would all merge
            // into each other.
            guard !name.isEmpty else { continue }

            if ap.isGhost == true {
                let ghost = existingPeople.first {
                    $0.isGhost && $0.name.trimmed.caseInsensitiveCompare(name) == .orderedSame
                } ?? {
                    let node = Person(name: name)
                    node.isGhost = true
                    context.insert(node)
                    existingPeople.append(node)
                    return node
                }()
                personByArchiveID[ap.id] = ghost
                continue
            }

            // A normal contact: reuse a same-name, same-workspace person if
            // one exists and hasn't been claimed by another archive person
            // yet (so repeated imports are idempotent *and* duplicate names
            // stay distinct), else create it and bring in everything
            // hanging off it.
            if let match = existingPeople.first(where: {
                !$0.isSelf && !$0.isGhost && $0.isBusiness == isBusiness
                    && !claimed.contains(ObjectIdentifier($0))
                    && $0.name.trimmed.caseInsensitiveCompare(name) == .orderedSame
            }) {
                claimed.insert(ObjectIdentifier(match))
                personByArchiveID[ap.id] = match
                summary.peopleMerged += 1
                continue
            }

            let person = Person(name: name)
            context.insert(person)
            apply(ap, to: person, group: groupByArchiveID[ap.groupID ?? UUID()], fillEmptyOnly: false)
            addChildren(of: ap, to: person, context: context, summary: &summary)
            existingPeople.append(person)
            claimed.insert(ObjectIdentifier(person))
            personByArchiveID[ap.id] = person
            summary.peopleAdded += 1
        }

        for edge in archive.parentages ?? [] {
            guard let parentID = edge.parentID, let childID = edge.childID,
                  let parent = personByArchiveID[parentID], let child = personByArchiveID[childID],
                  parent !== child,
                  !parent.edgesAsParentArray.contains(where: { $0.child === child }) else { continue }
            context.insert(Parentage(parent: parent, child: child,
                                     kind: ParentageKind(rawValue: edge.kind ?? "") ?? .bio))
        }
        for edge in archive.partnerships ?? [] {
            guard let aID = edge.aID, let bID = edge.bID,
                  let a = personByArchiveID[aID], let b = personByArchiveID[bID], a !== b else { continue }
            let linked = a.partnershipsAsAArray.contains { $0.b === b }
                || a.partnershipsAsBArray.contains { $0.a === b }
            guard !linked else { continue }
            context.insert(Partnership(a: a, b: b,
                                       kind: PartnershipKind(rawValue: edge.kind ?? "") ?? .partner))
        }

        do {
            try context.save()
        } catch {
            // Roll the half-applied import back rather than reporting
            // success on data that never persisted.
            context.rollback()
            throw error
        }
        FamilyGraphMaintenance.dedupe(context)
        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
        return summary
    }

    /// Copies scalar fields across. `fillEmptyOnly` protects existing data
    /// (used for the self node) by writing only where the target is blank.
    private static func apply(_ ap: ArchivePerson, to person: Person, group: PersonGroup?, fillEmptyOnly: Bool) {
        func setString(_ keyPath: ReferenceWritableKeyPath<Person, String>, _ value: String?) {
            guard let value = value?.trimmed, !value.isEmpty else { return }
            if fillEmptyOnly && !person[keyPath: keyPath].trimmed.isEmpty { return }
            person[keyPath: keyPath] = value
        }
        if !fillEmptyOnly || person.name.trimmed.isEmpty { person.name = (ap.name ?? person.name) }
        if !fillEmptyOnly {
            person.isBusiness = ap.isBusiness ?? person.isBusiness
            person.isPinned = ap.isPinned ?? person.isPinned
            // Restoring the latch keeps a deliberately unpinned partner
            // unpinned — without it, the next editor save would re-pin them.
            person.didAutoPinAsPartner = ap.didAutoPinAsPartner ?? person.didAutoPinAsPartner
            person.isDeceased = ap.isDeceased ?? person.isDeceased
            // nil here means "was true at export" — the exporter omits the
            // default; the self node keeps its own setting regardless.
            person.birthdayReminderEnabled = ap.birthdayReminderEnabled ?? true
            if let created = ap.createdAt { person.createdAt = created }
        }
        if let group, !fillEmptyOnly || person.group == nil { person.group = group }
        if person.birthday == nil || !fillEmptyOnly { person.birthday = ap.birthday ?? person.birthday }
        if let photo = ap.profilePhoto, person.profilePhotoData == nil || !fillEmptyOnly {
            person.profilePhotoData = photo
        }
        setString(\.relationshipToUser, ap.relationshipToUser)
        setString(\.partnerName, ap.partnerName)
        setString(\.childrenNames, ap.childrenNames)
        setString(\.otherFamily, ap.otherFamily)
        setString(\.jobTitle, ap.jobTitle)
        setString(\.company, ap.company)
        setString(\.hobbies, ap.hobbies)
        setString(\.hometown, ap.hometown)
        setString(\.currentCity, ap.currentCity)
        setString(\.howWeMet, ap.howWeMet)
        setString(\.foodPreferences, ap.foodPreferences)
        setString(\.phoneNumber, ap.phoneNumber)
        setString(\.email, ap.email)
        setString(\.address, ap.address)
    }

    /// Creates the notes, dates, family members, contacts and projects that
    /// belong to an imported person. Each collection fills only when the
    /// target has none of its own — for a freshly created person that's all
    /// of them, and for the self node it means a restore adds to "You"
    /// without ever replacing rows that already exist.
    private static func addChildren(of ap: ArchivePerson, to person: Person,
                                    context: ModelContext, summary: inout ImportSummary) {
        if person.notesArray.isEmpty {
            var notes: [NoteEntry] = []
            for an in ap.notes ?? [] {
                let note = NoteEntry(text: an.text ?? "", eventDate: an.eventDate ?? .now, location: an.location ?? "")
                note.title = an.title ?? ""
                note.createdAt = an.createdAt ?? an.eventDate ?? .now
                context.insert(note)
                note.person = person
                var photos: [EventPhoto] = []
                for aphoto in an.photos ?? [] {
                    let photo = EventPhoto(imageData: aphoto.imageData, caption: aphoto.caption ?? "",
                                           sortOrder: aphoto.sortOrder ?? 0)
                    context.insert(photo)
                    photos.append(photo)
                    summary.photosAdded += 1
                }
                note.photosArray = photos
                notes.append(note)
                summary.notesAdded += 1
            }
            person.notesArray = notes
        }

        if person.importantDatesArray.isEmpty {
            var dates: [ImportantDate] = []
            for ad in ap.importantDates ?? [] {
                let date = ImportantDate(label: ad.label ?? "", date: ad.date ?? .now)
                date.remindersEnabled = ad.remindersEnabled ?? true
                context.insert(date)
                dates.append(date)
                summary.datesAdded += 1
            }
            person.importantDatesArray = dates
        }

        if person.familyMembersArray.isEmpty {
            person.familyMembersArray = (ap.familyMembers ?? []).map {
                let member = FamilyMember(name: $0.name ?? "", relation: $0.relation ?? "")
                context.insert(member)
                return member
            }
        }
        if person.contactFieldsArray.isEmpty {
            var fields: [ContactField] = []
            for af in ap.contactFields ?? [] {
                let field = ContactField(kind: ContactField.Kind(rawValue: af.kind ?? "") ?? .phone,
                                         value: af.value ?? "", sortOrder: af.sortOrder ?? 0)
                field.isPreferred = af.isPreferred ?? false
                context.insert(field)
                fields.append(field)
                summary.contactsAdded += 1
            }
            person.contactFieldsArray = fields
        }
        if person.projectsArray.isEmpty {
            person.projectsArray = (ap.projects ?? []).map {
                let project = Project(name: $0.name ?? "", isCompleted: $0.isCompleted ?? false,
                                      sortOrder: $0.sortOrder ?? 0)
                context.insert(project)
                return project
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : self }
}
