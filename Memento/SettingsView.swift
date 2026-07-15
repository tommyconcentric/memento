import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(NotificationManager.enabledKey) private var remindersEnabled = false
    @State private var reminderNote: String?

    @AppStorage(CalendarSyncManager.enabledKey) private var calendarSyncEnabled = false
    @State private var calendarSyncNote: String?

    @AppStorage(AppLock.enabledKey) private var appLockEnabled = false
    @AppStorage(AppLock.useBiometricsKey) private var useBiometrics = false
    @State private var showingPINSetup = false
    @State private var pinSaveFailed = false

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
                } header: {
                    Text("Apple Calendar")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adds a “Memento” calendar with everyone's birthdays and important dates, so you can show or hide it in the Calendar app just like Birthdays or Holidays. Every date appears here, even ones you've turned reminders off for.")
                        if let calendarSyncNote {
                            Text(calendarSyncNote)
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
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
                            reminderNote = "Notifications are turned off for Memento — enable them in the iOS Settings app, then try again."
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
                            calendarSyncNote = "Calendar access is turned off for Memento — enable it in the iOS Settings app, then try again."
                            return
                        }
                        calendarSyncNote = nil
                        CalendarSyncManager.refreshFromContext(context)
                    } else {
                        calendarSyncNote = nil
                        CalendarSyncManager.removeCalendar()
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
