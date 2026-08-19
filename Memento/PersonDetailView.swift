import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PersonDetailView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var tab: DetailTab = .quickInfo
    @State private var showingEditor = false
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
        // Set here, not at any single presentation site: this screen is
        // reachable from the sidebar, the ladder, and family-tab links,
        // and its cards must wear the person's workspace surfaces on
        // every route.
        .environment(\.cardWorkspace, person.workspace)
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
                    // The export earns its place only once there's something
                    // to print; business contacts get a crisp report,
                    // personal people a scrapbook.
                    if !person.notesArray.isEmpty {
                        Button {
                            pdfExport = PDFExportDocument(data: NotesPDFExporter.render(for: person))
                            showingPDFExporter = true
                        } label: {
                            Label(
                                person.isBusiness ? "Export Notes Report (PDF)" : "Export Notes Scrapbook (PDF)",
                                systemImage: "square.and.arrow.up"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(person.workspace.accent)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(person.workspace.background)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        // A pencil straight to the editor. The old ⋯ menu's other actions
        // moved to where they're used: PDF export to the foot of the Notes
        // tab, deletion (and deceased) to the foot of the editor.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Person", systemImage: "pencil") {
                    showingEditor = true
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
    }

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(
                data: person.profilePhotoData,
                name: person.name,
                size: 104,
                desaturated: person.isDeceased,
                business: person.isBusiness
            )
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            .overlay(alignment: .topTrailing) {
                if person.isYourPartner {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.terracotta)
                        .padding(5)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("Your partner")
                }
            }
            // Change the photo right here, with no detour through Edit Person.
            // Bottom corner (iOS's photo-edit spot); the heart owns the top.
            .overlay(alignment: .bottomTrailing) {
                ProfilePhotoEditButton(person: person)
                    .offset(x: 2, y: 2)
            }

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
