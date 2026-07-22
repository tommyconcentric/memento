import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PersonDetailView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var tab: DetailTab = .quickInfo
    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var pdfExport: PDFExportDocument?
    @State private var showingPDFExporter = false

    enum DetailTab: String, CaseIterable {
        case quickInfo = "Quick Info"
        case family = "Family"
        case notes = "Notes"
    }

    var body: some View {
        Group {
            if person.isDeleted {
                Color.clear
            } else {
                content
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                PillPicker(
                    selection: $tab,
                    options: DetailTab.allCases.map { ($0, $0.rawValue) },
                    accent: person.workspace.accent,
                    fontDesign: person.workspace.displayFontDesign
                )

                switch tab {
                case .quickInfo:
                    QuickInfoView(person: person) { showingEditor = true }
                case .family:
                    PersonFamilySection(person: person) { showingEditor = true }
                case .notes:
                    NotesTimelineView(person: person)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(person.workspace.background)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Person", systemImage: "pencil") {
                        showingEditor = true
                    }
                    Button(
                        person.isDeceased ? "Unmark as Deceased" : "Mark as Deceased",
                        systemImage: "leaf"
                    ) {
                        person.isDeceased.toggle()
                        try? context.save()
                        NotificationManager.refreshFromContext(context)
                        CalendarSyncManager.refreshFromContext(context)
                    }
                    // Business contacts export a crisp report; personal
                    // people a scrapbook — each workspace's voice, in print.
                    Button(
                        person.isBusiness ? "Export Notes Report (PDF)" : "Export Notes Scrapbook (PDF)",
                        systemImage: "square.and.arrow.up"
                    ) {
                        pdfExport = PDFExportDocument(data: NotesPDFExporter.render(for: person))
                        showingPDFExporter = true
                    }
                    .disabled(person.notesArray.isEmpty)
                    Button("Delete Person", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            PersonEditorView(person: person)
        }
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: pdfExport,
            contentType: .pdf,
            defaultFilename: NotesPDFExporter.filename(for: person)
        ) { _ in
            pdfExport = nil
        }
        .confirmationDialog(
            "Delete \(person.name)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(person)
                try? context.save()
                NotificationManager.refreshFromContext(context)
                CalendarSyncManager.refreshFromContext(context)
                dismiss()
            }
        } message: {
            Text("All notes and photos for this person will be deleted too.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(
                data: person.profilePhotoData,
                name: person.name,
                size: 104,
                desaturated: person.isDeceased
            )
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(person.name)
                .font(.system(.title2, design: person.workspace.displayFontDesign, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                if person.isBusiness {
                    headerChip("Business", icon: "briefcase")
                }
                if let group = person.group {
                    headerChip(group.name, icon: "folder")
                }
                if person.isDeceased {
                    headerChip("In Memoriam", icon: "leaf")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background {
            ZStack {
                // Boardroom slate for business contacts, holiday blues for
                // everyone else.
                LinearGradient(
                    colors: person.isBusiness
                        ? [Color(red: 0.13, green: 0.17, blue: 0.23), Theme.steel]
                        : [Color(red: 0.09, green: 0.34, blue: 0.49), Theme.sky],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .inset(by: 10)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .saturation(person.isDeceased ? 0 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }

    private func headerChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(.white)
    }
}
