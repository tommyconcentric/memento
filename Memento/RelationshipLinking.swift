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

// MARK: - Label → edge vocabulary (shared by the migration and editor sync)

/// The keyword math that decides whether a relationship label describes a
/// *direct* edge (parent, child, partner) and which kind, plus idempotent
/// edge insertion. Shared by the one-time migration and `FamilyEdgeSync`
/// so the two can never drift apart on what "Mother" means.
enum FamilyEdgeBuilder {
    // A direct parent/child is a plain mother/father/child term — not a
    // grandparent, aunt/uncle, niece/nephew, in-law, or godparent, all of
    // which contain those words but sit off the direct line.
    static func isIndirect(_ l: String) -> Bool {
        l.contains("grand") || l.contains("great") || l.contains("aunt")
            || l.contains("uncle") || l.contains("niece") || l.contains("nephew")
            || l.contains("in-law") || l.contains("god") || l.contains("cousin")
    }
    static func isDirectParentTerm(_ l: String) -> Bool {
        !isIndirect(l) && (l.contains("mother") || l.contains("father") || l.contains("parent"))
    }
    static func isDirectChildTerm(_ l: String) -> Bool {
        !isIndirect(l) && (l.contains("daughter") || l.contains("son") || l.contains("child"))
    }
    static func isPartnerTerm(_ l: String) -> Bool {
        l.contains("wife") || l.contains("husband") || l.contains("spouse")
            || l.contains("partner") || l.contains("girlfriend") || l.contains("boyfriend")
            || l.contains("fianc")
    }
    static func parentageKind(_ l: String) -> ParentageKind {
        if l.contains("step") { return .step }
        if l.contains("adopt") { return .adopted }
        if l.contains("foster") { return .foster }
        return .bio
    }
    static func partnershipKind(_ l: String) -> PartnershipKind {
        if l.hasPrefix("ex-") || l.hasPrefix("ex ") || l.contains("former") { return .former }
        if l.contains("fianc") { return .engaged }
        if l.contains("wife") || l.contains("husband") || l.contains("spouse") { return .married }
        return .partner
    }

    /// Inserts a parent→child edge unless one already links the pair.
    static func addParentage(parent: Person, child: Person, kind: ParentageKind, context: ModelContext) {
        guard parent !== child,
              !parent.edgesAsParentArray.contains(where: { $0.child === child }) else { return }
        context.insert(Parentage(parent: parent, child: child, kind: kind))
    }

    /// Inserts a couple edge unless one already links the pair (in either
    /// direction — partnerships are undirected).
    static func addPartnership(_ a: Person, _ b: Person, kind: PartnershipKind, context: ModelContext) {
        guard a !== b else { return }
        let linked = a.partnershipsAsAArray.contains { $0.b === b }
            || a.partnershipsAsBArray.contains { $0.a === b }
        guard !linked else { return }
        context.insert(Partnership(a: a, b: b, kind: kind))
    }
}

// MARK: - Editor save → edges (keeps the pedigree in step with the editor)

/// The one-time migration seeds edges from the free-text fields, but only
/// once — without this, any relationship set in the person editor *after*
/// that first launch would show on the classic chart yet never reach the
/// (default) edge-driven pedigree, which reads only `Parentage`/`Partnership`.
/// Called from `PersonEditorView.save()`.
enum FamilyEdgeSync {
    static func apply(around subject: Person, context: ModelContext) {
        // The subject may be the hidden self node — "My Profile" edits its
        // partner/children/family fields through the same editor, and those
        // feed the pedigree directly. Only step 1 (the self↔subject label)
        // is meaningless for the self node itself.
        guard !subject.isGhost else { return }
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []

        // 1) "They're your…" → the self↔subject edge. The editor's label is
        // authoritative for this one link: changing "Mother" to "Daughter"
        // must stop drawing her as a parent. Business labels chart the
        // corporate ladder, not the family tree.
        if !subject.isSelf, !subject.isBusiness, let selfNode = people.first(where: { $0.isSelf }) {
            syncSelfEdge(subject: subject, selfNode: selfNode, context: context)
        }

        // 2) Partner / children / named family members — add-only, mirroring
        // migration step 2, so a routine editor save never tears down edges
        // hand-built in the family links editor. Names resolve through a
        // registry that learns each ghost as it's created (ghosts first so
        // real profiles win), like the migration's — resolving against the
        // one-shot fetch alone would mint two ghost "Sam"s from a single
        // save naming Sam in two fields.
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
        if let partner = node(for: subject.partnerName) {
            FamilyEdgeBuilder.addPartnership(subject, partner, kind: .partner, context: context)
        }
        for childName in childNames(of: subject) {
            if let child = node(for: childName) {
                FamilyEdgeBuilder.addParentage(parent: subject, child: child, kind: .bio, context: context)
            }
        }
        for member in subject.familyMembersArray {
            let l = member.relation.trimmed.lowercased()
            // Term check before name resolution, so an unchartable relation
            // (sibling, cousin…) doesn't mint an orphan ghost.
            if FamilyEdgeBuilder.isPartnerTerm(l) {
                guard let other = node(for: member.name) else { continue }
                FamilyEdgeBuilder.addPartnership(subject, other, kind: FamilyEdgeBuilder.partnershipKind(l), context: context)
            } else if FamilyEdgeBuilder.isDirectParentTerm(l) {
                guard let other = node(for: member.name) else { continue }
                FamilyEdgeBuilder.addParentage(parent: other, child: subject, kind: FamilyEdgeBuilder.parentageKind(l), context: context)
            } else if FamilyEdgeBuilder.isDirectChildTerm(l) {
                guard let other = node(for: member.name) else { continue }
                FamilyEdgeBuilder.addParentage(parent: subject, child: other, kind: FamilyEdgeBuilder.parentageKind(l), context: context)
            }
        }
    }

    private enum DirectLink { case parent, child, partner }

    /// Drops every direct self↔subject edge (both parentage directions and
    /// any partnership).
    private static func removeDirectSelfEdges(subject: Person, selfNode: Person, context: ModelContext) {
        for edge in subject.edgesAsParentArray where edge.child === selfNode { context.delete(edge) }
        for edge in subject.edgesAsChildArray where edge.parent === selfNode { context.delete(edge) }
        for edge in subject.partnershipsAsAArray where edge.b === selfNode { context.delete(edge) }
        for edge in subject.partnershipsAsBArray where edge.a === selfNode { context.delete(edge) }
    }

    private static func syncSelfEdge(subject: Person, selfNode: Person, context: ModelContext) {
        let label = subject.relationshipToUser.trimmed
        // Only preset labels chart (custom "Other…" text never does), and
        // only direct terms map to an edge — "Aunt" or "Grandmother" can't
        // be placed without inventing the person in between, so existing
        // hand-built edges are left alone. Likewise when the label is
        // cleared: absence of a label is not evidence the link is wrong.
        guard FamilyRelation.isChartable(label) else { return }
        let l = label.lowercased()
        let desired: DirectLink?
        if FamilyEdgeBuilder.isPartnerTerm(l) { desired = .partner }
        else if FamilyEdgeBuilder.isDirectParentTerm(l) { desired = .parent }
        else if FamilyEdgeBuilder.isDirectChildTerm(l) { desired = .child }
        else { desired = nil }
        guard let desired else {
            // Chartable but indirect (Aunt, Grandmother, Cousin…): no edge
            // can be drawn, but the label still asserts this person is NOT
            // a direct parent/child/partner — a mislabeled "Mother"
            // corrected to "Aunt" must stop charting as one. (Only a
            // cleared or custom label leaves hand-built edges alone.)
            removeDirectSelfEdges(subject: subject, selfNode: selfNode, context: context)
            return
        }

        // Drop self↔subject edges the new label contradicts…
        if desired != .parent {
            for edge in subject.edgesAsParentArray where edge.child === selfNode { context.delete(edge) }
        }
        if desired != .child {
            for edge in subject.edgesAsChildArray where edge.parent === selfNode { context.delete(edge) }
        }
        if desired != .partner {
            for edge in subject.partnershipsAsAArray where edge.b === selfNode { context.delete(edge) }
            for edge in subject.partnershipsAsBArray where edge.a === selfNode { context.delete(edge) }
        }

        // …then make the one it asks for, updating kind in place when the
        // link already exists (Mother → Stepmother, Wife → Ex-wife).
        switch desired {
        case .parent:
            if let existing = subject.edgesAsParentArray.first(where: { $0.child === selfNode }) {
                existing.kind = FamilyEdgeBuilder.parentageKind(l).rawValue
            } else {
                FamilyEdgeBuilder.addParentage(parent: subject, child: selfNode, kind: FamilyEdgeBuilder.parentageKind(l), context: context)
            }
        case .child:
            if let existing = subject.edgesAsChildArray.first(where: { $0.parent === selfNode }) {
                existing.kind = FamilyEdgeBuilder.parentageKind(l).rawValue
            } else {
                FamilyEdgeBuilder.addParentage(parent: selfNode, child: subject, kind: FamilyEdgeBuilder.parentageKind(l), context: context)
            }
        case .partner:
            if let existing = subject.partnershipsAsAArray.first(where: { $0.b === selfNode })
                ?? subject.partnershipsAsBArray.first(where: { $0.a === selfNode }) {
                existing.kind = FamilyEdgeBuilder.partnershipKind(l).rawValue
            } else {
                FamilyEdgeBuilder.addPartnership(selfNode, subject, kind: FamilyEdgeBuilder.partnershipKind(l), context: context)
            }
        }
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
            FamilyEdgeBuilder.addParentage(parent: parent, child: child, kind: kind, context: context)
        }

        func addPartnership(_ a: Person, _ b: Person, kind: PartnershipKind) {
            FamilyEdgeBuilder.addPartnership(a, b, kind: kind, context: context)
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

    // Term helpers live in FamilyEdgeBuilder, shared with FamilyEdgeSync.
    private static func isDirectParentTerm(_ l: String) -> Bool { FamilyEdgeBuilder.isDirectParentTerm(l) }
    private static func isDirectChildTerm(_ l: String) -> Bool { FamilyEdgeBuilder.isDirectChildTerm(l) }
    private static func isPartnerTerm(_ l: String) -> Bool { FamilyEdgeBuilder.isPartnerTerm(l) }
    private static func parentageKind(_ l: String) -> ParentageKind { FamilyEdgeBuilder.parentageKind(l) }
    private static func partnershipKind(_ l: String) -> PartnershipKind { FamilyEdgeBuilder.partnershipKind(l) }
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

// MARK: - Family links editor (edit the tree graph directly)

/// Picks an existing profile *or* creates a named ghost, for adding a family
/// link. Search matches profiles; when the query names no one, a "create"
/// row spawns a ghost the tree can carry without a full contact.
struct PersonOrGhostPicker: View {
    let title: String
    let excludeIDs: Set<PersistentIdentifier>
    var onPick: (Person) -> Void
    var onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]
    @State private var query = ""

    private var trimmedQuery: String { query.trimmed }

    private var results: [Person] {
        people.filter { p in
            !p.isSelf && !excludeIDs.contains(p.persistentModelID) &&
            (trimmedQuery.isEmpty || p.name.localizedCaseInsensitiveContains(trimmedQuery))
        }
    }

    private var exactMatchExists: Bool {
        people.contains { $0.name.compare(trimmedQuery, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmedQuery.isEmpty && !exactMatchExists {
                    Button {
                        onCreate(trimmedQuery)
                        dismiss()
                    } label: {
                        Label("Add “\(trimmedQuery)” as a name", systemImage: "plus.circle")
                    }
                }
                ForEach(results) { p in
                    Button {
                        onPick(p)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(data: p.profilePhotoData, name: p.name, size: 36, desaturated: p.isDeceased)
                            Text(p.name).foregroundStyle(.primary)
                            if p.isGhost {
                                Spacer()
                                Text("name only").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search or type a name")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Live editor for one person's place in the family graph: their parents,
/// partners and children, each an add/remove/kind control. Applies straight
/// to the store (no draft) — the same immediate model the tree's drag-to-
/// reparent uses.
struct FamilyLinksEditor: View {
    let subject: Person

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allPeople: [Person]

    private enum Role: String, Identifiable { case parent, partner, child; var id: String { rawValue } }
    @State private var adding: Role?

    private var possessive: String { subject.isSelf ? "Your" : "\(subject.name)’s" }

    var body: some View {
        NavigationStack {
            List {
                parentsSection
                partnersSection
                childrenSection
            }
            .navigationTitle(subject.isSelf ? "Your Family" : "Family Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $adding) { role in
                PersonOrGhostPicker(
                    title: role == .parent ? "Add a Parent" : role == .partner ? "Add a Partner" : "Add a Child",
                    excludeIDs: excludeIDs(for: role),
                    onPick: { link(role, to: $0) },
                    onCreate: { link(role, to: resolveGhost(named: $0)) }
                )
            }
        }
    }

    // MARK: Sections

    private var parentsSection: some View {
        Section {
            ForEach(subject.parentEdges, id: \.persistentModelID) { edge in
                if let parent = edge.parent {
                    personRow(parent, kindMenu: parentageKindMenu(edge)) { context.delete(edge); save() }
                }
            }
            addButton("Add parent", role: .parent)
        } header: { Text("\(possessive) parents") }
    }

    private var childrenSection: some View {
        Section {
            ForEach(subject.childEdges, id: \.persistentModelID) { edge in
                if let child = edge.child {
                    personRow(child, kindMenu: parentageKindMenu(edge)) { context.delete(edge); save() }
                }
            }
            addButton("Add child", role: .child)
        } header: { Text("\(possessive) children") }
    }

    private var partnersSection: some View {
        Section {
            ForEach(subject.partnerEdges, id: \.edge.persistentModelID) { pair in
                personRow(pair.other, kindMenu: partnershipKindMenu(pair.edge)) { context.delete(pair.edge); save() }
            }
            addButton("Add partner", role: .partner)
        } header: { Text("\(possessive) partner") }
    }

    // MARK: Row + controls

    private func personRow(_ person: Person, kindMenu: some View, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            AvatarView(data: person.profilePhotoData, name: person.name, size: 36, desaturated: person.isDeceased)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                if person.isGhost {
                    Button("Make a full contact") { person.isGhost = false; save() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.aegean)
                }
            }
            Spacer()
            kindMenu
            // Click-reachable removal: swipe is the only other affordance,
            // and a Mac mouse can't perform it.
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.terracotta)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(person.name) from these links")
        }
        .swipeActions {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private func addButton(_ label: String, role: Role) -> some View {
        Button { adding = role } label: {
            Label(label, systemImage: "plus.circle")
        }
    }

    private func parentageKindMenu(_ edge: Parentage) -> some View {
        Menu {
            ForEach(ParentageKind.allCases, id: \.self) { kind in
                Button(kind.rawValue.capitalized) { edge.kind = kind.rawValue; save() }
            }
        } label: {
            Text(edge.kind.capitalized).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func partnershipKindMenu(_ edge: Partnership) -> some View {
        Menu {
            ForEach(PartnershipKind.allCases, id: \.self) { kind in
                Button(kind.rawValue.capitalized) { edge.kind = kind.rawValue; save() }
            }
        } label: {
            Text(edge.kind.capitalized).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func excludeIDs(for role: Role) -> Set<PersistentIdentifier> {
        var ids: Set<PersistentIdentifier> = [subject.persistentModelID]
        switch role {
        case .parent: ids.formUnion(subject.parents.map(\.persistentModelID))
        case .child: ids.formUnion(subject.children.map(\.persistentModelID))
        case .partner: ids.formUnion(subject.partnerEdges.map(\.other.persistentModelID))
        }
        return ids
    }

    private func link(_ role: Role, to other: Person?) {
        guard let other, other !== subject else { return }
        switch role {
        case .parent: context.insert(Parentage(parent: other, child: subject, kind: .bio))
        case .child: context.insert(Parentage(parent: subject, child: other, kind: .bio))
        case .partner: context.insert(Partnership(a: subject, b: other, kind: .partner))
        }
        save()
    }

    private func resolveGhost(named rawName: String) -> Person? {
        resolveOrCreateGhost(named: rawName, in: context, among: allPeople)
    }

    private func save() { try? context.save() }
}

/// Finds a non-self profile/ghost by case-insensitive name, or creates a new
/// ghost. Shared by the migration and the family editor.
func resolveOrCreateGhost(named rawName: String, in context: ModelContext, among people: [Person]) -> Person? {
    let name = rawName.trimmed
    guard !name.isEmpty else { return nil }
    if let match = people.first(where: {
        !$0.isSelf && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
    }) { return match }
    let ghost = Person(name: name)
    ghost.isGhost = true
    context.insert(ghost)
    return ghost
}
