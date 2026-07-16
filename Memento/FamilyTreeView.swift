import SwiftUI
import SwiftData

// MARK: - Relationship vocabulary

/// Preset relationship labels and the generation math that turns them
/// into an auto-generated family tree.
enum FamilyRelation {
    static let presets: [String] = [
        "Mother", "Father", "Parent", "Stepmother", "Stepfather",
        "Grandmother", "Grandfather", "Grandparent",
        "Wife", "Husband", "Fiancée", "Fiancé", "Partner", "Girlfriend", "Boyfriend",
        "Sister", "Brother", "Sibling", "Stepsister", "Stepbrother", "Cousin",
        "Aunt", "Uncle", "Aunt/Uncle",
        "Daughter", "Son", "Child", "Stepdaughter", "Stepson",
        "Niece", "Nephew", "Niece/Nephew",
        "Granddaughter", "Grandson", "Grandchild",
        "Mother-in-law", "Father-in-law", "Parent-in-law",
        "Sister-in-law", "Brother-in-law", "Sibling-in-law",
        "Daughter-in-law", "Son-in-law", "Child-in-law",
        // Less common relations, kept at the bottom of the picker.
        "Half-sister", "Half-brother", "Half-sibling",
        "Great-grandmother", "Great-grandfather", "Great-grandparent",
        "Great-granddaughter", "Great-grandson", "Great-grandchild",
        "Godmother", "Godfather", "Goddaughter", "Godson",
        "Ex-wife", "Ex-husband", "Ex-girlfriend", "Ex-boyfriend", "Ex-partner"
    ]

    /// Generation offset relative to the tree's focus person.
    static func generation(of label: String) -> Int {
        let l = label.lowercased()
        if l.contains("great-grand") || l.contains("great grand") {
            return (l.contains("daughter") || l.contains("son") || l.contains("child")) ? -3 : 3
        }
        if l.contains("grandmother") || l.contains("grandfather") || l.contains("grandparent")
            || l.contains("grandma") || l.contains("grandpa") {
            return 2
        }
        if l.contains("granddaughter") || l.contains("grandson") || l.contains("grandchild") {
            return -2
        }
        if l.contains("mother") || l.contains("father") || l.contains("parent")
            || l.contains("mom") || l.contains("mum") || l.contains("dad")
            || l.contains("aunt") || l.contains("uncle") {
            return 1
        }
        if l.contains("daughter") || l.contains("son") || l.contains("child")
            || l.contains("niece") || l.contains("nephew") {
            return -1
        }
        return 0
    }

    /// Labels that belong to a generation lane (for the drag-to-move chooser).
    static func labels(forGeneration generation: Int) -> [String] {
        let matching = presets.filter { Self.generation(of: $0) == generation }
        return matching.isEmpty ? ["Family"] : matching
    }

    static func rowTitle(for generation: Int, subject: String) -> String {
        switch generation {
        case 3...: return "Great-grandparents"
        case 2: return "Grandparents"
        case 1: return "Parents, aunts & uncles"
        case 0: return "\(subject) & their generation"
        case -1: return "Children, nieces & nephews"
        case -2: return "Grandchildren"
        default: return "Great-grandchildren"
        }
    }
}

// MARK: - Tree data

struct TreeNode: Identifiable {
    let id = UUID()
    let name: String
    let relation: String
    let photoData: Data?
    let linkedPerson: Person?
    let isDeceased: Bool
    let isFocus: Bool
    let generation: Int
}

struct TreeRow: Identifiable {
    let id: Int          // the generation
    let title: String
    let nodes: [TreeNode]
}

func buildTreeRows(nodes: [TreeNode], subjectTitle: String, ensureGenerations: Set<Int> = []) -> [TreeRow] {
    var byGeneration: [Int: [TreeNode]] = [:]
    for generation in ensureGenerations { byGeneration[generation] = [] }
    for node in nodes {
        byGeneration[node.generation, default: []].append(node)
    }
    return byGeneration.keys.sorted(by: >).map { generation in
        let sorted = byGeneration[generation, default: []].sorted {
            ($0.isFocus ? 0 : 1, $0.name) < ($1.isFocus ? 0 : 1, $1.name)
        }
        return TreeRow(
            id: generation,
            title: generation == 0 && subjectTitle == "You"
                ? "You & your generation"
                : FamilyRelation.rowTitle(for: generation, subject: subjectTitle),
            nodes: sorted
        )
    }
}

// MARK: - Tree rendering

/// Generation rows joined by a spine — designed to live inside a ScrollView.
/// When `onDropInGeneration` is set, people can be held and dragged between
/// rows; the handler receives the dropped person's name and the target row.
struct FamilyTreeContent: View {
    let rows: [TreeRow]
    var dragEnabled = false
    var onDropInGeneration: ((String, Int) -> Void)? = nil

    @State private var targetedGeneration: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                laneContainer(row)
                if row.id != rows.last?.id {
                    generationJoin
                }
            }
        }
    }

    /// The descent line between generations, drawn like the inked joins on
    /// an old genealogical chart: a fine rule with a small gilt ornament.
    private var generationJoin: some View {
        VStack(spacing: 3) {
            Rectangle()
                .fill(Theme.bark.opacity(0.5))
                .frame(width: 1, height: 7)
            Image(systemName: "suit.diamond.fill")
                .font(.system(size: 7))
                .foregroundStyle(Theme.gold.opacity(0.85))
            Rectangle()
                .fill(Theme.bark.opacity(0.5))
                .frame(width: 1, height: 7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func laneContainer(_ row: TreeRow) -> some View {
        if let onDropInGeneration {
            lane(row)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.aegean.opacity(targetedGeneration == row.id ? 0.6 : 0), lineWidth: 2)
                )
                .dropDestination(for: String.self) { items, _ in
                    if let name = items.first { onDropInGeneration(name, row.id) }
                    return true
                } isTargeted: { isOver in
                    targetedGeneration = isOver ? row.id : nil
                }
        } else {
            lane(row)
        }
    }

    private func lane(_ row: TreeRow) -> some View {
        VStack(alignment: .center, spacing: 8) {
            laneTitle(row.title)
            if row.nodes.isEmpty {
                Text(dragEnabled ? "Hold a person and drag them here" : " ")
                    .font(.system(.caption2, design: .serif).italic())
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(row.nodes) { node in
                            FamilyNodeView(
                                node: node,
                                dragPayload: (dragEnabled && !node.isFocus) ? node.name : nil
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(laneTint(row.id), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.vertical, 1)
    }

    /// Engraved-plate generation caption: letterspaced serif small caps
    /// between two fine rules, the way old charts label each rank.
    private func laneTitle(_ title: String) -> some View {
        HStack(spacing: 8) {
            titleRule
            Text(title)
                .font(.system(.caption2, design: .serif).weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(Theme.bark.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
            titleRule
        }
    }

    private var titleRule: some View {
        Rectangle()
            .fill(Theme.bark.opacity(0.3))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    /// Parchment bands: ancestors fade lighter toward the top of the
    /// chart, descendants deepen toward the earth at the bottom.
    private func laneTint(_ generation: Int) -> Color {
        if generation >= 1 { return Theme.gold.opacity(generation >= 2 ? 0.13 : 0.10) }
        if generation == 0 { return Theme.gold.opacity(0.06) }
        return Theme.bark.opacity(generation <= -2 ? 0.12 : 0.08)
    }
}

struct FamilyNodeView: View {
    let node: TreeNode
    var dragPayload: String? = nil

    var body: some View {
        if let person = node.linkedPerson {
            draggableWrapper(
                NavigationLink {
                    PersonDetailView(person: person)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        } else {
            draggableWrapper(content)
        }
    }

    @ViewBuilder
    private func draggableWrapper<V: View>(_ view: V) -> some View {
        if let dragPayload {
            view.draggable(dragPayload)
        } else {
            view
        }
    }

    private var content: some View {
        VStack(spacing: 4) {
            // Gilt portrait frame: a gold ring around the sitter with a
            // fine bark rule floating just outside it, like the framed
            // ovals on a Victorian genealogy chart.
            AvatarView(
                data: node.photoData,
                name: node.name,
                size: node.isFocus ? 62 : 52,
                desaturated: node.isDeceased
            )
            .overlay {
                Circle().stroke(
                    node.isFocus ? Theme.gold : Theme.gold.opacity(0.55),
                    lineWidth: node.isFocus ? 2.5 : 1.5
                )
            }
            .overlay {
                Circle()
                    .stroke(Theme.bark.opacity(node.isFocus ? 0.6 : 0.35), lineWidth: 0.5)
                    .padding(-3)
            }
            .padding(3)
            Text(node.name)
                .font(.system(.caption, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !node.relation.isEmpty {
                Text(node.relation)
                    .font(.system(.caption2, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 88)
    }
}

// MARK: - My family tree (auto-generated, drag to re-place people)

struct MyFamilyTreeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]

    struct MoveRequest: Identifiable {
        let id = UUID()
        let person: Person
        let generation: Int
    }
    @State private var pendingMove: MoveRequest?

    private var labeled: [Person] {
        people.filter { !$0.relationshipToUser.trimmed.isEmpty }
    }

    private var rows: [TreeRow] {
        var nodes = labeled.map { person in
            TreeNode(
                name: person.name,
                relation: person.relationshipToUser,
                photoData: person.profilePhotoData,
                linkedPerson: person,
                isDeceased: person.isDeceased,
                isFocus: false,
                generation: FamilyRelation.generation(of: person.relationshipToUser)
            )
        }
        nodes.append(TreeNode(
            name: "You", relation: "", photoData: nil,
            linkedPerson: nil, isDeceased: false, isFocus: true, generation: 0
        ))
        return buildTreeRows(nodes: nodes, subjectTitle: "You", ensureGenerations: [-2, -1, 0, 1, 2])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if labeled.isEmpty {
                    ContentUnavailableView {
                        Label("No Tree Yet", systemImage: "tree")
                    } description: {
                        Text("Set \"Family Relationship to You\" on your relatives in Edit Person — mother, brother, grandson — and your tree grows itself. Friends and colleagues can be left unset.")
                    }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tap anyone to open their profile. Hold a person and drag them to another row to change how you're related.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        FamilyTreeContent(rows: rows, dragEnabled: true) { name, generation in
                            handleDrop(name: name, generation: generation)
                        }
                        .historicalTreePlate()
                        .mementoCard(padding: 10)
                    }
                    .padding()
                }
            }
            .background(Theme.background)
            .navigationTitle("My Family Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingMove.map { move in
                    "Move \(move.person.name) to \(FamilyRelation.rowTitle(for: move.generation, subject: "You").lowercased())?"
                } ?? "",
                isPresented: Binding(
                    get: { pendingMove != nil },
                    set: { if !$0 { pendingMove = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingMove
            ) { move in
                ForEach(FamilyRelation.labels(forGeneration: move.generation), id: \.self) { label in
                    Button(label) { apply(label: label, to: move.person) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { move in
                Text("They're currently your \(move.person.relationshipToUser.lowercased()). Nothing changes until you pick their new relationship — only ones that belong in that row are offered.")
            }
        }
    }

    private func handleDrop(name: String, generation: Int) {
        guard let person = people.first(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) else { return }
        guard FamilyRelation.generation(of: person.relationshipToUser) != generation else { return }
        pendingMove = MoveRequest(person: person, generation: generation)
    }

    private func apply(label: String, to person: Person) {
        person.relationshipToUser = label
        try? context.save()
        pendingMove = nil
    }
}

// MARK: - A person's own family tree (shown on their Family tab)

struct PersonFamilySection: View {
    let person: Person
    var onEdit: () -> Void

    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]

    private var nodes: [TreeNode] {
        var result: [TreeNode] = [
            TreeNode(
                name: person.name,
                relation: "",
                photoData: person.profilePhotoData,
                linkedPerson: nil,
                isDeceased: person.isDeceased,
                isFocus: true,
                generation: 0
            )
        ]

        if !person.partnerName.trimmed.isEmpty {
            result.append(node(named: person.partnerName, relation: "Partner"))
        }
        for child in childNames(of: person) {
            result.append(node(named: child, relation: "Child"))
        }
        for member in person.familyMembersArray where !member.name.trimmed.isEmpty {
            result.append(node(named: member.name, relation: member.relation))
        }
        return result
    }

    private func node(named rawName: String, relation: String) -> TreeNode {
        let name = rawName.trimmed
        let match = people.first {
            $0.persistentModelID != person.persistentModelID &&
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        return TreeNode(
            name: name,
            relation: relation,
            photoData: match?.profilePhotoData,
            linkedPerson: match,
            isDeceased: match?.isDeceased ?? false,
            isFocus: false,
            generation: FamilyRelation.generation(of: relation)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            if !person.relationshipToUser.trimmed.isEmpty {
                Label("Your \(person.relationshipToUser.lowercased())", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.bougainvillea)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.bougainvillea.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if let path = RelationshipPath.description(to: person, people: people) {
                Label(path, systemImage: "arrow.triangle.branch")
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
            }

            if nodes.count <= 1 {
                ContentUnavailableView {
                    Label("No Family Recorded", systemImage: "tree")
                } description: {
                    Text("Add a partner, children or named family members and their tree appears here automatically.")
                } actions: {
                    Button("Add Family Details", action: onEdit)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            } else {
                FamilyTreeContent(rows: buildTreeRows(nodes: nodes, subjectTitle: person.name))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .historicalTreePlate()
                    .mementoCard(padding: 10)

                Button(action: onEdit) {
                    Label("Edit Family", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Names split out of the free-text children field.
func childNames(of person: Person) -> [String] {
    let separators = CharacterSet(charactersIn: ",&\n")
    return person.childrenNames
        .replacingOccurrences(of: " and ", with: ",")
        .components(separatedBy: separators)
        .map { $0.trimmed }
        .filter { !$0.isEmpty }
}


/// Shared backdrop for tree cards: aged parchment, faded at the top of the
/// chart and warming toward the earth at the bottom.
private var treeParchmentGradient: LinearGradient {
    LinearGradient(
        colors: [Theme.gold.opacity(0.08), Theme.bark.opacity(0.12)],
        startPoint: .top, endPoint: .bottom
    )
}

/// Dresses a tree in its historical-chart plate: parchment fill plus the
/// fine inner rule that gives engraved certificates their double border.
private struct HistoricalPlate: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(treeParchmentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.bark.opacity(0.28), lineWidth: 0.5)
                    .padding(4)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func historicalTreePlate() -> some View { modifier(HistoricalPlate()) }
}
