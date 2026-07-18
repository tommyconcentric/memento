import SwiftUI
import SwiftData
import LocalAuthentication
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    /// Fill in once Memento has an App Store listing — enables the direct
    /// write-review deep link (works for both the iOS and Mac App Store).
    /// While empty, the Rate button falls back to the system's in-app
    /// review prompt instead.
    private static let appStoreID = ""
    private static let feedbackAddress = "tommy@concentric.health"
    /// Where permission recovery actually lives: there is no "iOS Settings
    /// app" when the app runs on a Mac — pointing users there is misleading
    /// exactly when they need unblocking.
    private static let systemSettingsName =
        ProcessInfo.processInfo.isiOSAppOnMac ? "System Settings" : "the iOS Settings app"
    @AppStorage(NotificationManager.enabledKey) private var remindersEnabled = false
    @State private var reminderNote: String?

    @AppStorage(CalendarSyncManager.enabledKey) private var calendarSyncEnabled = false
    @AppStorage(CalendarSyncManager.manualSyncOnlyKey) private var manualSyncOnly = false
    @AppStorage(CalendarSyncManager.lastSyncKey) private var lastSyncTimestamp = 0.0
    @State private var calendarSyncNote: String?

    @AppStorage(AppLock.enabledKey) private var appLockEnabled = false
    @AppStorage(AppLock.useBiometricsKey) private var useBiometrics = false
    @State private var showingPINSetup = false
    @State private var pinSaveFailed = false

    @State private var showingResetConfirm = false
    @State private var resetNote: String?

    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Birthday & date reminders", isOn: $remindersEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A 9 AM notification on birthdays and important dates. Reminders skip people marked in memoriam and any date you've turned off from its Quick Info tab, and iOS allows up to 60 scheduled dates — the nearest ones are kept.")
                        if let reminderNote {
                            Text(reminderNote)
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
                }

                Section {
                    Toggle("Sync with Apple Calendar", isOn: $calendarSyncEnabled)
                    if calendarSyncEnabled {
                        Picker("Keep up to date", selection: $manualSyncOnly) {
                            Text("Automatically").tag(false)
                            Text("Manually").tag(true)
                        }
                        Button {
                            CalendarSyncManager.syncNow(context)
                        } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } header: {
                    Text("Apple Calendar")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adds a “Memento” calendar with everyone's birthdays and important dates, so you can show or hide it in the Calendar app just like Birthdays or Holidays. Every date appears here, even ones you've turned reminders off for.")
                        if calendarSyncEnabled {
                            if manualSyncOnly {
                                Text("Changes you make in Memento only reach Apple Calendar when you tap Sync Now.")
                            }
                            Text(lastSyncedText)
                        }
                        if let calendarSyncNote {
                            Text(calendarSyncNote)
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
                }

                Section {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import from Contacts…", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Contacts")
                } footer: {
                    Text("Pick people from your contacts — names, photos, birthdays and every number, email and address come along.")
                }

                Section {
                    Toggle("Require a PIN to open Memento", isOn: appLockToggleBinding)
                    if appLockEnabled {
                        if AppLock.biometryType != .none {
                            Toggle("Unlock with \(AppLock.biometryName)", isOn: $useBiometrics)
                        }
                        Button("Change PIN") { showingPINSetup = true }
                    }
                } header: {
                    Text("App Lock")
                } footer: {
                    Text("Locks Memento with your PIN\(AppLock.biometryType != .none ? " or \(AppLock.biometryName)" : "") whenever you leave the app. If you ever forget the PIN, delete and reinstall Memento — your data is safe and restores automatically from iCloud once you sign back in.")
                }

                Section {
                    Button {
                        rateMemento()
                    } label: {
                        Label("Rate Memento", systemImage: "star")
                    }
                    Button {
                        sendFeedback()
                    } label: {
                        Label("Send Feedback & Suggestions", systemImage: "envelope")
                    }
                } header: {
                    Text("Help & Feedback")
                } footer: {
                    Text("Reviews help other people find Memento, and feedback goes straight to the developer.")
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Reset All Data…", systemImage: "trash")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permanently deletes every profile and every note from Memento. Because your data syncs through iCloud, they are also removed from all devices signed into your account. Folders are kept, but emptied.")
                        if let resetNote {
                            Text(resetNote)
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportContactsView()
            }
            .sheet(isPresented: $showingPINSetup) {
                PINSetupView(
                    onComplete: { pin in
                        // Only trust the Keychain write if it's verified to have
                        // landed — never enable the lock on a false positive,
                        // or the PIN becomes the only key and it doesn't exist.
                        if AppLock.savePIN(pin) {
                            appLockEnabled = true
                        } else {
                            pinSaveFailed = true
                            if AppLock.storedPIN == nil { appLockEnabled = false }
                        }
                        showingPINSetup = false
                    },
                    onCancel: {
                        // Cancelling a first-time setup leaves nothing to protect with.
                        if AppLock.storedPIN == nil { appLockEnabled = false }
                        showingPINSetup = false
                    }
                )
            }
            .alert("Reset All Data?", isPresented: $showingResetConfirm) {
                Button("Delete Everything", role: .destructive) { resetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all profiles and notes in Memento. The deletion syncs to every device signed into your iCloud account, and it cannot be undone.")
            }
            .alert("Couldn't Save PIN", isPresented: $pinSaveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your PIN wasn't saved. App Lock has been left off — please try again.")
            }
            .onChange(of: remindersEnabled) { _, isOn in
                Task { @MainActor in
                    if isOn {
                        let granted = await NotificationManager.requestPermission()
                        if !granted {
                            remindersEnabled = false
                            reminderNote = "Notifications are turned off for Memento — enable them in \(Self.systemSettingsName), then try again."
                            NotificationManager.refreshFromContext(context)
                            return
                        }
                        reminderNote = nil
                    }
                    NotificationManager.refreshFromContext(context)
                }
            }
            .onChange(of: calendarSyncEnabled) { _, isOn in
                Task { @MainActor in
                    if isOn {
                        let granted = await CalendarSyncManager.requestAccess()
                        if !granted {
                            calendarSyncEnabled = false
                            calendarSyncNote = "Calendar access is turned off for Memento — enable it in \(Self.systemSettingsName), then try again."
                            return
                        }
                        calendarSyncNote = nil
                        // Populate immediately even in manual mode — an
                        // empty calendar until the first Sync Now would
                        // read as broken.
                        CalendarSyncManager.syncNow(context)
                    } else {
                        // Don't clear calendarSyncNote here: the denial path
                        // above flips the toggle off, which re-fires this
                        // handler — clearing the note in that re-entrant pass
                        // would erase the explanation the instant it was set.
                        // (The granted path clears it on the next attempt.)
                        CalendarSyncManager.removeCalendar()
                        lastSyncTimestamp = 0
                    }
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

    /// Deep-links to the App Store's write-review page when the app has a
    /// listing; otherwise asks StoreKit for the in-app rating prompt (which
    /// the system may rate-limit).
    private func rateMemento() {
        if Self.appStoreID.isEmpty {
            requestReview()
        } else if let url = URL(string: "https://apps.apple.com/app/id\(Self.appStoreID)?action=write-review") {
            openURL(url)
        }
    }

    /// Deletes every profile and note. Objects are deleted one by one, not
    /// with a batch delete: batch deletes skip relationship processing and
    /// don't reliably reach the CloudKit mirror, and the whole point here is
    /// that the wipe propagates to the user's other devices. People go first
    /// (cascades take their notes, dates, family members, contact fields and
    /// photos); the child types are then swept for orphans left behind by
    /// older versions of the schema.
    private func resetAllData() {
        do {
            for person in try context.fetch(FetchDescriptor<Person>()) { context.delete(person) }
            for note in try context.fetch(FetchDescriptor<NoteEntry>()) { context.delete(note) }
            for photo in try context.fetch(FetchDescriptor<EventPhoto>()) { context.delete(photo) }
            for date in try context.fetch(FetchDescriptor<ImportantDate>()) { context.delete(date) }
            for member in try context.fetch(FetchDescriptor<FamilyMember>()) { context.delete(member) }
            for field in try context.fetch(FetchDescriptor<ContactField>()) { context.delete(field) }
            for project in try context.fetch(FetchDescriptor<Project>()) { context.delete(project) }
            try context.save()
            resetNote = nil
        } catch {
            resetNote = "Something went wrong and your data was not deleted. Please try again."
            return
        }
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
    }

    private func sendFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Memento feedback"),
            URLQueryItem(name: "body", value: "\n\n—\nMemento \(version)")
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private var lastSyncedText: String {
        guard lastSyncTimestamp > 0 else { return "Not synced yet." }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        return "Last synced \(date.formatted(date: .abbreviated, time: .shortened))."
    }

    /// Turning the lock on requires setting a PIN first; turning it off
    /// clears the PIN entirely so nothing stale is left in the Keychain.
    private var appLockToggleBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { newValue in
                if newValue {
                    showingPINSetup = true
                } else {
                    appLockEnabled = false
                    useBiometrics = false
                    AppLock.clearPIN()
                }
            }
        )
    }
}
