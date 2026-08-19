#if DEBUG
import SwiftUI
import SwiftData
import UIKit
import os

/// Dev-only stress tooling: launch with `--stress-seed 250` to fill the
/// store with that many synthetic people: varied birthdays (Feb 29 and
/// year-less included), important dates, extra contacts with stars, family
/// links, notes with photos, both workspaces, pinned and deceased people.
/// Idempotent (bails if the marker person exists) and compiled out of
/// Release builds entirely. Timings land in the unified log under the
/// "stress" category.
enum StressSeeder {
    // Must exactly match the first generated name below.
    private static let marker = "Stress 001 Aegean Papadopoulos"
    private static let log = Logger(subsystem: "brickcedar.Memento", category: "stress")

    static func seedIfRequested(_ context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "--stress-seed"), flag + 1 < args.count,
              let count = Int(args[flag + 1]), count > 0 else { return }

        var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.name == marker })
        descriptor.fetchLimit = 1
        if let hits = try? context.fetchCount(descriptor), hits > 0 {
            log.notice("STRESS seed skipped, marker person already present")
            timeRefreshes(context)
            return
        }

        let firsts = ["Aegean", "Bougainvillea", "Cypress", "Delphi", "Ellada", "Fira", "Gaia",
                      "Halki", "Ithaca", "Kalamata", "Lefkas", "Mykonos", "Naxos", "Oia",
                      "Paros", "Rhodes", "Santorini", "Thera", "Volos", "Zante"]
        let lasts = ["Papadopoulos", "Georgiou", "Nikolaou", "Dimitriou", "Ioannou",
                     "Christodoulou", "Petrou", "Andreou", "Stavrou", "Eleni"]
        let hobbies = ["sailing, jazz", "pottery", "hiking, sourdough", "chess", "", "swimming"]
        let dateLabels = ["Wedding anniversary", "Graduation", "First met", "Name day"]
        let groups = (try? context.fetch(FetchDescriptor<PersonGroup>(
            sortBy: [SortDescriptor(\.sortOrder)]))) ?? []

        let seedStart = Date.now
        for index in 0..<count {
            let name = "Stress \(String(format: "%03d", index + 1)) " +
                "\(firsts[index % firsts.count]) \(lasts[(index / firsts.count) % lasts.count])"
            let person = Person(name: name, group: groups.isEmpty ? nil : groups[index % (groups.count + 1) == groups.count ? 0 : index % groups.count])
            if index % (groups.count + 1) == groups.count { person.group = nil }

            person.isBusiness = index % 3 == 0
            person.isPinned = index % 25 == 0
            person.isDeceased = index % 20 == 19

            // Birthdays: most people have one; every 50th is Feb 29, every
            // 10th uses the year-less 1904 placeholder. Leap-day people skip
            // the no-birthday gate (index 67 would otherwise lose its Feb 29)
            // and get a fixed leap year. 1950 + 17 is 1967, where
            // Calendar.date(from:) silently rolls Feb 29 over to Mar 1.
            let isLeapDay = index % 50 == 17
            if index % 4 != 3 || isLeapDay {
                let year = index % 10 == 5 ? Date.placeholderYear : (isLeapDay ? 1968 : 1950 + (index % 50))
                let month = isLeapDay ? 2 : (index % 12) + 1
                let day = isLeapDay ? 29 : (index % 28) + 1
                person.birthday = Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            }

            person.jobTitle = index % 2 == 0 ? "Engineer" : ""
            person.company = index % 2 == 0 ? "Brick & Cedar" : ""
            person.hobbies = hobbies[index % hobbies.count]
            person.phoneNumber = "+44 7700 900\(String(format: "%03d", index))"
            person.email = "stress\(index)@example.com"
            if index % 5 == 0 {
                person.relationshipToUser = FamilyRelation.presets[index % FamilyRelation.presets.count]
            }
            if index % 2 == 0 {
                person.profilePhotoData = avatarJPEG(seed: index)
            }
            context.insert(person)

            for dateIndex in 0..<(index % 3) {
                let date = ImportantDate(
                    label: dateLabels[(index + dateIndex) % dateLabels.count],
                    date: Calendar.current.date(from: DateComponents(
                        year: 2000 + dateIndex, month: (index % 12) + 1, day: (index % 27) + 1)) ?? .now)
                person.importantDatesArray.append(date)
            }

            for extraIndex in 0..<(index % 3) {
                let field = ContactField(kind: extraIndex == 1 ? .email : .phone,
                                         value: "extra-\(index)-\(extraIndex)", sortOrder: extraIndex)
                field.isPreferred = extraIndex == 0 && index % 4 == 0
                person.contactFieldsArray.append(field)
            }

            if index % 6 == 0 {
                person.familyMembersArray.append(FamilyMember(name: "Stress \(String(format: "%03d", (index + 1) % count + 1))", relation: "Sibling"))
            }

            for noteIndex in 0..<(index % 4) {
                let note = NoteEntry(text: "Stress note \(noteIndex) for \(name). Talked about the harbour, the boat, and dinner plans.",
                                     eventDate: Date.now.addingTimeInterval(-Double(index + noteIndex) * 86_400),
                                     location: noteIndex == 0 ? "Taverna" : "")
                note.title = noteIndex == 1 ? "Catch-up" : ""
                person.notesArray.append(note)
                if index < 30, noteIndex == 0 {
                    note.photosArray.append(EventPhoto(imageData: avatarJPEG(seed: index + 999), caption: "Stress photo"))
                }
            }
        }
        try? context.save()
        log.notice("STRESS seeded \(count) people in \(Self.ms(since: seedStart)) ms")
        timeRefreshes(context)
    }

    private static func timeRefreshes(_ context: ModelContext) {
        var start = Date.now
        NotificationManager.refreshFromContext(context)
        log.notice("STRESS notification refresh took \(Self.ms(since: start)) ms")
        start = .now
        CalendarSyncManager.syncNow(context)
        log.notice("STRESS calendar syncNow took \(Self.ms(since: start)) ms (no-op unless sync enabled + permission granted)")
    }

    private static func ms(since start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1000)
    }

    /// A tiny generated avatar so list scrolling exercises image decode.
    private static func avatarJPEG(seed: Int) -> Data? {
        let side: CGFloat = 300
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            UIColor(hue: CGFloat(seed % 20) / 20, saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: side / 4, y: side / 4, width: side / 2, height: side / 2))
        }.jpegData(compressionQuality: 0.7)
    }
}
#endif
