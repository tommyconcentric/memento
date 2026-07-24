import Foundation
import SwiftData

// MARK: - Memento CSV (a spreadsheet-friendly, re-importable subset)

/// A single standalone CSV that round-trips through Memento. Unlike the full
/// `.memento` archive it can't carry photos or the family-tree graph, but it
/// covers the everyday data — every listed person in both workspaces, their
/// quick-info fields, their notes and their important dates — in a file that
/// opens cleanly in any spreadsheet.
///
/// One CSV holds several kinds of row, told apart by a leading **Type**
/// column (`Person`, `Note`, `Date`, `Contact`). `Note`/`Date`/`Contact`
/// rows reference their owner by the `PersonID` written on the matching
/// `Person` row, so the whole file re-imports as connected data. Unknown
/// `Type` values and unknown columns are ignored, so — like the JSON archive
/// — a CSV written by a newer Memento still imports into an older one.
enum MementoCSV {
    static let columns = [
        "Type", "ID", "PersonID", "Workspace", "Folder", "Name",
        "Birthday", "Deceased", "Pinned", "Relationship",
        "Job Title", "Company", "Hobbies", "Hometown", "How We Met",
        "Food & Drink", "Phone", "Email", "Address",
        "Date", "Label", "Title", "Text", "Location"
    ]

    // MARK: Export

    static func writeCSVFile(_ context: ModelContext) -> URL? {
        let text = makeCSV(context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Memento Export \(DataArchiveExport.filenameStamp()).csv")
        do {
            // A UTF-8 BOM makes Excel open accented names correctly.
            try ("\u{FEFF}" + text).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func makeCSV(_ context: ModelContext) -> String {
        let people = ((try? context.fetch(FetchDescriptor<Person>())) ?? [])
            .filter { !$0.isSelf && !$0.isGhost }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var rows: [[String: String]] = []
        for (index, person) in people.enumerated() {
            let personID = "P\(index + 1)"
            rows.append([
                "Type": "Person",
                "ID": personID,
                "Workspace": person.isBusiness ? "Business" : "Personal",
                "Folder": person.group?.name ?? "",
                "Name": person.name,
                "Birthday": person.birthday.map(birthdayString) ?? "",
                "Deceased": person.isDeceased ? "Yes" : "",
                "Pinned": person.isPinned ? "Yes" : "",
                "Relationship": person.relationshipToUser,
                "Job Title": person.jobTitle,
                "Company": person.company,
                "Hobbies": person.hobbies,
                "Hometown": person.hometown,
                "How We Met": person.howWeMet,
                "Food & Drink": person.foodPreferences,
                "Phone": person.phoneNumber,
                "Email": person.email,
                "Address": person.address
            ])
            for note in person.sortedNotes {
                rows.append([
                    "Type": "Note",
                    "PersonID": personID,
                    "Date": isoDay(note.eventDate),
                    "Title": note.title,
                    "Text": note.text,
                    "Location": note.location
                ])
            }
            for date in person.importantDatesArray {
                rows.append([
                    "Type": "Date",
                    "PersonID": personID,
                    "Date": birthdayString(date.date),
                    "Label": date.label
                ])
            }
            for field in person.contactFieldsArray where !field.value.trimmed.isEmpty {
                rows.append([
                    "Type": "Contact",
                    "PersonID": personID,
                    "Label": field.kind,
                    "Text": field.value
                ])
            }
        }

        var lines = [columns.map(escape).joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { escape(row[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    // MARK: Import

    @discardableResult
    static func importCSV(_ text: String, into context: ModelContext) throws -> ImportSummary {
        let table = parseRows(text)
        guard let header = table.first else { throw DataArchiveError.unreadable }
        // Tolerant of a spreadsheet with repeated column names — first wins,
        // and a duplicate header must never trap.
        let index = Dictionary(header.enumerated().map { ($1.trimmed.lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })
        func value(_ fields: [String], _ column: String) -> String {
            guard let i = index[column.lowercased()], i < fields.count else { return "" }
            return fields[i].trimmed
        }
        guard index["type"] != nil, index["name"] != nil else {
            // Not a Memento CSV — a plain contacts CSV goes through the
            // Import from Contacts screen instead.
            throw DataArchiveError.notAnArchive
        }

        var summary = ImportSummary()
        var groups = (try? context.fetch(FetchDescriptor<PersonGroup>())) ?? []
        var existingPeople = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        var personByCSVID: [String: Person] = [:]

        func folder(named name: String) -> PersonGroup? {
            let trimmed = name.trimmed
            guard !trimmed.isEmpty else { return nil }
            if let match = groups.first(where: { $0.name.trimmed.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return match
            }
            let group = PersonGroup(name: trimmed, sortOrder: (groups.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(group)
            groups.append(group)
            summary.groupsAdded += 1
            return group
        }

        // Two passes: create people first so notes/dates can find their owner
        // regardless of row order.
        for fields in table.dropFirst() where value(fields, "Type").caseInsensitiveCompare("Person") == .orderedSame {
            let name = value(fields, "Name")
            guard !name.isEmpty else { continue }
            let isBusiness = value(fields, "Workspace").caseInsensitiveCompare("Business") == .orderedSame
            let csvID = value(fields, "ID")

            if let match = existingPeople.first(where: {
                !$0.isSelf && !$0.isGhost && $0.isBusiness == isBusiness
                    && $0.name.trimmed.caseInsensitiveCompare(name) == .orderedSame
            }) {
                if !csvID.isEmpty { personByCSVID[csvID] = match }
                summary.peopleMerged += 1
                continue
            }

            let person = Person(name: name)
            person.isBusiness = isBusiness
            person.isDeceased = isYes(value(fields, "Deceased"))
            person.isPinned = isYes(value(fields, "Pinned"))
            person.group = folder(named: value(fields, "Folder"))
            person.birthday = parseBirthday(value(fields, "Birthday"))
            person.relationshipToUser = value(fields, "Relationship")
            person.jobTitle = value(fields, "Job Title")
            person.company = value(fields, "Company")
            person.hobbies = value(fields, "Hobbies")
            person.hometown = value(fields, "Hometown")
            person.howWeMet = value(fields, "How We Met")
            person.foodPreferences = value(fields, "Food & Drink")
            person.phoneNumber = value(fields, "Phone")
            person.email = value(fields, "Email")
            person.address = value(fields, "Address")
            context.insert(person)
            existingPeople.append(person)
            if !csvID.isEmpty { personByCSVID[csvID] = person }
            summary.peopleAdded += 1
        }

        for fields in table.dropFirst() {
            let type = value(fields, "Type")
            guard let owner = personByCSVID[value(fields, "PersonID")] else { continue }
            if type.caseInsensitiveCompare("Note") == .orderedSame {
                let note = NoteEntry(text: value(fields, "Text"),
                                     eventDate: parseBirthday(value(fields, "Date")) ?? .now,
                                     location: value(fields, "Location"))
                note.title = value(fields, "Title")
                note.createdAt = note.eventDate
                context.insert(note)
                note.person = owner
                summary.notesAdded += 1
            } else if type.caseInsensitiveCompare("Date") == .orderedSame {
                let label = value(fields, "Label")
                let date = parseBirthday(value(fields, "Date"))
                guard !label.isEmpty, let date else { continue }
                let entry = ImportantDate(label: label, date: date)
                context.insert(entry)
                entry.person = owner
                summary.datesAdded += 1
            } else if type.caseInsensitiveCompare("Contact") == .orderedSame {
                let fieldValue = value(fields, "Text")
                guard !fieldValue.isEmpty else { continue }
                let kind = ContactField.Kind(rawValue: value(fields, "Label").lowercased()) ?? .phone
                let field = ContactField(kind: kind, value: fieldValue, sortOrder: owner.contactFieldsArray.count)
                context.insert(field)
                field.person = owner
            }
        }

        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
        return summary
    }

    // MARK: Date formatting (shared by export & import)

    /// A real-year date as `yyyy-MM-dd`; a year-less birthday (placeholder
    /// year) as `--MM-dd`, matching the contact-import convention so those
    /// files interoperate.
    private static func birthdayString(_ date: Date) -> String {
        date.hasPlaceholderYear ? "--" + monthDay(date) : isoDay(date)
    }

    private static func isoDay(_ date: Date) -> String {
        let comps = Date.gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func monthDay(_ date: Date) -> String {
        let comps = Date.gregorian.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", comps.month ?? 0, comps.day ?? 0)
    }

    private static func parseBirthday(_ string: String) -> Date? {
        let value = string.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("--") {
            let parts = value.dropFirst(2).split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return Date.gregorian.date(from: DateComponents(year: Date.placeholderYear, month: parts[0], day: parts[1]))
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Date.gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func isYes(_ string: String) -> Bool {
        ["yes", "true", "1", "y"].contains(string.trimmed.lowercased())
    }

    // MARK: CSV text

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Quote-aware parse of the whole file into rows of fields — tolerant of
    /// embedded newlines in quoted values and doubled `""` escapes.
    private static func parseRows(_ text: String) -> [[String]] {
        // Normalize line endings to a lone "\n" first. Swift treats "\r\n"
        // (a CRLF, as Excel and this exporter write) as a *single*
        // Character, so a char-by-char scan would never see it as a line
        // break — the whole file would parse as one giant row.
        var stripped = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        stripped = stripped.replacingOccurrences(of: "\r\n", with: "\n")
                           .replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        let characters = Array(stripped)
        var i = 0
        func endField() { fields.append(current); current = "" }
        func endRow() {
            endField()
            if !(fields.count == 1 && fields[0].trimmed.isEmpty) { rows.append(fields) }
            fields = []
        }
        while i < characters.count {
            let c = characters[i]
            if insideQuotes {
                if c == "\"" {
                    if i + 1 < characters.count, characters[i + 1] == "\"" { current.append("\""); i += 1 }
                    else { insideQuotes = false }
                } else {
                    current.append(c)
                }
            } else if c == "\"" {
                insideQuotes = true
            } else if c == "," {
                endField()
            } else if c == "\n" {
                endRow()
            } else {
                current.append(c)
            }
            i += 1
        }
        if !current.isEmpty || !fields.isEmpty { endRow() }
        return rows
    }
}
