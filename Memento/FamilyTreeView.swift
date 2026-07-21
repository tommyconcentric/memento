import SwiftUI
import SwiftData

// MARK: - Relationship vocabulary

/// Preset relationship labels and the generation math that turns them
/// into an auto-generated family tree.
enum FamilyRelation {
    static let presets: [String] = [
        "Mother", "Father", "Parent",
        "Stepmother", "Stepfather", "Stepparent",
        "Grandmother", "Grandfather", "Grandparent",
        "Wife", "Husband", "Fiancée", "Fiancé", "Partner", "Girlfriend", "Boyfriend",
        "Sister", "Brother", "Sibling",
        "Stepsister", "Stepbrother", "Stepsibling",
        "Half-sister", "Half-brother", "Half-sibling",
        "Cousin",
        "Aunt", "Uncle", "Aunt/Uncle",
        "Daughter", "Son", "Child",
        "Stepdaughter", "Stepson", "Stepchild",
        "Niece", "Nephew", "Niece/Nephew",
        "Granddaughter", "Grandson", "Grandchild",
        "Mother-in-law", "Father-in-law", "Parent-in-law",
        "Sister-in-law", "Brother-in-law", "Sibling-in-law",
        "Daughter-in-law", "Son-in-law", "Child-in-law",
        // Adopted and foster relations — same generations as the blood
        // relatives they mirror, so the tree places them correctly.
        "Adoptive mother", "Adoptive father", "Adoptive parent",
        "Adopted daughter", "Adopted son", "Adopted child",
        "Foster mother", "Foster father", "Foster parent",
        "Foster daughter", "Foster son", "Foster child",
        // Less common relations, kept toward the bottom of the picker.
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

    /// Only preset relations earn a place on the family tree. Custom
    /// "Other…" relationships stay off the chart by design — and keyword
    /// sniffing is no substitute, since a custom label like "childhood
    /// neighbour" would substring-match "child" straight into the
    /// children's lane. Nothing but the editor's preset picker has ever
    /// written this field, so exact matching loses no legacy data.
    static func isChartable(_ label: String) -> Bool {
        presets.contains { $0.compare(label, options: .caseInsensitive) == .orderedSame }
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

// MARK: - Business relationship vocabulary

/// The Business workspace counterpart of `FamilyRelation`: working
/// relationships and the ladder-level math that turns them into a
/// corporate ladder (who reports to whom) instead of a family tree.
enum BusinessRelation {
    static let presets: [String] = [
        "Colleague", "Teammate", "Manager", "Direct report",
        "Client", "Customer", "Business partner", "Collaborator",
        "Networking contact", "Mentor", "Mentee", "Advisor",
        "Investor", "Supplier", "Recruiter", "Former colleague"
    ]

    /// Ladder level relative to you: people you answer to sit above,
    /// people who answer to you sit below, and everyone you work
    /// alongside — colleagues, clients, collaborators — shares your rung.
    static func level(of label: String) -> Int {
        let l = label.lowercased()
        if l.contains("mentee") || l.contains("report") || l.contains("intern")
            || l.contains("apprentice") {
            return -1
        }
        if l.contains("manager") || l.contains("mentor") || l.contains("advisor")
            || l.contains("investor") || l.contains("boss") {
            return 1
        }
        return 0
    }

    /// Only preset working relationships climb the ladder — custom
    /// "Other…" labels describe the relationship without charting it.
    static func isChartable(_ label: String) -> Bool {
        presets.contains { $0.compare(label, options: .caseInsensitive) == .orderedSame }
    }

    /// Labels that belong to a ladder level (for the drag-to-move chooser).
    static func labels(forLevel level: Int) -> [String] {
        let matching = presets.filter { Self.level(of: $0) == level }
        return matching.isEmpty ? ["Colleague"] : matching
    }

    static func rowTitle(for level: Int) -> String {
        switch level {
        case 1...: return "Managers, mentors & advisors"
        case 0: return "You & the people you work with"
        default: return "Reports & mentees"
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

func buildTreeRows(nodes: [TreeNode], subjectTitle: String, ensureGenerations: Set<Int> = [],
                   titleFor: ((Int) -> String)? = nil) -> [TreeRow] {
    var byGeneration: [Int: [TreeNode]] = [:]
    for generation in ensureGenerations { byGeneration[generation] = [] }
    for node in nodes {
        byGeneration[node.generation, default: []].append(node)
    }
    return byGeneration.keys.sorted(by: >).map { generation in
        let sorted = byGeneration[generation, default: []].sorted {
            ($0.isFocus ? 0 : 1, $0.name) < ($1.isFocus ? 0 : 1, $1.name)
        }
        let title: String
        if let titleFor {
            title = titleFor(generation)
        } else if generation == 0 && subjectTitle == "You" {
            title = "You & your generation"
        } else {
            title = FamilyRelation.rowTitle(for: generation, subject: subjectTitle)
        }
        return TreeRow(id: generation, title: title, nodes: sorted)
    }
}

// MARK: - Tree rendering

/// Generation rows joined by a spine — designed to live inside a ScrollView.
/// When `onDropInGeneration` is set, people can be held and dragged between
/// rows; the handler receives the dropped person's name and the target row.
private struct LaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A node's laid-out frame, tagged with its generation, so the chart can
/// draw genealogy-style connectors between one generation and the next.
struct NodeAnchor: Equatable {
    let generation: Int
    let bounds: Anchor<CGRect>
}

private struct NodeAnchorKey: PreferenceKey {
    static var defaultValue: [NodeAnchor] = []
    static func reduce(value: inout [NodeAnchor], nextValue: () -> [NodeAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

struct FamilyTreeContent: View {
    let rows: [TreeRow]
    var dragEnabled = false
    /// Corporate dressing for the Business ladder: slate lanes and steel
    /// rules in place of the genealogy chart's parchment and gilt.
    var corporate = false
    var onDropInGeneration: ((String, Int) -> Void)? = nil

    @State private var targetedGeneration: Int? = nil
    // Width of the chart, so a lane with only a person or two can centre
    // them across it instead of leaving them pinned to the left edge.
    @State private var laneWidth: CGFloat = 0

    private var ruleColor: Color { corporate ? Theme.graphite : Theme.bark }
    // Total horizontal inset the lane adds around its scroll area; the
    // node row fills the chart width minus this so centring lines up.
    private let laneHorizontalPadding: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                laneContainer(row)
                if row.id != rows.last?.id {
                    generationJoin
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: LaneWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(LaneWidthKey.self) { laneWidth = $0 }
        // Genealogy-chart connectors: each generation hangs from a
        // horizontal bar joined by a vertical drop-line to the one below,
        // the way a family tree links parents to their offspring. Drawn as
        // an overlay so the lines sit above the lane tints, but every
        // segment lives in the gap between rows, never over a portrait.
        .overlayPreferenceValue(NodeAnchorKey.self) { anchors in
            GeometryReader { proxy in
                connectorPath(anchors, in: proxy)
                    .stroke(
                        ruleColor.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
            }
            .allowsHitTesting(false)
        }
    }

    /// Clear breathing room between generations; the actual descent lines
    /// are drawn across this gap by the connector overlay.
    private var generationJoin: some View {
        Color.clear.frame(height: 26)
    }

    /// Builds the family-tree connectors between adjacent populated
    /// generations: a short vertical from the bottom of every person in the
    /// upper row and from the top of every person in the lower row, joined
    /// by one horizontal bar running along the midline of the gap.
    private func connectorPath(_ anchors: [NodeAnchor], in proxy: GeometryProxy) -> Path {
        var byGeneration: [Int: [CGRect]] = [:]
        for anchor in anchors {
            byGeneration[anchor.generation, default: []].append(proxy[anchor.bounds])
        }
        // Only generations that actually hold people; link each to the next
        // populated one below (empty lanes are skipped, not spanned to).
        let generations = byGeneration.keys.sorted(by: >)
        var path = Path()
        for index in generations.indices.dropLast() {
            guard let upper = byGeneration[generations[index]],
                  let lower = byGeneration[generations[index + 1]],
                  let upperBottom = upper.map({ $0.maxY }).max(),
                  let lowerTop = lower.map({ $0.minY }).min() else { continue }
            let midY = (upperBottom + lowerTop) / 2
            for rect in upper {
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: midY))
            }
            for rect in lower {
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: midY))
            }
            let centers = (upper + lower).map { $0.midX }
            if let minX = centers.min(), let maxX = centers.max(), minX < maxX {
                path.move(to: CGPoint(x: minX, y: midY))
                path.addLine(to: CGPoint(x: maxX, y: midY))
            }
        }
        return path
    }

    @ViewBuilder
    private func laneContainer(_ row: TreeRow) -> some View {
        if let onDropInGeneration {
            lane(row)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder((corporate ? Theme.steel : Theme.aegean).opacity(targetedGeneration == row.id ? 0.6 : 0), lineWidth: 2)
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
                // A crowded generation overflows its lane sideways; the
                // visible indicator is what makes that scrollable at all
                // with a mouse on the Mac, where there's no swipe.
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
                        ForEach(row.nodes) { node in
                            FamilyNodeView(
                                node: node,
                                dragPayload: (dragEnabled && !node.isFocus) ? node.name : nil,
                                corporate: corporate
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    // Fill the chart width so a sparse generation centres;
                    // a crowded one exceeds it and the ScrollView takes over.
                    // (maxWidth: .infinity is inert inside a horizontal
                    // ScrollView, which sizes content to its natural width.)
                    .frame(minWidth: max(0, laneWidth - laneHorizontalPadding), alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(laneTint(row.id), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.vertical, 1)
    }

    /// Engraved generation caption, pinned to the lane's leading edge so the
    /// vertical centre stays clear for the family-tree connector lines.
    private func laneTitle(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(.caption2, design: corporate ? .default : .serif).weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(ruleColor.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    /// Parchment bands: ancestors fade lighter toward the top of the
    /// chart, descendants deepen toward the earth at the bottom.
    private func laneTint(_ generation: Int) -> Color {
        if corporate {
            if generation >= 1 { return Theme.steel.opacity(0.16) }
            if generation == 0 { return Theme.steel.opacity(0.08) }
            return Theme.graphite.opacity(0.10)
        }
        if generation >= 1 { return Theme.gold.opacity(generation >= 2 ? 0.13 : 0.10) }
        if generation == 0 { return Theme.gold.opacity(0.06) }
        return Theme.bark.opacity(generation <= -2 ? 0.12 : 0.08)
    }
}

struct FamilyNodeView: View {
    let node: TreeNode
    var dragPayload: String? = nil
    var corporate = false

    private var ringColor: Color { corporate ? Theme.steel : Theme.gold }
    private var frameColor: Color { corporate ? Theme.graphite : Theme.bark }

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
                    node.isFocus ? ringColor : ringColor.opacity(0.55),
                    lineWidth: node.isFocus ? 2.5 : 1.5
                )
            }
            .overlay {
                Circle()
                    .stroke(frameColor.opacity(node.isFocus ? 0.6 : 0.35), lineWidth: 0.5)
                    .padding(-3)
            }
            .padding(3)
            Text(node.name)
                .font(.system(.caption, design: corporate ? .default : .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !node.relation.isEmpty {
                Text(node.relation)
                    .font(.system(.caption2, design: corporate ? .default : .serif).italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 88)
        // Report this node's frame so the chart can route connector lines
        // from the bottom of each parent's row to the top of each child's.
        .anchorPreference(key: NodeAnchorKey.self, value: .bounds) {
            [NodeAnchor(generation: node.generation, bounds: $0)]
        }
    }
}

// MARK: - My family tree (auto-generated, drag to re-place people)

struct MyFamilyTreeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]
    @AppStorage(Workspace.storageKey) private var storedWorkspace = Workspace.personal.rawValue

    struct MoveRequest: Identifiable {
        let id = UUID()
        let person: Person
        let generation: Int
    }
    @State private var pendingMove: MoveRequest?
    @State private var showingSelfLinks = false

    private var workspace: Workspace {
        Workspace(rawValue: storedWorkspace) ?? .personal
    }

    /// In Business the same sheet renders a corporate ladder: business
    /// contacts placed by working relationship (who reports to whom)
    /// instead of relatives placed by generation.
    private var isLadder: Bool { workspace == .business }

    private var labeled: [Person] {
        people.filter {
            let label = $0.relationshipToUser.trimmed
            guard !label.isEmpty, $0.isBusiness == isLadder else { return false }
            // Custom "Other…" relationships describe someone without
            // placing them on the chart.
            return isLadder ? BusinessRelation.isChartable(label) : FamilyRelation.isChartable(label)
        }
    }

    private func placement(of label: String) -> Int {
        isLadder ? BusinessRelation.level(of: label) : FamilyRelation.generation(of: label)
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
                generation: placement(of: person.relationshipToUser)
            )
        }
        nodes.append(TreeNode(
            name: "You", relation: "", photoData: nil,
            linkedPerson: nil, isDeceased: false, isFocus: true, generation: 0
        ))
        return buildTreeRows(
            nodes: nodes,
            subjectTitle: "You",
            ensureGenerations: isLadder ? [-1, 0, 1] : [-2, -1, 0, 1, 2],
            titleFor: isLadder ? { BusinessRelation.rowTitle(for: $0) } : nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if labeled.isEmpty {
                    ContentUnavailableView {
                        Label(
                            isLadder ? "No Ladder Yet" : "No Tree Yet",
                            systemImage: isLadder ? "building.2" : "tree"
                        )
                    } description: {
                        Text(isLadder
                            ? "Set \"Working Relationship to You\" on your business contacts in Edit Person — manager, client, direct report — and your corporate ladder builds itself."
                            : "Set \"Family Relationship to You\" on your relatives in Edit Person — mother, brother, grandson — and your tree grows itself. Friends and colleagues can be left unset.")
                    }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isLadder
                            ? "Tap anyone to open their profile. Hold a person and drag them to another rung to change how you work together."
                            : "Tap anyone to open their profile. Hold a person and drag them to another row to change how you're related.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        FamilyTreeContent(rows: rows, dragEnabled: true, corporate: isLadder) { name, generation in
                            handleDrop(name: name, generation: generation)
                        }
                        .historicalTreePlate(corporate: isLadder)
                        .mementoCard(padding: 10)
                    }
                    .padding()
                }
            }
            .background(workspace.background)
            .navigationTitle(isLadder ? "Corporate Ladder" : "My Family Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isLadder {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Edit") { showingSelfLinks = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSelfLinks) {
                if let selfNode = people.first(where: { $0.isSelf }) {
                    FamilyLinksEditor(subject: selfNode)
                }
            }
            .confirmationDialog(
                pendingMove.map { move in
                    "Move \(move.person.name) to \(destinationName(for: move.generation))?"
                } ?? "",
                isPresented: Binding(
                    get: { pendingMove != nil },
                    set: { if !$0 { pendingMove = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingMove
            ) { move in
                let choices = isLadder
                    ? BusinessRelation.labels(forLevel: move.generation)
                    : FamilyRelation.labels(forGeneration: move.generation)
                ForEach(choices, id: \.self) { label in
                    Button(label) { apply(label: label, to: move.person) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { move in
                Text("They're currently your \(move.person.relationshipToUser.lowercased()). Nothing changes until you pick their new relationship — only ones that belong in that \(isLadder ? "rung" : "row") are offered.")
            }
        }
    }

    /// The lane name as the dialog should say it — the generation-0 lane is
    /// labeled "You & your generation", not rowTitle's "You & their
    /// generation".
    private func destinationName(for generation: Int) -> String {
        if isLadder {
            return generation == 0 ? "your rung" : BusinessRelation.rowTitle(for: generation).lowercased()
        }
        return generation == 0
            ? "your generation"
            : FamilyRelation.rowTitle(for: generation, subject: "You").lowercased()
    }

    private func handleDrop(name: String, generation: Int) {
        // The drag payload is a display name, so resolve it only among the
        // people this tree actually renders, and refuse ambiguous duplicates
        // — same convention as applyReciprocalLinks; guessing risks
        // rewriting the relationship of the wrong person.
        let matches = labeled.filter {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        guard matches.count == 1, let person = matches.first else { return }
        guard placement(of: person.relationshipToUser) != generation else { return }
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
    @State private var showingLinks = false

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

            Button { showingLinks = true } label: {
                Label("Edit Family Links", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $showingLinks) {
            FamilyLinksEditor(subject: person)
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
    var corporate = false

    func body(content: Content) -> some View {
        content
            .background(
                corporate ? corporateSlateGradient : treeParchmentGradient,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder((corporate ? Theme.graphite : Theme.bark).opacity(0.28), lineWidth: 0.5)
                    .padding(4)
                    .allowsHitTesting(false)
            }
    }
}

/// The ladder's backing: cool brushed slate instead of aged parchment.
private var corporateSlateGradient: LinearGradient {
    LinearGradient(
        colors: [Theme.steel.opacity(0.10), Theme.graphite.opacity(0.14)],
        startPoint: .top, endPoint: .bottom
    )
}

extension View {
    func historicalTreePlate(corporate: Bool = false) -> some View {
        modifier(HistoricalPlate(corporate: corporate))
    }
}
