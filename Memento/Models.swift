import Foundation
import SwiftData

// MARK: - Folder (a group of people: Close Friends, Work Colleagues, custom…)

@Model
final class PersonGroup {
    var name: String = ""
    var sortOrder: Int = 0
    var isBuiltIn: Bool = false

    // CloudKit requires to-many relationships to be Optional; `peopleArray`
    // is the non-optional accessor everything else in the app should use.
    @Relationship(deleteRule: .nullify, inverse: \Person.group)
    var people: [Person]?

    init(name: String, sortOrder: Int = 0, isBuiltIn: Bool = false) {
        self.name = name
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }
}

extension PersonGroup {
    /// The starter set, in the order a new user meets them.
    static let starterFolderNames = ["Family", "Close Friends", "Work Colleagues", "Friends"]

    /// Where a folder sits before anyone drags it: the closest relationships
    /// first, everything else alphabetically after. `sortOrder` stays the
    /// source of truth for display — this only decides what that order starts
    /// out as, so reordering by hand always wins.
    private static let rankedFolderNames = ["Family", "Close Friends", "Friends"]

    static func defaultRank(of name: String) -> Int {
        let match = rankedFolderNames.firstIndex {
            $0.compare(name.trimmed, options: .caseInsensitive) == .orderedSame
        }
        return match ?? rankedFolderNames.count
    }

    /// Orders folders the way a user who has never reordered them expects.
    static func inDefaultOrder(_ groups: [PersonGroup]) -> [PersonGroup] {
        groups.sorted {
            let (left, right) = (defaultRank(of: $0.name), defaultRank(of: $1.name))
            if left != right { return left < right }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var peopleArray: [Person] {
        get { people ?? [] }
        set { people = newValue }
    }
}

// MARK: - Person

@Model
final class Person {
    var name: String = ""
    @Attribute(.externalStorage) var profilePhotoData: Data?
    var group: PersonGroup?
    var createdAt: Date = Date.now
    var isDeceased: Bool = false
    var isPinned: Bool = false            // held at the top of the people list until unpinned
    var isBusiness: Bool = false          // lives in the Business workspace instead of Personal
    var relationshipToUser: String = ""   // e.g. "Mother" — places them on your family tree
    var address: String = ""
    // Family-tree graph nodes that never appear in the people list (see the
    // "listed people" filter): `isSelf` is the single hidden "You" node the
    // pedigree roots on; `isGhost` is a relative known only by name, kept so
    // it can carry parentage/partner edges. Both default false.
    var isSelf: Bool = false
    var isGhost: Bool = false

    // Quick-reference details — kept separate from the running notes
    var birthday: Date?
    var birthdayReminderEnabled: Bool = true
    var partnerName: String = ""
    // Set once, when someone first becomes your partner, so they ride at the
    // top of the list without ever re-pinning someone you deliberately unpinned.
    var didAutoPinAsPartner: Bool = false
    var childrenNames: String = ""
    var otherFamily: String = ""
    var jobTitle: String = ""
    var company: String = ""
    var hobbies: String = ""
    var hometown: String = ""
    var currentCity: String = ""          // where they're based now, e.g. "Lisbon, Portugal"
    var howWeMet: String = ""
    var foodPreferences: String = ""
    var phoneNumber: String = ""
    var email: String = ""

    // CloudKit requires to-many relationships to be Optional; use the
    // `notesArray`/`importantDatesArray`/`familyMembersArray` accessors below.
    @Relationship(deleteRule: .cascade, inverse: \NoteEntry.person)
    var notes: [NoteEntry]?

    @Relationship(deleteRule: .cascade, inverse: \ImportantDate.person)
    var importantDates: [ImportantDate]?

    @Relationship(deleteRule: .cascade, inverse: \FamilyMember.person)
    var familyMembers: [FamilyMember]?

    // Extra phone numbers/emails/addresses beyond the primary ones above.
    @Relationship(deleteRule: .cascade, inverse: \ContactField.person)
    var contactFields: [ContactField]?

    // Shared work with a business contact; use `projectsArray`.
    @Relationship(deleteRule: .cascade, inverse: \Project.person)
    var projects: [Project]?

    // Family-tree edges. A person appears as the parent in some `Parentage`
    // rows and the child in others; likewise either side of a `Partnership`.
    // All Optional for CloudKit; use the array accessors below. Deleting a
    // person cascades their edges so none dangle.
    @Relationship(deleteRule: .cascade, inverse: \Parentage.parent)
    var edgesAsParent: [Parentage]?

    @Relationship(deleteRule: .cascade, inverse: \Parentage.child)
    var edgesAsChild: [Parentage]?

    @Relationship(deleteRule: .cascade, inverse: \Partnership.a)
    var partnershipsAsA: [Partnership]?

    @Relationship(deleteRule: .cascade, inverse: \Partnership.b)
    var partnershipsAsB: [Partnership]?

    init(name: String, group: PersonGroup? = nil) {
        self.name = name
        self.group = group
        self.createdAt = .now
        self.partnerName = ""
        self.childrenNames = ""
        self.otherFamily = ""
        self.jobTitle = ""
        self.company = ""
        self.hobbies = ""
        self.hometown = ""
        self.howWeMet = ""
        self.foodPreferences = ""
        self.phoneNumber = ""
        self.email = ""
    }
}

extension Array where Element == Person {
    /// The single self node every feature should agree on. Two devices can
    /// each seed a "You" before CloudKit merges; picking the earliest
    /// created (deterministically, everywhere) keeps My Profile, the
    /// pedigree root and new edges on the same node while the duplicate
    /// merge folds the others away.
    var canonicalSelfNode: Person? {
        filter(\.isSelf).min { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
    }
}

extension Person {
    /// Labels that mean "this is my partner". `relationshipToUser` is written
    /// by the self-node linking (which normalises girlfriend/boyfriend to
    /// "Partner"), but the user can also type their own, so equivalents count.
    private static let partnerLabels: Set<String> = [
        "partner", "spouse", "husband", "wife", "girlfriend", "boyfriend",
        "fiancé", "fiancée", "fiance", "fiancee"
    ]

    /// True when this person is *your* partner. Ex-partners deliberately
    /// don't count — "Ex-partner" is exactly what the linking writes when a
    /// partnership is marked former.
    var isYourPartner: Bool {
        let label = relationshipToUser.trimmed.lowercased()
        guard !label.hasPrefix("ex"), !label.hasPrefix("former") else { return false }
        return Self.partnerLabels.contains(label)
    }

    /// A one-line summary shown under the name in the people list.
    var subtitle: String {
        let work = [jobTitle, company].filter { !$0.isEmpty }.joined(separator: " · ")
        if !work.isEmpty { return work }
        if !hobbies.isEmpty { return hobbies }
        if !howWeMet.isEmpty { return howWeMet }
        return ""
    }

    var notesArray: [NoteEntry] {
        get { notes ?? [] }
        set { notes = newValue }
    }

    var importantDatesArray: [ImportantDate] {
        get { importantDates ?? [] }
        set { importantDates = newValue }
    }

    var familyMembersArray: [FamilyMember] {
        get { familyMembers ?? [] }
        set { familyMembers = newValue }
    }

    var contactFieldsArray: [ContactField] {
        get { contactFields ?? [] }
        set { contactFields = newValue }
    }

    var projectsArray: [Project] {
        get { projects ?? [] }
        set { projects = newValue }
    }

    // Family-tree edge accessors (non-optional, like the others above).
    var edgesAsParentArray: [Parentage] {
        get { edgesAsParent ?? [] }
        set { edgesAsParent = newValue }
    }
    var edgesAsChildArray: [Parentage] {
        get { edgesAsChild ?? [] }
        set { edgesAsChild = newValue }
    }
    var partnershipsAsAArray: [Partnership] {
        get { partnershipsAsA ?? [] }
        set { partnershipsAsA = newValue }
    }
    var partnershipsAsBArray: [Partnership] {
        get { partnershipsAsB ?? [] }
        set { partnershipsAsB = newValue }
    }

    /// Parentage edges where this person is the child — i.e. their parents.
    var parentEdges: [Parentage] { edgesAsChildArray }
    /// Parentage edges where this person is the parent — i.e. their children.
    var childEdges: [Parentage] { edgesAsParentArray }
    var parents: [Person] { parentEdges.compactMap(\.parent) }
    var children: [Person] { childEdges.compactMap(\.child) }
    /// Each partnership paired with the person on the other side of it.
    var partnerEdges: [(edge: Partnership, other: Person)] {
        partnershipsAsAArray.compactMap { edge in edge.b.map { (edge, $0) } }
            + partnershipsAsBArray.compactMap { edge in edge.a.map { (edge, $0) } }
    }

    /// Ongoing work first, completed history below, each in entry order.
    var sortedProjects: [Project] {
        projectsArray.sorted {
            ($0.isCompleted ? 1 : 0, $0.sortOrder) < ($1.isCompleted ? 1 : 0, $1.sortOrder)
        }
    }

    /// Additional contact methods of one kind, in entry order.
    func additionalContacts(_ kind: ContactField.Kind) -> [ContactField] {
        contactFieldsArray
            .filter { $0.kind == kind.rawValue && !$0.value.trimmed.isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The starred extra of one kind, if the user chose one — preferred over
    /// the primary field and shown first on Quick Info.
    func preferredContact(_ kind: ContactField.Kind) -> ContactField? {
        additionalContacts(kind).first(where: \.isPreferred)
    }

    /// Newest first. Backdated notes all land on midnight of their day, so
    /// same-day ties are common — break them by `createdAt`, then by the
    /// persistent ID, to keep timeline and PDF order stable across
    /// launches, devices and CloudKit refetches (Swift's sort isn't stable
    /// and the relationship's underlying order isn't guaranteed).
    var sortedNotes: [NoteEntry] {
        notesArray.sorted {
            if $0.eventDate != $1.eventDate { return $0.eventDate > $1.eventDate }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
    }

    var hasAnyQuickInfo: Bool {
        if birthday != nil || !importantDatesArray.isEmpty || !contactFieldsArray.isEmpty { return true }
        let fields = [partnerName, childrenNames, otherFamily, jobTitle, company,
                      hobbies, hometown, currentCity, howWeMet, foodPreferences, phoneNumber, email,
                      address, relationshipToUser]
        return !fields.allSatisfy { $0.isEmpty }
    }

    /// Where they live for grouping and filtering: the city they're based in
    /// now, falling back to their hometown.
    var cityLabel: String {
        let based = currentCity.trimmed
        return based.isEmpty ? hometown.trimmed : based
    }

    /// Age usable for ordering — nil when there's no birthday or only a
    /// year-less one (the placeholder year would fake a 120-year-old).
    var sortableAge: Int? {
        guard let birthday, !birthday.hasPlaceholderYear else { return nil }
        return age
    }

    /// Completed years since the stored birthday.
    var age: Int? {
        guard let birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: .now).year
    }

    /// Days until the next occurrence of the birthday (0 = today).
    var daysUntilNextBirthday: Int? {
        guard let birthday else { return nil }
        return Date.daysUntilNextOccurrence(of: birthday)
    }
}

// MARK: - Important date (anniversary, kid's birthday, big event…)

@Model
final class ImportantDate {
    var label: String = ""
    var date: Date = Date.now
    var remindersEnabled: Bool = true
    var person: Person?

    init(label: String, date: Date) {
        self.label = label
        self.date = date
    }
}

// MARK: - Note entry (one item in a person's running timeline)

@Model
final class NoteEntry {
    var title: String = ""
    var text: String = ""
    var eventDate: Date = Date.now
    var location: String = ""
    var createdAt: Date = Date.now
    var person: Person?

    // CloudKit requires to-many relationships to be Optional; use `photosArray`.
    @Relationship(deleteRule: .cascade, inverse: \EventPhoto.note)
    var photos: [EventPhoto]?

    init(text: String = "", eventDate: Date = .now, location: String = "") {
        self.text = text
        self.eventDate = eventDate
        self.location = location
        self.createdAt = .now
    }
}

extension NoteEntry {
    var photosArray: [EventPhoto] {
        get { photos ?? [] }
        set { photos = newValue }
    }

    var sortedPhotos: [EventPhoto] {
        photosArray.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Event photo attached to a note

@Model
final class EventPhoto {
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String = ""
    var sortOrder: Int = 0
    var note: NoteEntry?

    init(imageData: Data?, caption: String = "", sortOrder: Int = 0) {
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
    }
}

// MARK: - Contact field (extra phone/email/address beyond the primary one)

@Model
final class ContactField {
    var kind: String = ContactField.Kind.phone.rawValue
    var value: String = ""
    var sortOrder: Int = 0
    // Starred in the editor: preferred over the primary field of its kind,
    // shown first on Quick Info. At most one per kind is expected; the
    // editor and save path enforce it.
    var isPreferred: Bool = false
    var person: Person?

    enum Kind: String, CaseIterable {
        case phone, email, address

        var label: String {
            switch self {
            case .phone: return "Phone"
            case .email: return "Email"
            case .address: return "Address"
            }
        }
        var icon: String {
            switch self {
            case .phone: return "phone"
            case .email: return "envelope"
            case .address: return "mappin"
            }
        }
    }

    init(kind: Kind, value: String = "", sortOrder: Int = 0) {
        self.kind = kind.rawValue
        self.value = value
        self.sortOrder = sortOrder
    }
}

// MARK: - Project (work you share with a business contact)

@Model
final class Project {
    var name: String = ""
    var isCompleted: Bool = false
    var sortOrder: Int = 0
    var person: Person?

    init(name: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.name = name
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}

// MARK: - Family member (structured entry that builds a person's family tree)

@Model
final class FamilyMember {
    var name: String = ""
    var relation: String = ""   // relation to the person this belongs to, e.g. "Mother"
    var person: Person?

    init(name: String, relation: String) {
        self.name = name
        self.relation = relation
    }
}

// MARK: - Family-tree edges (parentage & partnership)

/// One directed parent→child link between two people (either may be a hidden
/// self/ghost node). `kind` styles the line and decides half- vs full-sibling
/// math: two people are full siblings when they share both parents, half when
/// they share one.
@Model
final class Parentage {
    var parent: Person?
    var child: Person?
    var kind: String = ParentageKind.bio.rawValue

    init(parent: Person?, child: Person?, kind: ParentageKind = .bio) {
        self.parent = parent
        self.child = child
        self.kind = kind.rawValue
    }
}

enum ParentageKind: String, CaseIterable {
    case bio, adopted, foster, step
    /// Step and foster ties draw dashed; blood and adoption draw solid.
    var isDashed: Bool { self == .step || self == .foster }
}

/// An undirected couple link between two people. `kind` distinguishes a
/// current union from a former one (a former partner draws a dashed bar).
@Model
final class Partnership {
    var a: Person?
    var b: Person?
    var kind: String = PartnershipKind.married.rawValue

    init(a: Person?, b: Person?, kind: PartnershipKind = .married) {
        self.a = a
        self.b = b
        self.kind = kind.rawValue
    }
}

enum PartnershipKind: String, CaseIterable {
    case married, partner, engaged, former
    var isDashed: Bool { self == .former }
}
