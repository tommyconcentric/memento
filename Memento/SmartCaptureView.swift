import SwiftUI
import SwiftData

/// Record a catch-up, transcribe it on-device, then let Claude draft a note
/// and suggest profile updates. Nothing is saved until the person reviews it.
struct SmartCaptureView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var transcriber = SpeechTranscriber()
    @State private var phase: Phase = .ready
    @State private var startedAt = Date.now
    @State private var editedTranscript = ""
    @State private var noteText = ""
    @State private var noteLocation = ""
    @State private var changes: [ProposedChange] = []
    @State private var analysisError: String?
    @State private var showingSettings = false

    enum Phase { case ready, recording, transcript, analyzing, proposal }

    struct ProposedChange: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        var isSelected = true
        let apply: (Person) -> Void
    }

    private var hasAPIKey: Bool {
        ClaudeService.storedAPIKey?.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready: readyView
                case .recording: recordingView
                case .transcript: transcriptView
                case .analyzing: analyzingView
                case .proposal: proposalView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Smart Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        transcriber.stop()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Ready

    private var readyView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(Theme.aegean)

            Text("Record your catch-up with \(person.name). Memento transcribes it on your phone, then Claude drafts a note and suggests profile updates — you approve everything before it's saved.")
                .font(.callout)
                .multilineTextAlignment(.center)

            if let message = transcriber.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.terracotta)
                    .multilineTextAlignment(.center)
            }

            Button {
                startRecording()
            } label: {
                Label("Start Recording", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !hasAPIKey {
                VStack(spacing: 6) {
                    Text("No API key yet — you can still record and save the raw transcript as a note.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add API Key in Settings") { showingSettings = true }
                        .font(.footnote.weight(.medium))
                }
            }

            Spacer()

            Text("Recording-consent laws vary by place — make sure everyone is happy to be recorded.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.bougainvillea.opacity(0.2))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(Theme.bougainvillea)
                    .frame(width: 72, height: 72)
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .padding(.top, 12)

            TimelineView(.periodic(from: startedAt, by: 1)) { timelineContext in
                Text(elapsedString(at: timelineContext.date))
                    .font(.title3.monospacedDigit().weight(.medium))
            }

            ScrollView {
                Text(transcriber.transcript.isEmpty ? "Listening…" : transcriber.transcript)
                    .font(.callout)
                    .foregroundStyle(transcriber.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .mementoCard(padding: 0)

            Button {
                stopRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.bougainvillea)
            .controlSize(.large)
        }
        .padding(20)
    }

    // MARK: - Transcript review

    private var transcriptView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Transcript")
                    .font(.headline)
                Text("Fix any misheard names or details before analyzing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $editedTranscript)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .mementoCard(padding: 8)

                if editedTranscript.trimmed.isEmpty {
                    Text("Nothing was transcribed — try re-recording a little closer to the speakers.")
                        .font(.footnote)
                        .foregroundStyle(Theme.terracotta)
                }

                if let analysisError {
                    Text(analysisError)
                        .font(.footnote)
                        .foregroundStyle(Theme.terracotta)
                }

                Button {
                    analyze()
                } label: {
                    Label("Analyze with AI", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(editedTranscript.trimmed.isEmpty)

                Button {
                    saveTranscriptAsNote()
                } label: {
                    Label("Save Transcript as Note", systemImage: "note.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(editedTranscript.trimmed.isEmpty)

                Button("Re-record") {
                    editedTranscript = ""
                    analysisError = nil
                    phase = .ready
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Claude is reading the conversation…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Proposal

    private var proposalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Note")
                    .font(.headline)

                TextEditor(text: $noteText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .mementoCard(padding: 8)

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Theme.aegean)
                    TextField("Location (optional)", text: $noteLocation)
                }
                .mementoCard(padding: 12)

                Text("Suggested Profile Updates")
                    .font(.headline)
                    .padding(.top, 4)

                if changes.isEmpty {
                    Text("No new profile details were found — just the note will be saved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mementoCard(padding: 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach($changes) { $change in
                            Toggle(isOn: $change.isSelected) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(change.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            if change.id != changes.last?.id {
                                Divider()
                            }
                        }
                    }
                    .mementoCard(padding: 12)
                }

                Button {
                    saveProposal()
                } label: {
                    Label("Save to \(person.name)", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(noteText.trimmed.isEmpty && changes.allSatisfy { !$0.isSelected })

                Button("Back to Transcript") {
                    phase = .transcript
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func startRecording() {
        startedAt = .now
        Task { @MainActor in
            await transcriber.start()
            phase = transcriber.isRecording ? .recording : .ready
        }
    }

    private func stopRecording() {
        transcriber.stop()
        editedTranscript = transcriber.transcript.trimmed
        phase = .transcript
    }

    private func analyze() {
        guard hasAPIKey else {
            showingSettings = true
            return
        }
        analysisError = nil
        phase = .analyzing
        Task { @MainActor in
            do {
                let insights = try await ClaudeService.extractInsights(
                    transcript: editedTranscript,
                    person: person
                )
                buildProposal(from: insights)
                phase = .proposal
            } catch {
                analysisError = error.localizedDescription
                phase = .transcript
            }
        }
    }

    private func saveTranscriptAsNote() {
        let note = NoteEntry(text: editedTranscript.trimmed, eventDate: .now, location: "")
        person.notes.append(note)
        try? context.save()
        dismiss()
    }

    private func saveProposal() {
        if !noteText.trimmed.isEmpty || !noteLocation.trimmed.isEmpty {
            let note = NoteEntry(
                text: noteText.trimmed,
                eventDate: .now,
                location: noteLocation.trimmed
            )
            person.notes.append(note)
        }
        for change in changes where change.isSelected {
            change.apply(person)
        }
        try? context.save()
        NotificationManager.refreshFromContext(context)
        dismiss()
    }

    // MARK: - Proposal building

    private func buildProposal(from insights: ConversationInsights) {
        let summary = insights.noteSummary?.trimmed ?? ""
        noteText = summary.isEmpty ? editedTranscript : summary
        noteLocation = insights.location?.trimmed ?? ""

        var proposed: [ProposedChange] = []

        if let info = insights.quickInfo {
            appendChange(&proposed, "Partner", current: person.partnerName, new: info.partnerName) { $0.partnerName = $1 }
            appendChange(&proposed, "Children", current: person.childrenNames, new: info.childrenNames) { $0.childrenNames = $1 }
            appendChange(&proposed, "Family", current: person.otherFamily, new: info.otherFamily) { $0.otherFamily = $1 }
            appendChange(&proposed, "Job Title", current: person.jobTitle, new: info.jobTitle) { $0.jobTitle = $1 }
            appendChange(&proposed, "Company", current: person.company, new: info.company) { $0.company = $1 }
            appendChange(&proposed, "Hobbies", current: person.hobbies, new: info.hobbies) { $0.hobbies = $1 }
            appendChange(&proposed, "Hometown", current: person.hometown, new: info.hometown) { $0.hometown = $1 }
            appendChange(&proposed, "How We Met", current: person.howWeMet, new: info.howWeMet) { $0.howWeMet = $1 }
            appendChange(&proposed, "Food & Drink", current: person.foodPreferences, new: info.foodPreferences) { $0.foodPreferences = $1 }

            if let birthdayString = info.birthday,
               let date = ClaudeService.parseDay(birthdayString) {
                let differs = person.birthday.map {
                    !Calendar.current.isDate($0, inSameDayAs: date)
                } ?? true
                if differs {
                    let currentText = person.birthday?.formatted(date: .abbreviated, time: .omitted) ?? ""
                    let newText = date.formatted(date: .abbreviated, time: .omitted)
                    proposed.append(ProposedChange(
                        title: "Birthday",
                        detail: detailText(current: currentText, new: newText)
                    ) { $0.birthday = date })
                }
            }
        }

        for suggestion in insights.importantDates ?? [] {
            guard let date = ClaudeService.parseDay(suggestion.date) else { continue }
            let label = suggestion.label.trimmed
            guard !label.isEmpty else { continue }
            let alreadyExists = person.importantDates.contains {
                $0.label.caseInsensitiveCompare(label) == .orderedSame &&
                Calendar.current.isDate($0.date, inSameDayAs: date)
            }
            guard !alreadyExists else { continue }
            proposed.append(ProposedChange(
                title: label,
                detail: "Add important date: \(date.formatted(date: .abbreviated, time: .omitted))"
            ) { $0.importantDates.append(ImportantDate(label: label, date: date)) })
        }

        changes = proposed
    }

    private func appendChange(
        _ list: inout [ProposedChange],
        _ title: String,
        current: String,
        new: String?,
        apply: @escaping (Person, String) -> Void
    ) {
        guard let value = new?.trimmed, !value.isEmpty,
              value.caseInsensitiveCompare(current.trimmed) != .orderedSame else { return }
        list.append(ProposedChange(
            title: title,
            detail: detailText(current: current, new: value)
        ) { apply($0, value) })
    }

    private func detailText(current: String, new: String) -> String {
        current.trimmed.isEmpty ? new : "\(current) → \(new)"
    }

    private func elapsedString(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
