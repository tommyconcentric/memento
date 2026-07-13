import SwiftUI
import SwiftData

struct PersonDetailView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var tab: DetailTab = .quickInfo
    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false

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
                    options: DetailTab.allCases.map { ($0, $0.rawValue) }
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
        .background(Theme.background)
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
                    }
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
        .confirmationDialog(
            "Delete \(person.name)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(person)
                try? context.save()
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
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                if let group = person.group {
                    headerChip(group.name, icon: "folder")
                }
                if person.isDeceased {
                    headerChip("In Memoriam", icon: "leaf")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Theme.aegean, Theme.sky],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 190, height: 190)
                    .offset(x: 130, y: -70)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 130, height: 130)
                    .offset(x: -140, y: 60)
            }
            .saturation(person.isDeceased ? 0 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .shadow(color: Theme.aegean.opacity(person.isDeceased ? 0.12 : 0.28), radius: 14, y: 6)
    }

    private func headerChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.22), in: Capsule())
            .foregroundStyle(.white)
    }
}
