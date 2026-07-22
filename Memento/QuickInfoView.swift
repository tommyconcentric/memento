import SwiftUI
import SwiftData

/// The at-a-glance card of preset details (birthday, family, hobbies…).
/// Deliberately separate from the running notes timeline.
struct QuickInfoView: View {
    let person: Person
    var onEdit: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(AppDateFormat.storageKey) private var dateFormatRaw = AppDateFormat.system.rawValue

    var body: some View {
        VStack(spacing: 16) {
            // Projects count as content in their own right — a profile
            // holding nothing but shared projects must not fall into the
            // "No Details Yet" empty state and hide them.
            if person.hasAnyQuickInfo || !person.projectsArray.isEmpty {
                if person.hasAnyQuickInfo {
                    infoCard
                }

                if !person.projectsArray.isEmpty {
                    projectsCard
                }

                if (person.birthday != nil || !person.importantDatesArray.isEmpty) && !person.isDeceased {
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

    /// Shared work with this contact: ongoing first, wrapped-up history
    /// below. Edited from the same editor as everything else.
    private var projectsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.1)
                .foregroundStyle(.secondary)
            ForEach(person.sortedProjects) { project in
                HStack(spacing: 10) {
                    Image(systemName: project.isCompleted ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(project.isCompleted ? Theme.olive : Color.accentColor)
                    Text(project.name)
                        .font(.body)
                    Spacer(minLength: 0)
                    Text(project.isCompleted ? "Completed" : "Ongoing")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (project.isCompleted ? Theme.olive : Theme.steel).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(project.isCompleted ? Theme.olive : Theme.graphite)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mementoCard()
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
            InfoRow(
                icon: person.isBusiness ? "person.crop.rectangle" : "person",
                label: person.isBusiness ? "Working Relationship" : "Relationship",
                value: "Your \(person.relationshipToUser.lowercased())"
            )
        }
        if let birthday = person.birthday {
            // Reminders never fire for in-memoriam people, so a live-looking
            // toggle would promise one that can't happen — plain text there.
            if person.isDeceased {
                InfoRow(icon: "gift", label: "Birthday", value: birthdayText(birthday))
            } else {
                dateRow(
                    icon: "gift", label: "Birthday", value: birthdayText(birthday),
                    isOn: Binding(
                        get: { person.birthdayReminderEnabled },
                        set: { person.birthdayReminderEnabled = $0; saveDateChange() }
                    )
                )
            }
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
        contactRows(.phone, primary: person.phoneNumber)
        contactRows(.email, primary: person.email)
        contactRows(.address, primary: person.address)
        ForEach(person.importantDatesArray.sorted { $0.date < $1.date }) { item in
            if person.isDeceased {
                InfoRow(icon: "calendar.badge.clock", label: item.label, value: dateText(item.date))
            } else {
                dateRow(
                    icon: "calendar.badge.clock", label: item.label, value: dateText(item.date),
                    isOn: Binding(
                        get: { item.remindersEnabled },
                        set: { item.remindersEnabled = $0; saveDateChange() }
                    )
                )
            }
        }
    }

    /// All values of one contact kind. A starred extra is the preferred one
    /// and leads with a gold star; otherwise the primary field leads and
    /// extras follow in entry order.
    @ViewBuilder
    private func contactRows(_ kind: ContactField.Kind, primary: String) -> some View {
        let preferred = person.preferredContact(kind)
        if let preferred {
            preferredRow(icon: kind.icon, label: kind.label, value: preferred.value)
        }
        if !primary.isEmpty {
            InfoRow(icon: kind.icon, label: kind.label, value: primary)
        }
        ForEach(person.additionalContacts(kind).filter {
            $0.persistentModelID != preferred?.persistentModelID
        }) { field in
            InfoRow(icon: kind.icon, label: kind.label, value: field.value)
        }
    }

    /// Same layout as `InfoRow`, plus the trailing star that marks the
    /// user's preferred contact method of its kind.
    private func preferredRow(icon: String, label: String, value: String) -> some View {
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
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(Theme.gold)
                .accessibilityLabel("Preferred \(label.lowercased())")
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
        // Year-less birthdays from contact import carry a placeholder year
        // the user never entered — show only the month and day.
        let dateText = birthday.hasPlaceholderYear
            ? birthday.appFormattedMonthDay()
            : birthday.appFormatted()
        if person.isDeceased {
            return dateText
        }
        var parts = [dateText]
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
        var value = date.appFormatted()
        if !person.isDeceased, let days = Date.daysUntilNextOccurrence(of: date), days <= 60 {
            value += days == 0 ? " · today" : " · in \(days)d"
        }
        return value
    }
}
