import SwiftUI
import SwiftData

/// The person's running notes: newest first, each entry with date,
/// location and event photos.
struct NotesTimelineView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @State private var showingComposer = false
    @State private var noteBeingEdited: NoteEntry?
    @State private var noteBeingRead: NoteEntry?
    @State private var viewerPhoto: EventPhoto?
    // Deleting a note asks first — it permanently destroys the entry and
    // its photos, and the menu item sits one slip below "Edit Note".
    @State private var notePendingDelete: NoteEntry?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Button {
                showingComposer = true
            } label: {
                Label("Add a Note", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if person.notesArray.isEmpty {
                ContentUnavailableView {
                    Label("No Notes Yet", systemImage: "text.book.closed")
                } description: {
                    Text("After you meet, jot down what you talked about and add photos with the date and place.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            } else {
                ForEach(person.sortedNotes) { note in
                    NoteCard(
                        note: note,
                        onPhotoTap: { viewerPhoto = $0 },
                        onOpen: { noteBeingRead = note },
                        onEdit: { noteBeingEdited = note },
                        onDelete: { notePendingDelete = note }
                    )
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            NoteComposerView(person: person, note: nil)
        }
        .sheet(item: $noteBeingEdited) { note in
            NoteComposerView(person: person, note: note)
        }
        .sheet(item: $noteBeingRead) { note in
            NoteDetailSheet(note: note) {
                noteBeingRead = nil
                noteBeingEdited = note
            }
        }
        .sheet(item: $viewerPhoto) { photo in
            PhotoViewerSheet(photo: photo)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { notePendingDelete != nil },
                set: { if !$0 { notePendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: notePendingDelete
        ) { note in
            Button("Delete", role: .destructive) { delete(note) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The note and its photos will be deleted.")
        }
    }

    private func delete(_ note: NoteEntry) {
        context.delete(note)
        try? context.save()
    }
}

// MARK: - Note card

struct NoteCard: View {
    let note: NoteEntry
    var onPhotoTap: (EventPhoto) -> Void
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    note.eventDate.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
                if !note.location.isEmpty {
                    Label(note.location, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Edit Note", systemImage: "pencil", action: onEdit)
                    Button("Delete Note", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(.vertical, 4)
                        .padding(.leading, 8)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !note.title.isEmpty {
                Text(note.title)
                    .font(.headline)
            }

            if !note.text.isEmpty {
                // The timeline shows a preview; the full note lives one
                // tap away in the reading sheet.
                Text(note.text)
                    .font(.body)
                    .lineLimit(5)
            }

            if !note.photosArray.isEmpty {
                photoGrid
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .mementoCard()
        .contextMenu {
            Button("Edit Note", systemImage: "pencil", action: onEdit)
            Button("Delete Note", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(note.sortedPhotos) { photo in
                Button {
                    onPhotoTap(photo)
                } label: {
                    VStack(spacing: 4) {
                        if let data = photo.imageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        if !photo.caption.isEmpty {
                            Text(photo.caption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Note reading sheet

/// The full note, opened by tapping its card in the timeline — title,
/// date, place, complete text and photos without the preview truncation.
struct NoteDetailSheet: View {
    let note: NoteEntry
    var onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewerPhoto: EventPhoto?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.system(.title2, design: .serif).weight(.semibold))
                    }

                    HStack(spacing: 12) {
                        Label(
                            note.eventDate.formatted(date: .long, time: .omitted),
                            systemImage: "calendar"
                        )
                        if !note.location.isEmpty {
                            Label(note.location, systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if !note.text.isEmpty {
                        Text(note.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    if !note.photosArray.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            ForEach(note.sortedPhotos) { photo in
                                Button {
                                    viewerPhoto = photo
                                } label: {
                                    VStack(spacing: 4) {
                                        if let data = photo.imageData, let uiImage = UIImage(data: data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        if !photo.caption.isEmpty {
                                            Text(photo.caption)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit", action: onEdit)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $viewerPhoto) { photo in
                PhotoViewerSheet(photo: photo)
            }
        }
    }
}

// MARK: - Full-screen photo viewer

struct PhotoViewerSheet: View {
    let photo: EventPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let data = photo.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(spacing: 4) {
                    if !photo.caption.isEmpty {
                        Text(photo.caption)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    if let note = photo.note {
                        let detail = [
                            note.eventDate.formatted(date: .long, time: .omitted),
                            note.location
                        ]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
