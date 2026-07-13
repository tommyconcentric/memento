import Foundation
import SwiftData

// MARK: - Folder (a group of people: Close Friends, Work Colleagues, custom…)

@Model
final class PersonGroup {
    var name: String
    var sortOrder: Int
    var isBuiltIn: Bool

    @Relationship(deleteRule: .nullify, inverse: \Person.group)
    var people: [Person] = []

    init(name: String, sortOrder: Int = 0, isBuiltIn: Bool = false) {
        self.name = name
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Person

@Model
final class Person {
    var name: String
    @Attribute(.externalStorage) var profilePhotoData: Data?
    var group: PersonGroup?
    var createdAt: Date
    var isDeceased: Bool = false
    var relationshipToUser: String = ""   // e.g. "Mother" — places them on your family tree
    var address: String = ""

    // Quick-reference details — kept separate from the running notes
    var birthday: Date?
    var partnerName: String
    var childrenNames: String
    var otherFamily: String
    var jobTitle: String
    var company: String
    var hobbies: String
    var hometown: String
    var howWeMet: String
    var foodPreferences: String
    var phoneNumber: String
    var email: String

    @Relationship(deleteRule: .cascade, inverse: \NoteEntry.person)
    var notes: [NoteEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ImportantDate.person)
    var importantDates: [ImportantDate] = []

    @Relationship(deleteRule: .cascade, inverse: \FamilyMember.person)
    var familyMembers: [FamilyMember] = []

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

extension Person {
    /// A one-line summary shown under the name in the people list.
    var subtitle: String {
        let work = [jobTitle, company].filter { !$0.isEmpty }.joined(separator: " · ")
        if !work.isEmpty { return work }
        if !hobbies.isEmpty { return hobbies }
        if !howWeMet.isEmpty { return howWeMet }
        return ""
    }

    var sortedNotes: [NoteEntry] {
        notes.sorted { $0.eventDate > $1.eventDate }
    }

    var hasAnyQuickInfo: Bool {
        if birthday != nil || !importantDates.isEmpty { return true }
        let fields = [partnerName, childrenNames, otherFamily, jobTitle, company,
                      hobbies, hometown, howWeMet, foodPreferences, phoneNumber, email,
                      address, relationshipToUser]
        return !fields.allSatisfy { $0.isEmpty }
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
    var label: String
    var date: Date
    var person: Person?

    init(label: String, date: Date) {
        self.label = label
        self.date = date
    }
}

// MARK: - Note entry (one item in a person's running timeline)

@Model
final class NoteEntry {
    var text: String
    var eventDate: Date
    var location: String
    var createdAt: Date
    var person: Person?

    @Relationship(deleteRule: .cascade, inverse: \EventPhoto.note)
    var photos: [EventPhoto] = []

    init(text: String = "", eventDate: Date = .now, location: String = "") {
        self.text = text
        self.eventDate = eventDate
        self.location = location
        self.createdAt = .now
    }
}

extension NoteEntry {
    var sortedPhotos: [EventPhoto] {
        photos.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Event photo attached to a note

@Model
final class EventPhoto {
    @Attribute(.externalStorage) var imageData: Data
    var caption: String
    var sortOrder: Int
    var note: NoteEntry?

    init(imageData: Data, caption: String = "", sortOrder: Int = 0) {
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
    }
}

// MARK: - Family member (structured entry that builds a person's family tree)

@Model
final class FamilyMember {
    var name: String
    var relation: String   // relation to the person this belongs to, e.g. "Mother"
    var person: Person?

    init(name: String, relation: String) {
        self.name = name
        self.relation = relation
    }
}
