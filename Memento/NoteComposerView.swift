import SwiftUI
import SwiftData
import PhotosUI

/// Creates a new note entry, or edits an existing one when `note` is set.
struct NoteComposerView: View {
    let person: Person
    let note: NoteEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var eventDate = Date.now
    @State private var location = ""
    @State private var drafts: [DraftPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var loadedInitial = false
    @State private var transcriber = SpeechTranscriber()
    @State private var dictationBaseText = ""

    struct DraftPhoto: Identifiable {
        let id = UUID()
        var data: Data
        var caption: String
        var existingID: PersistentIdentifier? = nil
    }

    private var canSave: Bool {
        !text.trimmed.isEmpty || !location.trimmed.isEmpty || !drafts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When & Where") {
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                    TextField("Location (e.g. Coffee at Marlowe's)", text: $location)
                }

                Section {
                    TextField(
                        "What happened? What did you talk about?",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(4...12)

                    Button {
                        if transcriber.isRecording {
                            transcriber.stop()
                        } else {
                            dictationBaseText = text.trimmed.isEmpty ? "" : text.trimmed + " "
                            Task { await transcriber.start() }
                        }
                    } label: {
                        Label(
                            transcriber.isRecording ? "Stop Dictation" : "Dictate",
                            systemImage: transcriber.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                        .foregroundStyle(transcriber.isRecording ? Theme.bougainvillea : Color.accentColor)
                    }
                } header: {
                    Text("Note")
                } footer: {
                    if let message = transcriber.errorMessage {
                        Text(message)
                            .foregroundStyle(Theme.terracotta)
                    }
                }

                Section {
                    ForEach($drafts) { $draft in
                        HStack(spacing: 12) {
                            if let uiImage = UIImage(data: draft.data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            TextField("Caption (optional)", text: $draft.caption)
                        }
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }

                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 8,
                        matching: .images
                    ) {
                        Label(
                            isLoadingPhotos ? "Adding Photos…" : "Add Photos",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                } header: {
                    Text("Event Photos")
                } footer: {
                    Text("Photos are saved with this note's date and location. Swipe left on a photo to remove it.")
                }
            }
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadInitial)
            .onChange(of: pickerItems) { _, items in
                appendPhotos(items)
            }
            .onChange(of: transcriber.transcript) { _, newValue in
                if transcriber.isRecording {
                    text = dictationBaseText + newValue
                }
            }
            .onDisappear {
                transcriber.stop()
            }
        }
    }

    // MARK: - Setup

    private func loadInitial() {
        guard !loadedInitial else { return }
        loadedInitial = true
        guard let note else { return }
        text = note.text
        eventDate = note.eventDate
        location = note.location
        drafts = note.sortedPhotos.compactMap { photo in
            // A photo whose bytes haven't synced down from another device yet
            // has nil imageData; skip it rather than showing a broken draft.
            guard let data = photo.imageData else { return nil }
            return DraftPhoto(data: data, caption: photo.caption, existingID: photo.persistentModelID)
        }
    }

    // MARK: - Photos

    private func appendPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let compressed = uiImage.compressedData() {
                    drafts.append(DraftPhoto(data: compressed, caption: ""))
                }
            }
            pickerItems = []
            isLoadingPhotos = false
        }
    }

    // MARK: - Save

    private func save() {
        transcriber.stop()

        let target: NoteEntry
        if let note {
            target = note
        } else {
            let newNote = NoteEntry()
            person.notes.append(newNote)
            target = newNote
        }

        target.text = text.trimmed
        target.eventDate = eventDate
        target.location = location.trimmed

        // Remove photos that were deleted in the editor.
        let existing = target.photos
        let keptIDs = Set(drafts.compactMap(\.existingID))
        for photo in existing where !keptIDs.contains(photo.persistentModelID) {
            context.delete(photo)
        }

        // Update kept photos and add new ones, preserving order.
        for (index, draft) in drafts.enumerated() {
            if let id = draft.existingID {
                if let photo = existing.first(where: { $0.persistentModelID == id }) {
                    photo.caption = draft.caption.trimmed
                    photo.sortOrder = index
                }
            } else {
                let photo = EventPhoto(
                    imageData: draft.data,
                    caption: draft.caption.trimmed,
                    sortOrder: index
                )
                target.photos.append(photo)
            }
        }

        try? context.save()
        dismiss()
    }
}
