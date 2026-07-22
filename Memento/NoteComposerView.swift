import SwiftUI
import SwiftData
import PhotosUI

/// Creates a new note entry, or edits an existing one when `note` is set.
struct NoteComposerView: View {
    let person: Person
    let note: NoteEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var text = ""
    @State private var eventDate = Date.now
    @State private var location = ""
    @State private var drafts: [DraftPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    // Count of in-flight picker batches, not a Bool: each selection spawns
    // its own load Task, and a shared Bool would be cleared by whichever
    // batch finished first — re-enabling Save while the other was still
    // loading and silently dropping its photos.
    @State private var photoLoadsInFlight = 0
    @State private var isSaving = false
    @State private var loadedInitial = false
    @State private var transcriber = SpeechTranscriber()
    @State private var dictationBaseText = ""
    // Photos whose bytes haven't synced down from another device yet — kept
    // out of `drafts` (nothing to preview) but must not be treated as
    // user-removed when save() diffs against `drafts`.
    @State private var unsyncedPhotoIDs: Set<PersistentIdentifier> = []

    struct DraftPhoto: Identifiable {
        let id = UUID()
        var data: Data
        var caption: String
        var existingID: PersistentIdentifier? = nil
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty || !text.trimmed.isEmpty || !location.trimmed.isEmpty || !drafts.isEmpty
    }

    private var isLoadingPhotos: Bool { photoLoadsInFlight > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("When & Where") {
                    AppDatePicker(title: "Date", date: $eventDate, business: person.isBusiness)
                    TextField("Location (e.g. Coffee at Marlowe's)", text: $location)
                }

                Section {
                    TextField("Title (optional)", text: $title)
                        .font(.headline)
                    TextField(
                        "What happened? What did you talk about?",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(4...12)
                    // Read-only while dictating: the field is rebuilt from
                    // the live transcript on every partial result, so
                    // anything typed mid-dictation would be silently wiped
                    // by the next one.
                    .disabled(transcriber.isRecording)

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
                            // Click-reachable removal: swipe-to-delete is
                            // the only other affordance, and a Mac mouse
                            // can't perform it.
                            Button(role: .destructive) {
                                drafts.removeAll { $0.id == draft.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Theme.terracotta)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove this photo")
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
                    Text("Photos are saved with this note's date and location. Use the ⊖ button to remove one.")
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
                        .disabled(!canSave || isLoadingPhotos || isSaving)
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
        title = note.title
        text = note.text
        eventDate = note.eventDate
        location = note.location
        drafts = []
        unsyncedPhotoIDs = []
        for photo in note.sortedPhotos {
            // A photo whose bytes haven't synced down from another device yet
            // has nil imageData; skip it rather than showing a broken draft,
            // but remember it so save() doesn't delete it as user-removed.
            guard let data = photo.imageData else {
                unsyncedPhotoIDs.insert(photo.persistentModelID)
                continue
            }
            drafts.append(DraftPhoto(data: data, caption: photo.caption, existingID: photo.persistentModelID))
        }
    }

    // MARK: - Photos

    private func appendPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        // Clear the selection synchronously, before the slow transferable
        // loads — while it stayed populated, reopening the picker mid-load
        // re-offered the same items and a second onChange appended them
        // all again, duplicating every photo. (The clear re-fires onChange
        // with an empty array; the guard above swallows it.)
        pickerItems = []
        photoLoadsInFlight += 1
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let compressed = uiImage.compressedData() {
                    drafts.append(DraftPhoto(data: compressed, caption: ""))
                }
            }
            photoLoadsInFlight -= 1
        }
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        transcriber.stop()

        let target: NoteEntry
        if let note {
            target = note
        } else {
            let newNote = NoteEntry()
            person.notesArray.append(newNote)
            target = newNote
        }

        target.title = title.trimmed
        target.text = text.trimmed
        target.eventDate = eventDate
        target.location = location.trimmed

        // Remove photos that were deleted in the editor (but not photos that
        // simply hadn't synced down yet — those were never shown as drafts).
        let existing = target.photosArray
        let keptIDs = Set(drafts.compactMap(\.existingID)).union(unsyncedPhotoIDs)
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
                target.photosArray.append(photo)
            }
        }

        try? context.save()
        dismiss()
    }
}
