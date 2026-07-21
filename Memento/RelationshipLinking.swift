import SwiftUI
import SwiftData

// MARK: - Inverse relations (for two-way linking)

extension FamilyRelation {
    /// Neutral inverse written onto the other person's profile when a
    /// family link points at an existing Memento profile.
    static func inverse(of relation: String) -> String {
        let l = relation.lowercased()
        if l.contains("great-grand") || l.contains("great grand") {
            return (l.contains("daughter") || l.contains("son") || l.contains("child"))
                ? "Great-grandparent" : "Great-grandchild"
        }
        if l.contains("grandmother") || l.contains("grandfather") || l.contains("grandparent") { return "Grandchild" }
        if l.contains("granddaughter") || l.contains("grandson") || l.contains("grandchild") { return "Grandparent" }
        if l.contains("in-law") {
            if l.contains("mother") || l.contains("father") || l.contains("parent") { return "Child-in-law" }
            if l.contains("daughter") || l.contains("son") || l.contains("child") { return "Parent-in-law" }
            return "Sibling-in-law"
        }
        // Godparents before the plain parent branch — "godmother" would
        // otherwise match "mother" and invert to "Child".
        if l.contains("god") {
            if l.contains("mother") || l.contains("father") || l.contains("parent") { return "Godchild" }
            return "Godparent"
        }
        // Exes before the partner branch — "ex-girlfriend" contains
        // "girlfriend" and must not invert to a current "Partner".
        if l.hasPrefix("ex-") || l.hasPrefix("ex ") { return "Ex-partner" }
        // Halves before the sibling branch, so the qualifier survives the
        // round trip.
        if l.contains("half") { return "Half-sibling" }
        // Step / adoptive / foster relations keep their qualifier across the
        // link, the way half- and god- do — a stepfather's counterpart is a
        // stepchild, not a plain child. Parent-side labels invert to the
        // child term and vice versa.
        if l.contains("step") || l.contains("adopt") || l.contains("foster") {
            let parentTerm: String, childTerm: String, siblingTerm: String
            if l.contains("adopt") {
                (parentTerm, childTerm, siblingTerm) = ("Adoptive parent", "Adopted child", "Sibling")
            } else if l.contains("foster") {
                (parentTerm, childTerm, siblingTerm) = ("Foster parent", "Foster child", "Sibling")
            } else {
                (parentTerm, childTerm, siblingTerm) = ("Stepparent", "Stepchild", "Stepsibling")
            }
            if l.contains("mother") || l.contains("father") || l.contains("parent") { return childTerm }
            if l.contains("daughter") || l.contains("son") || l.contains("child") { return parentTerm }
            if l.contains("sister") || l.contains("brother") || l.contains("sibling") { return siblingTerm }
        }
        if l.contains("fianc") { return "Fiancé(e)" }
        if l.contains("mother") || l.contains("father") || l.contains("parent") { return "Child" }
        if l.contains("aunt") || l.contains("uncle") { return "Niece/Nephew" }
        if l.contains("niece") || l.contains("nephew") { return "Aunt/Uncle" }
        if l.contains("brother") || l.contains("sister") || l.contains("sibling") { return "Sibling" }
        if l.contains("daughter") || l.contains("son") || l.contains("child") { return "Parent" }
        if l.contains("wife") || l.contains("husband") || l.contains("partner") || l.contains("spouse")
            || l.contains("girlfriend") || l.contains("boyfriend") { return "Partner" }
        if l.contains("cousin") { return "Cousin" }
        return "Family"
    }
}

// MARK: - One-time migration of free-text family data into edges

/// Converts the existing free-text family fields into `Parentage`/`Partnership`
/// edges once, so the new tree has data to draw. Best-effort: only relations
/// that map to a *direct* edge are converted (parents, children, partners).
/// Indirect ones (siblings, grandparents, aunts, cousins, in-laws) are left in
/// the old fields for the user to re-link precisely in the family editor —
/// they can't be placed without inventing intermediate people.
enum FamilyGraphMigration {
    static let didRunKey = "didMigrateFamilyEdgesV1"

    static func runIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didRunKey) else { return }
        guard let people = try? context.fetch(FetchDescriptor<Person>()),
              let selfNode = people.first(where: { $0.isSelf }) else { return }

        // Resolve a name to a node: prefer a real profile, then any existing
        // ghost, else create a ghost. Profiles registered last so they win.
        var byName: [String: Person] = [:]
        for p in people where !p.isSelf && p.isGhost { byName[p.name.trimmed.lowercased()] = p }
        for p in people where !p.isSelf && !p.isGhost { byName[p.name.trimmed.lowercased()] = p }

        func node(for rawName: String) -> Person? {
            let name = rawName.trimmed
            guard !name.isEmpty else { return nil }
            if let existing = byName[name.lowercased()] { return existing }
            let ghost = Person(name: name)
            ghost.isGhost = true
            context.insert(ghost)
            byName[name.lowercased()] = ghost
            return ghost
        }

        func addParentage(parent: Person, child: Person, kind: ParentageKind) {
            guard parent !== child,
                  !parent.edgesAsParentArray.contains(where: { $0.child === child }) else { return }
            context.insert(Parentage(parent: parent, child: child, kind: kind))
        }

        func addPartnership(_ a: Person, _ b: Person, kind: PartnershipKind) {
            guard a !== b else { return }
            let linked = a.partnershipsAsAArray.contains { $0.b === b }
                || a.partnershipsAsBArray.contains { $0.a === b }
            guard !linked else { return }
            context.insert(Partnership(a: a, b: b, kind: kind))
        }

        // 1) relationshipToUser → edges relative to the self node.
        for p in people where !p.isSelf && !p.isGhost {
            let label = p.relationshipToUser.trimmed
            guard FamilyRelation.isChartable(label) else { continue }
            let l = label.lowercased()
            if isPartnerTerm(l) {
                addPartnership(selfNode, p, kind: partnershipKind(l))
            } else if isDirectParentTerm(l) {
                addParentage(parent: p, child: selfNode, kind: parentageKind(l))
            } else if isDirectChildTerm(l) {
                addParentage(parent: selfNode, child: p, kind: parentageKind(l))
            }
        }

        // 2) Each person's own partner / children / family-member fields.
        for p in people where !p.isSelf && !p.isGhost {
            if let partner = node(for: p.partnerName) {
                addPartnership(p, partner, kind: .partner)
            }
            for childName in childNames(of: p) {
                if let child = node(for: childName) {
                    addParentage(parent: p, child: child, kind: .bio)
                }
            }
            for member in p.familyMembersArray {
                let l = member.relation.trimmed.lowercased()
                guard let other = node(for: member.name) else { continue }
                if isPartnerTerm(l) {
                    addPartnership(p, other, kind: partnershipKind(l))
                } else if isDirectParentTerm(l) {
                    addParentage(parent: other, child: p, kind: parentageKind(l))
                } else if isDirectChildTerm(l) {
                    addParentage(parent: p, child: other, kind: parentageKind(l))
                }
            }
        }

        if (try? context.save()) != nil {
            UserDefaults.standard.set(true, forKey: didRunKey)
        }
    }

    // A direct parent/child is a plain mother/father/child term — not a
    // grandparent, aunt/uncle, niece/nephew, in-law, or godparent, all of
    // which contain those words but sit off the direct line.
    private static func isIndirect(_ l: String) -> Bool {
        l.contains("grand") || l.contains("great") || l.contains("aunt")
            || l.contains("uncle") || l.contains("niece") || l.contains("nephew")
            || l.contains("in-law") || l.contains("god") || l.contains("cousin")
    }
    private static func isDirectParentTerm(_ l: String) -> Bool {
        !isIndirect(l) && (l.contains("mother") || l.contains("father") || l.contains("parent"))
    }
    private static func isDirectChildTerm(_ l: String) -> Bool {
        !isIndirect(l) && (l.contains("daughter") || l.contains("son") || l.contains("child"))
    }
    private static func isPartnerTerm(_ l: String) -> Bool {
        l.contains("wife") || l.contains("husband") || l.contains("spouse")
            || l.contains("partner") || l.contains("girlfriend") || l.contains("boyfriend")
            || l.contains("fianc")
    }
    private static func parentageKind(_ l: String) -> ParentageKind {
        if l.contains("step") { return .step }
        if l.contains("adopt") { return .adopted }
        if l.contains("foster") { return .foster }
        return .bio
    }
    private static func partnershipKind(_ l: String) -> PartnershipKind {
        if l.hasPrefix("ex-") || l.hasPrefix("ex ") || l.contains("former") { return .former }
        if l.contains("fianc") { return .engaged }
        if l.contains("wife") || l.contains("husband") || l.contains("spouse") { return .married }
        return .partner
    }
}

// MARK: - Deep relationship description ("Your father's brother's daughter")

enum RelationshipPath {
    /// Breadth-first search from "you" across relationship labels, partner
    /// and children links. Returns a possessive chain for indirect
    /// relations (2+ hops); direct relations already show as a chip.
    static func description(to target: Person, people: [Person], maxHops: Int = 4) -> String? {
        // Sentinel for "you" that can't collide with a trimmed/lowercased
        // person name (e.g. someone actually named "You").
        let root = "\u{0}you"
        func key(_ name: String) -> String { name.trimmed.lowercased() }
        func exists(_ name: String) -> Bool {
            people.contains { $0.name.compare(name.trimmed, options: .caseInsensitive) == .orderedSame }
        }

        var adjacency: [String: [(to: String, label: String)]] = [:]
        for p in people where !p.relationshipToUser.trimmed.isEmpty {
            adjacency[root, default: []].append((key(p.name), p.relationshipToUser.lowercased()))
        }
        for p in people {
            var edges: [(to: String, label: String)] = []
            if !p.partnerName.trimmed.isEmpty, exists(p.partnerName) {
                edges.append((key(p.partnerName), "partner"))
            }
            for child in childNames(of: p) where exists(child) {
                edges.append((key(child), "child"))
            }
            for member in p.familyMembersArray where exists(member.name) {
                edges.append((key(member.name), member.relation.lowercased()))
            }
            if !edges.isEmpty { adjacency[key(p.name), default: []].append(contentsOf: edges) }
        }

        let goal = key(target.name)
        var queue: [(node: String, labels: [String])] = [(root, [])]
        var seen: Set<String> = [root]
        while !queue.isEmpty {
            let (node, labels) = queue.removeFirst()
            guard labels.count < maxHops else { continue }
            for edge in adjacency[node] ?? [] where !seen.contains(edge.to) {
                let next = labels + [edge.label]
                if edge.to == goal {
                    return next.count >= 2 ? "Your " + next.joined(separator: "\u{2019}s ") : nil
                }
                seen.insert(edge.to)
                queue.append((edge.to, next))
            }
        }
        return nil
    }
}

// MARK: - Person picker (search existing profiles to link them)

struct PersonPickerSheet: View {
    let excludeID: PersistentIdentifier?
    var onPick: (Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]
    @State private var query = ""

    private var results: [Person] {
        people.filter { p in
            p.persistentModelID != excludeID && !p.isSelf && !p.isGhost &&
            (query.trimmed.isEmpty || p.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { p in
                Button {
                    onPick(p)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(data: p.profilePhotoData, name: p.name, size: 40, desaturated: p.isDeceased)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            if !p.subtitle.isEmpty {
                                Text(p.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search people")
            .navigationTitle("Link a Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}
