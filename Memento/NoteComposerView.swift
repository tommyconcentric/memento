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
                    TipHeader(
                        title: "Event Photos",
                        tip: "Photos are saved with this note's date and location. Use the ⊖ button to remove one."
                    )
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
            // A CloudKit sync from another device can delete the note out
            // from under the editor; don't write into the dead model.
            guard !note.isDeleted else {
                dismiss()
                return
            }
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

        // Reindex everything the note keeps — drafts and the held-out
        // unsynced photos alike. Reindexing only the drafts would leave each
        // unsynced photo's stale sortOrder colliding with a reassigned draft
        // index, scrambling the order once its bytes arrive; instead each
        // unsynced photo is slotted back in at its original relative
        // position. (Drafts can't be reordered, so kept drafts still ascend
        // in the note's original photo order and a straight merge works.)
        let originalRank = Dictionary(
            uniqueKeysWithValues: target.sortedPhotos.enumerated()
                .map { ($1.persistentModelID, $0) }
        )
        var pendingUnsynced = existing
            .filter { unsyncedPhotoIDs.contains($0.persistentModelID) }
            .sorted { (originalRank[$0.persistentModelID] ?? .max) < (originalRank[$1.persistentModelID] ?? .max) }
        var nextOrder = 0
        func placeUnsynced(before rank: Int) {
            while let photo = pendingUnsynced.first,
                  (originalRank[photo.persistentModelID] ?? .max) < rank {
                photo.sortOrder = nextOrder
                nextOrder += 1
                pendingUnsynced.removeFirst()
            }
        }

        // Update kept photos and add new ones, preserving order.
        for draft in drafts {
            if let id = draft.existingID {
                placeUnsynced(before: originalRank[id] ?? .max)
                if let photo = existing.first(where: { $0.persistentModelID == id }) {
                    photo.caption = draft.caption.trimmed
                    photo.sortOrder = nextOrder
                    nextOrder += 1
                }
            } else {
                // Newly added photos land after every photo the note had.
                placeUnsynced(before: .max)
                let photo = EventPhoto(
                    imageData: draft.data,
                    caption: draft.caption.trimmed,
                    sortOrder: nextOrder
                )
                nextOrder += 1
                target.photosArray.append(photo)
            }
        }
        for photo in pendingUnsynced {
            photo.sortOrder = nextOrder
            nextOrder += 1
        }

        try? context.save()
        dismiss()
    }
}
