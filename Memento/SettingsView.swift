import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(NotificationManager.enabledKey) private var remindersEnabled = false
    @State private var reminderNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Birthday & date reminders", isOn: $remindersEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A 9 AM notification on birthdays and important dates. Reminders skip people marked in memoriam, and iOS allows up to 60 scheduled dates — the nearest ones are kept.")
                        if let reminderNote {
                            Text(reminderNote)
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
                }
            }
            .onChange(of: remindersEnabled) { _, isOn in
                Task { @MainActor in
                    if isOn {
                        let granted = await NotificationManager.requestPermission()
                        if !granted {
                            remindersEnabled = false
                            reminderNote = "Notifications are turned off for Memento — enable them in the iOS Settings app, then try again."
                            NotificationManager.refreshFromContext(context)
                            return
                        }
                        reminderNote = nil
                    }
                    NotificationManager.refreshFromContext(context)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
