import SwiftUI
import SwiftData

/// The at-a-glance card of preset details (birthday, family, hobbies…).
/// Deliberately separate from the running notes timeline.
struct QuickInfoView: View {
    let person: Person
    var onEdit: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 16) {
            if person.hasAnyQuickInfo {
                infoCard

                if person.birthday != nil || !person.importantDatesArray.isEmpty {
                    Text("Toggle a date to turn its reminder on or off — every date still shows on the Memento calendar either way.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

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
            dateRow(
                icon: "gift", label: "Birthday", value: birthdayText(birthday),
                isOn: Binding(
                    get: { person.birthdayReminderEnabled },
                    set: { person.birthdayReminderEnabled = $0; saveDateChange() }
                )
            )
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
        ForEach(person.additionalContacts(.phone)) { field in
            InfoRow(icon: "phone", label: "Phone", value: field.value)
        }
        if !person.email.isEmpty {
            InfoRow(icon: "envelope", label: "Email", value: person.email)
        }
        ForEach(person.additionalContacts(.email)) { field in
            InfoRow(icon: "envelope", label: "Email", value: field.value)
        }
        if !person.address.isEmpty {
            InfoRow(icon: "mappin", label: "Address", value: person.address)
        }
        ForEach(person.additionalContacts(.address)) { field in
            InfoRow(icon: "mappin", label: "Address", value: field.value)
        }
        ForEach(person.importantDatesArray.sorted { $0.date < $1.date }) { item in
            dateRow(
                icon: "calendar.badge.clock", label: item.label, value: dateText(item.date),
                isOn: Binding(
                    get: { item.remindersEnabled },
                    set: { item.remindersEnabled = $0; saveDateChange() }
                )
            )
        }
    }

    /// Same layout as `InfoRow`, plus a trailing reminder toggle. Mutating
    /// the toggle writes straight through to the live model (like
    /// PersonDetailView's "Mark as Deceased" toggle) rather than going
    /// through the cancel-safe editor draft flow — it's a single boolean
    /// flip with nothing to lose by committing immediately.
    private func dateRow(icon: String, label: String, value: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            Spacer(minLength: 0)
            Toggle(isOn: isOn) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("Remind me for \(label)")
        }
    }

    private func saveDateChange() {
        try? context.save()
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
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
