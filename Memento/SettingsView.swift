import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var apiKey = ""
    @State private var savedKeyExists = ClaudeService.storedAPIKey?.isEmpty == false
    @AppStorage(NotificationManager.enabledKey) private var remindersEnabled = false
    @State private var reminderNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if savedKeyExists {
                        Label("API key saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.olive)
                        Button("Remove API Key", role: .destructive) {
                            KeychainHelper.delete(ClaudeService.apiKeyKeychainKey)
                            savedKeyExists = false
                            apiKey = ""
                        }
                    } else {
                        SecureField("sk-ant-…", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save API Key") {
                            KeychainHelper.save(apiKey.trimmed, for: ClaudeService.apiKeyKeychainKey)
                            savedKeyExists = true
                        }
                        .disabled(apiKey.trimmed.isEmpty)
                    }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Smart Capture uses Claude (\(ClaudeService.model)) to turn transcripts into notes and profile suggestions. Create a key at console.anthropic.com. It's stored in your device Keychain, requests go straight from your phone to Anthropic, and standard API usage rates apply to your account.")
                }

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

                Section {
                    stepRow(1, "Record the conversation on your phone.")
                    stepRow(2, "It's transcribed on-device when your iPhone supports it.")
                    stepRow(3, "Only the transcript text and that person's existing profile are sent to Claude — never audio or photos.")
                    stepRow(4, "You review and edit everything before it's saved.")
                } header: {
                    Text("How Smart Capture Works")
                } footer: {
                    Text("A word on courtesy and the law: recording-consent rules vary by country and state. Make sure everyone is happy to be recorded before you start.")
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

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.aegean, in: Circle())
            Text(text)
                .font(.callout)
        }
        .padding(.vertical, 2)
    }
}
