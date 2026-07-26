import SwiftUI
import SwiftData
import LocalAuthentication
import StoreKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    /// Fill in once Memento has an App Store listing — enables the direct
    /// write-review deep link (works for both the iOS and Mac App Store).
    /// While empty, the Rate button falls back to the system's in-app
    /// review prompt instead.
    private static let appStoreID = "6791973402"
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
    @AppStorage(AppDateFormat.storageKey) private var dateFormatRaw = AppDateFormat.system.rawValue
    @AppStorage(UsageAnalytics.optOutKey) private var usageOptOut = false
    @State private var showingUsageDashboard = false

    // Backup & transfer
    @State private var exportShareItem: TreeImageExport.Item?
    @State private var showingDataImport = false
    @State private var dataResultTitle = ""
    @State private var dataResultMessage = ""
    @State private var showingDataResult = false
    @State private var isExporting = false
    /// A generous ceiling so a photo-heavy backup still imports, without
    /// slurping a pathologically large file whole into memory.
    private static let maxImportBytes = 200 * 1024 * 1024

    /// The toggle reads naturally ("share on/off") while storage stays an
    /// opt-out flag; switching off also triggers the remote cleanup.
    private var shareUsageBinding: Binding<Bool> {
        Binding(
            get: { !usageOptOut },
            set: { share in
                usageOptOut = !share
                if !share {
                    UsageAnalytics.handleOptOut()
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Birthday & date reminders", isOn: $remindersEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("9 AM alerts for birthdays and important dates. Skips in-memoriam people and dates you've turned off; keeps the nearest 60.")
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
                        Text("Adds a “Memento” calendar of everyone's dates that you can show or hide in the Calendar app. Includes dates with reminders off.")
                        if calendarSyncEnabled {
                            if manualSyncOnly {
                                Text("Changes reach Apple Calendar only when you tap Sync Now.")
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
                    Text("Import contacts with their names, photos, birthdays and details.")
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export All Data (Backup)…", systemImage: "arrow.up.doc")
                    }
                    .disabled(isExporting)
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export as Spreadsheet (CSV)…", systemImage: "tablecells")
                    }
                    .disabled(isExporting)
                    Button {
                        showingDataImport = true
                    } label: {
                        Label("Import Backup or CSV…", systemImage: "arrow.down.doc")
                    }
                } header: {
                    Text("Backup & Transfer")
                } footer: {
                    Text("Export a complete backup — everyone in both workspaces, notes, dates, photos and family links — as a single file you can save or move to another device, and import it back on any version of Memento. The CSV holds people, notes and dates in a spreadsheet (no photos or family tree) and imports back too.")
                }

                Section {
                    Picker("Date format", selection: $dateFormatRaw) {
                        ForEach(AppDateFormat.allCases) { format in
                            Text(format.label).tag(format.rawValue)
                        }
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text("Used everywhere Memento shows a date. System follows your device's region settings.")
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
                    Text("Locks Memento with your PIN\(AppLock.biometryType != .none ? " or \(AppLock.biometryName)" : "") when you leave it. Forgot your PIN? Reinstall — iCloud restores your data.")
                }

                Section {
                    Toggle("Share anonymous usage statistics", isOn: shareUsageBinding)
                } header: {
                    Text("Anonymous Usage Statistics")
                } footer: {
                    Text("Sends a daily count of app opens and contacts created under a random identifier — never your name, notes, photos, dates or anything you've written. Turning this off also deletes the counts this device already sent.")
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
                    // The About sheet is gone; this is the version's home now.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reviews help others find Memento; feedback reaches the developer.")
                        Text(aboutLine)
                            // The developer's hidden usage dashboard —
                            // seven taps, same spirit as build-number
                            // easter eggs. Harmless if found: it shows only
                            // the anonymous aggregate counts described in
                            // the toggle's footer above.
                            .onTapGesture(count: 7) { showingUsageDashboard = true }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Reset All Data…", systemImage: "trash")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permanently deletes every profile and note from all devices on your iCloud. Folders stay, emptied.")
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
            .sheet(item: $exportShareItem) { item in
                ActivityShareSheet(url: item.url)
            }
            .fileImporter(
                isPresented: $showingDataImport,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText, .item]
            ) { result in
                handleDataImport(result)
            }
            .alert(dataResultTitle, isPresented: $showingDataResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataResultMessage)
            }
            .sheet(isPresented: $showingUsageDashboard) {
                UsageDashboardView()
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
                Text("Permanently deletes all profiles and notes from every device on your iCloud. Can't be undone.")
            }
            .alert("Couldn't Save PIN", isPresented: $pinSaveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                // A failed change-PIN can leave the previous PIN in place
                // (delete failed too) — "left off" would then be a lie
                // about which key opens the app.
                Text(AppLock.storedPIN == nil
                    ? "Your PIN wasn't saved. App Lock has been left off — please try again."
                    : "Your new PIN wasn't saved — your previous PIN is still in effect.")
            }
            .onChange(of: remindersEnabled) { _, isOn in
                Task { @MainActor in
                    if isOn {
                        let granted = await NotificationManager.requestPermission()
                        if !granted {
                            remindersEnabled = false
                            reminderNote = "Turn on notifications in \(Self.systemSettingsName), then try again."
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
                            calendarSyncNote = "Turn on Calendar access in \(Self.systemSettingsName), then try again."
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
            .onChange(of: manualSyncOnly) { _, isManual in
                // Edits made while in manual mode never reached the calendar
                // (refreshFromContext is gated on this flag), so switching
                // back to Automatically must catch up now — otherwise the
                // calendar stays stale until the next date-affecting save,
                // which reads as broken. (syncNow no-ops if sync is off.)
                if !isManual {
                    CalendarSyncManager.syncNow(context)
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
            for edge in try context.fetch(FetchDescriptor<Parentage>()) { context.delete(edge) }
            for edge in try context.fetch(FetchDescriptor<Partnership>()) { context.delete(edge) }
            // The hidden "You" node the family tree roots on went down with
            // everything else. Recreate it now rather than waiting for the
            // next launch — until then the tree's "Add Family" editor would
            // open as a blank sheet.
            let selfNode = Person(name: "You")
            selfNode.isSelf = true
            context.insert(selfNode)
            try context.save()
            resetNote = nil
        } catch {
            // Without the rollback, every queued deletion stays pending in
            // the shared main context — the next successful save from
            // anywhere would silently commit the full wipe (and sync it to
            // every device) right after this message promised nothing was
            // deleted.
            context.rollback()
            resetNote = "Something went wrong and your data was not deleted. Please try again."
            return
        }
        NotificationManager.refreshFromContext(context)
        CalendarSyncManager.refreshFromContext(context)
    }

    // MARK: - Backup & transfer

    private func exportBackup() {
        isExporting = true
        // Encoding walks every note and base64s every photo; keep it off the
        // main thread so a large store doesn't freeze Settings. The build
        // reads SwiftData on the main context, so snapshot there, encode on
        // a background task, then present on the main actor.
        let archive = DataArchiveExport.makeArchive(context)
        Task.detached {
            let url = DataArchiveExport.writeArchive(archive)
            await MainActor.run {
                isExporting = false
                if let url {
                    exportShareItem = TreeImageExport.Item(url: url)
                } else {
                    showResult("Export Failed", "Memento couldn't create the backup file. Please try again.")
                }
            }
        }
    }

    private func exportCSV() {
        if let url = MementoCSV.writeCSVFile(context) {
            exportShareItem = TreeImageExport.Item(url: url)
        } else {
            showResult("Export Failed", "Memento couldn't create the CSV file. Please try again.")
        }
    }

    private func handleDataImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > Self.maxImportBytes {
                showResult("File Too Large", "That file is over 200 MB and can't be imported.")
                return
            }
            let data = try Data(contentsOf: url)
            // Sniff by content, not extension: try a full backup first (it's
            // marked with `format`), then read it as a Memento CSV. Only
            // "wrong format" falls through to the next attempt — a real
            // failure (a backup from a newer breaking format, or the save
            // failing) surfaces through the outer catch instead.
            do {
                let summary = try DataArchiveImport.importArchive(data, into: context)
                showResult("Backup Imported", summary.headline + ".")
                return
            } catch DataArchiveError.notAnArchive {}
            if let text = String(data: data, encoding: .utf8) {
                do {
                    let summary = try MementoCSV.importCSV(text, into: context)
                    showResult("Data Imported", summary.headline + ".")
                    return
                } catch DataArchiveError.notAnArchive, DataArchiveError.unreadable {}
            }
            showResult("Couldn't Import", "That file isn't a Memento backup or a Memento CSV export.")
        } catch {
            showResult("Import Failed", error.localizedDescription)
        }
    }

    private func showResult(_ title: String, _ message: String) {
        dataResultTitle = title
        dataResultMessage = message
        showingDataResult = true
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

    private var aboutLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Memento \(version) (\(build)) · SwiftUI + SwiftData · synced via your private iCloud"
    }

    private var lastSyncedText: String {
        guard lastSyncTimestamp > 0 else { return "Not synced yet." }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        return "Last synced \(date.appFormatted()) \(date.formatted(date: .omitted, time: .shortened))."
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
