import SwiftUI

/// The at-a-glance card of preset details (birthday, family, hobbies…).
/// Deliberately separate from the running notes timeline.
struct QuickInfoView: View {
    let person: Person
    var onEdit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if person.hasAnyQuickInfo {
                infoCard

                Button(action: onEdit) {
                    Label("Edit Details", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                ContentUnavailableView {
                    Label("No Details Yet", systemImage: "list.clipboard")
                } description: {
                    Text("Add the things you always want at your fingertips — birthday, family, hobbies, how you met.")
                } actions: {
                    Button("Add Details", action: onEdit)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            rows
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mementoCard()
    }

    @ViewBuilder
    private var rows: some View {
        if !person.relationshipToUser.isEmpty {
            InfoRow(icon: "person", label: "Relationship", value: "Your \(person.relationshipToUser.lowercased())")
        }
        if let birthday = person.birthday {
            InfoRow(icon: "gift", label: "Birthday", value: birthdayText(birthday))
        }
        if !person.partnerName.isEmpty {
            InfoRow(icon: "heart", label: "Partner", value: person.partnerName)
        }
        if !person.childrenNames.isEmpty {
            InfoRow(icon: "figure.2.and.child.holdinghands", label: "Children", value: person.childrenNames)
        }
        if !person.otherFamily.isEmpty {
            InfoRow(icon: "person.2", label: "Family", value: person.otherFamily)
        }
        if !person.jobTitle.isEmpty || !person.company.isEmpty {
            InfoRow(
                icon: "briefcase",
                label: "Work",
                value: [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }
        if !person.hobbies.isEmpty {
            InfoRow(icon: "star", label: "Hobbies & Interests", value: person.hobbies)
        }
        if !person.hometown.isEmpty {
            InfoRow(icon: "house", label: "Hometown", value: person.hometown)
        }
        if !person.howWeMet.isEmpty {
            InfoRow(icon: "sparkles", label: "How We Met", value: person.howWeMet)
        }
        if !person.foodPreferences.isEmpty {
            InfoRow(icon: "fork.knife", label: "Food & Drink", value: person.foodPreferences)
        }
        if !person.phoneNumber.isEmpty {
            InfoRow(icon: "phone", label: "Phone", value: person.phoneNumber)
        }
        if !person.email.isEmpty {
            InfoRow(icon: "envelope", label: "Email", value: person.email)
        }
        if !person.address.isEmpty {
            InfoRow(icon: "mappin", label: "Address", value: person.address)
        }
        ForEach(person.importantDatesArray.sorted { $0.date < $1.date }) { item in
            InfoRow(icon: "calendar.badge.clock", label: item.label, value: dateText(item.date))
        }
    }

    private func birthdayText(_ birthday: Date) -> String {
        if person.isDeceased {
            return birthday.formatted(date: .abbreviated, time: .omitted)
        }
        var parts = [birthday.formatted(date: .abbreviated, time: .omitted)]
        if let age = person.age, age > 0, age < 120 {
            parts.append("age \(age)")
        }
        var value = parts.joined(separator: " · ")
        if let days = person.daysUntilNextBirthday, days <= 60 {
            value += days == 0 ? " · 🎉 today" : " · in \(days)d"
        }
        return value
    }

    private func dateText(_ date: Date) -> String {
        var value = date.formatted(date: .abbreviated, time: .omitted)
        if !person.isDeceased, let days = Date.daysUntilNextOccurrence(of: date), days <= 60 {
            value += days == 0 ? " · today" : " · in \(days)d"
        }
        return value
    }
}
