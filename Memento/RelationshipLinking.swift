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
        if !subject.isSelf, !subject.isBusiness, let selfNode = people.canonicalSelfNode {
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
              let selfNode = people.canonicalSelfNode else { return }

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
        // The graph is keyed by name, which would merge two distinct people
        // sharing one — a chain through the wrong "Sarah" reads as a
        // confidently wrong relationship. Ambiguous names stay out of the
        // graph entirely; this feature is best-effort flavor text, and no
        // path beats a fabricated one.
        var nameCounts: [String: Int] = [:]
        for p in people { nameCounts[key(p.name), default: 0] += 1 }
        func unambiguous(_ name: String) -> Bool { nameCounts[key(name)] == 1 }
        func exists(_ name: String) -> Bool {
            unambiguous(name) &&
            people.contains { $0.name.compare(name.trimmed, options: .caseInsensitive) == .orderedSame }
        }
        guard unambiguous(target.name) else { return nil }

        var adjacency: [String: [(to: String, label: String)]] = [:]
        // Business labels chart the corporate ladder, not the family — a
        // path through "your manager" isn't a family relationship.
        for p in people where !p.relationshipToUser.trimmed.isEmpty && !p.isBusiness && unambiguous(p.name) {
            adjacency[root, default: []].append((key(p.name), p.relationshipToUser.lowercased()))
        }
        for p in people where unambiguous(p.name) {
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
                        AvatarView(data: p.profilePhotoData, name: p.name, size: 40, desaturated: p.isDeceased, business: p.isBusiness)
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
        // Checked against the *pickable* results, not all people — an exact
        // match on the hidden self node or an excluded person would
        // suppress the "add as a name" row while offering nothing to pick,
        // dead-ending a relative who shares your name.
        results.contains { $0.name.compare(trimmedQuery, options: .caseInsensitive) == .orderedSame }
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
                            AvatarView(data: p.profilePhotoData, name: p.name, size: 36, desaturated: p.isDeceased, business: p.isBusiness)
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

/// Editor for one person's place in the family graph: their parents,
/// partners and children. Draft-based, matching the app's cancel-safe
/// editor convention: nothing touches the store until Save, X asks before
/// discarding changes, and a saved banner confirms the commit. Saving also
/// back-fills the affected *profiles* (relationship-to-you labels, family
/// member rows) so the tree and the profiles can't disagree — and clears
/// the fields that would otherwise resurrect a removed link on the next
/// editor save.
struct FamilyLinksEditor: View {
    let subject: Person

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allPeople: [Person]

    private enum Role: String, Identifiable { case parent, partner, child; var id: String { rawValue } }

    struct DraftParentage: Identifiable {
        let id = UUID()
        var person: Person
        var kind: String
        var existing: Parentage?
    }
    struct DraftPartnership: Identifiable {
        let id = UUID()
        var person: Person
        var kind: String
        var existing: Partnership?
    }

    @State private var adding: Role?
    @State private var loadedInitial = false
    @State private var draftParents: [DraftParentage] = []
    @State private var draftChildren: [DraftParentage] = []
    @State private var draftPartners: [DraftPartnership] = []
    @State private var initialParentEdges: [Parentage] = []
    @State private var initialChildEdges: [Parentage] = []
    @State private var initialPartnerEdges: [Partnership] = []
    // Ghosts minted by "add as a name" during this session — real store
    // objects already, so a discard must delete them again.
    @State private var createdGhosts: [Person] = []
    @State private var confirmingDiscard = false
    @State private var showingSavedBanner = false

    private var possessive: String { subject.isSelf ? "Your" : "\(subject.name)\u{2019}s" }

    private var hasChanges: Bool {
        let removedParent = initialParentEdges.contains { edge in !draftParents.contains { $0.existing === edge } }
        let removedChild = initialChildEdges.contains { edge in !draftChildren.contains { $0.existing === edge } }
        let removedPartner = initialPartnerEdges.contains { edge in !draftPartners.contains { $0.existing === edge } }
        let dirtyParent = draftParents.contains { $0.existing == nil || $0.existing?.kind != $0.kind }
        let dirtyChild = draftChildren.contains { $0.existing == nil || $0.existing?.kind != $0.kind }
        let dirtyPartner = draftPartners.contains { $0.existing == nil || $0.existing?.kind != $0.kind }
        return removedParent || removedChild || removedPartner || dirtyParent || dirtyChild || dirtyPartner
    }

    var body: some View {
        NavigationStack {
            List {
                section(title: "\(possessive) parents", drafts: $draftParents,
                        kinds: ParentageKind.allCases.map(\.rawValue), addLabel: "Add parent", role: .parent)
                section(title: "\(possessive) partner", drafts: $draftPartners,
                        kinds: PartnershipKind.allCases.map(\.rawValue), addLabel: "Add partner", role: .partner)
                section(title: "\(possessive) children", drafts: $draftChildren,
                        kinds: ParentageKind.allCases.map(\.rawValue), addLabel: "Add child", role: .child)
            }
            .navigationTitle(subject.isSelf ? "Your Family" : "Family Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        attemptClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveChanges)
                        .disabled(!hasChanges)
                }
            }
            // Swiping the sheet away must go through the same discard check
            // as the X button.
            .interactiveDismissDisabled(hasChanges)
            .alert("Discard Changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { discardAndClose() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your family tree has unsaved changes. Closing now will discard them.")
            }
            .overlay(alignment: .top) {
                if showingSavedBanner {
                    Label("Your changes have been saved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.olive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(item: $adding) { role in
                PersonOrGhostPicker(
                    title: role == .parent ? "Add a Parent" : role == .partner ? "Add a Partner" : "Add a Child",
                    excludeIDs: excludeIDs(for: role),
                    onPick: { addDraft(role, person: $0) },
                    onCreate: { name in
                        if let ghost = resolveGhost(named: name) { addDraft(role, person: ghost) }
                    }
                )
            }
            .onAppear(perform: loadInitialIfNeeded)
        }
    }

    // MARK: Sections & rows

    private func section(title: String, drafts: Binding<[DraftParentage]>,
                         kinds: [String], addLabel: String, role: Role) -> some View {
        Section {
            ForEach(drafts) { $draft in
                linkRow(person: draft.person, kind: $draft.kind, kinds: kinds) {
                    drafts.wrappedValue.removeAll { $0.id == draft.id }
                }
            }
            addButton(addLabel, role: role)
        } header: { Text(title) }
    }

    private func section(title: String, drafts: Binding<[DraftPartnership]>,
                         kinds: [String], addLabel: String, role: Role) -> some View {
        Section {
            ForEach(drafts) { $draft in
                linkRow(person: draft.person, kind: $draft.kind, kinds: kinds) {
                    drafts.wrappedValue.removeAll { $0.id == draft.id }
                }
            }
            addButton(addLabel, role: role)
        } header: { Text(title) }
    }

    private func linkRow(person: Person, kind: Binding<String>, kinds: [String],
                         onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            AvatarView(data: person.profilePhotoData, name: person.name, size: 36, desaturated: person.isDeceased, business: person.isBusiness)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                if person.isGhost {
                    // Immediate, not part of the draft: promoting a ghost to
                    // a listed contact is its own action, not a tree edit.
                    Button("Make a full contact") { person.isGhost = false; try? context.save() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.aegean)
                }
            }
            Spacer()
            Menu {
                ForEach(kinds, id: \.self) { option in
                    Button(option.capitalized) { kind.wrappedValue = option }
                }
            } label: {
                Text(kind.wrappedValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
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

    // MARK: Drafts

    private func loadInitialIfNeeded() {
        guard !loadedInitial else { return }
        loadedInitial = true
        reloadFromStore()
    }

    private func reloadFromStore() {
        initialParentEdges = subject.parentEdges.filter { $0.parent != nil }
        initialChildEdges = subject.childEdges.filter { $0.child != nil }
        initialPartnerEdges = subject.partnerEdges.map(\.edge)
        draftParents = initialParentEdges.compactMap { edge in
            edge.parent.map { DraftParentage(person: $0, kind: edge.kind, existing: edge) }
        }
        draftChildren = initialChildEdges.compactMap { edge in
            edge.child.map { DraftParentage(person: $0, kind: edge.kind, existing: edge) }
        }
        draftPartners = subject.partnerEdges.map { pair in
            DraftPartnership(person: pair.other, kind: pair.edge.kind, existing: pair.edge)
        }
    }

    private func addDraft(_ role: Role, person: Person) {
        guard person !== subject else { return }
        switch role {
        case .parent: draftParents.append(DraftParentage(person: person, kind: ParentageKind.bio.rawValue, existing: nil))
        case .child: draftChildren.append(DraftParentage(person: person, kind: ParentageKind.bio.rawValue, existing: nil))
        case .partner: draftPartners.append(DraftPartnership(person: person, kind: PartnershipKind.partner.rawValue, existing: nil))
        }
    }

    private func excludeIDs(for role: Role) -> Set<PersistentIdentifier> {
        var ids: Set<PersistentIdentifier> = [subject.persistentModelID]
        switch role {
        case .parent:
            // Exclude draft children too — offering one as a parent invites
            // an A\u{21c4}B parentage cycle the pedigree can only draw as
            // contradictory descent loops.
            ids.formUnion(draftParents.map(\.person.persistentModelID))
            ids.formUnion(draftChildren.map(\.person.persistentModelID))
        case .child:
            ids.formUnion(draftChildren.map(\.person.persistentModelID))
            ids.formUnion(draftParents.map(\.person.persistentModelID))
        case .partner:
            ids.formUnion(draftPartners.map(\.person.persistentModelID))
        }
        return ids
    }

    private func resolveGhost(named rawName: String) -> Person? {
        let before = Set(allPeople.map(ObjectIdentifier.init))
        guard let person = resolveOrCreateGhost(named: rawName, in: context, among: allPeople) else { return nil }
        if !before.contains(ObjectIdentifier(person)) {
            createdGhosts.append(person)
        }
        return person
    }

    // MARK: Close / discard

    private func attemptClose() {
        if hasChanges {
            confirmingDiscard = true
        } else {
            discardAndClose()
        }
    }

    private func discardAndClose() {
        // Ghosts minted this session were inserted immediately (they need
        // identities for the draft rows); with the draft discarded they are
        // edgeless orphans — delete them again.
        for ghost in createdGhosts where ghost.isGhost
            && ghost.edgesAsParentArray.isEmpty && ghost.edgesAsChildArray.isEmpty
            && ghost.partnershipsAsAArray.isEmpty && ghost.partnershipsAsBArray.isEmpty {
            context.delete(ghost)
        }
        if !createdGhosts.isEmpty { try? context.save() }
        dismiss()
    }

    // MARK: Save

    private func saveChanges() {
        // Removals first (with profile-field cleanup so the next editor
        // save can't resurrect the link from stale text).
        for edge in initialParentEdges where !draftParents.contains(where: { $0.existing === edge }) {
            clearBackfill(for: edge.parent, role: .parent)
            context.delete(edge)
        }
        for edge in initialChildEdges where !draftChildren.contains(where: { $0.existing === edge }) {
            clearBackfill(for: edge.child, role: .child)
            context.delete(edge)
        }
        for edge in initialPartnerEdges where !draftPartners.contains(where: { $0.existing === edge }) {
            clearBackfill(for: edge.a === subject ? edge.b : edge.a, role: .partner)
            context.delete(edge)
        }

        // Kind updates and additions.
        for draft in draftParents {
            if let existing = draft.existing {
                if existing.kind != draft.kind { existing.kind = draft.kind }
            } else {
                context.insert(Parentage(parent: draft.person, child: subject,
                                         kind: ParentageKind(rawValue: draft.kind) ?? .bio))
                backfill(added: draft.person, role: .parent, kindRaw: draft.kind)
            }
        }
        for draft in draftChildren {
            if let existing = draft.existing {
                if existing.kind != draft.kind { existing.kind = draft.kind }
            } else {
                context.insert(Parentage(parent: subject, child: draft.person,
                                         kind: ParentageKind(rawValue: draft.kind) ?? .bio))
                backfill(added: draft.person, role: .child, kindRaw: draft.kind)
            }
        }
        for draft in draftPartners {
            if let existing = draft.existing {
                if existing.kind != draft.kind { existing.kind = draft.kind }
            } else {
                context.insert(Partnership(a: subject, b: draft.person,
                                           kind: PartnershipKind(rawValue: draft.kind) ?? .partner))
                backfill(added: draft.person, role: .partner, kindRaw: draft.kind)
            }
        }

        createdGhosts = []
        try? context.save()
        reloadFromStore()

        withAnimation(.snappy(duration: 0.25)) { showingSavedBanner = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.3)) { showingSavedBanner = false }
        }
    }

    /// The neutral label a link writes onto profiles ("Parent", not a
    /// guessed "Mother").
    private func genericLabel(role: Role, kindRaw: String) -> String {
        switch role {
        case .parent:
            switch ParentageKind(rawValue: kindRaw) ?? .bio {
            case .bio: return "Parent"
            case .adopted: return "Adoptive parent"
            case .foster: return "Foster parent"
            case .step: return "Stepparent"
            }
        case .child:
            switch ParentageKind(rawValue: kindRaw) ?? .bio {
            case .bio: return "Child"
            case .adopted: return "Adopted child"
            case .foster: return "Foster child"
            case .step: return "Stepchild"
            }
        case .partner:
            return (PartnershipKind(rawValue: kindRaw) ?? .partner) == .former ? "Ex-partner" : "Partner"
        }
    }

    /// Saved links land on the profiles too: the subject gains a family
    /// member row, a real (non-ghost) counterpart gains the reciprocal row,
    /// and — when the subject is the self node — the other person's
    /// "relationship to you" label is set unless a specific fitting label
    /// ("Mother") is already there. Custom unchartable labels are left
    /// alone.
    private func backfill(added other: Person, role: Role, kindRaw: String) {
        let generic = genericLabel(role: role, kindRaw: kindRaw)
        if !subject.isGhost,
           !subject.familyMembersArray.contains(where: {
               $0.name.compare(other.name, options: .caseInsensitive) == .orderedSame
           }) {
            subject.familyMembersArray.append(FamilyMember(name: other.name, relation: generic))
        }
        if !other.isGhost, !subject.isSelf,
           !other.familyMembersArray.contains(where: {
               $0.name.compare(subject.name, options: .caseInsensitive) == .orderedSame
           }) {
            other.familyMembersArray.append(FamilyMember(name: subject.name, relation: FamilyRelation.inverse(of: generic)))
        }
        if subject.isSelf, !other.isGhost {
            let l = other.relationshipToUser.trimmed.lowercased()
            let fits: Bool
            switch role {
            case .parent: fits = FamilyEdgeBuilder.isDirectParentTerm(l)
            case .child: fits = FamilyEdgeBuilder.isDirectChildTerm(l)
            case .partner: fits = FamilyEdgeBuilder.isPartnerTerm(l)
            }
            if l.isEmpty || (FamilyRelation.isChartable(other.relationshipToUser) && !fits) {
                other.relationshipToUser = generic
            }
        }
    }

    /// A removed link clears the profile fields that fed it — otherwise
    /// FamilyEdgeSync would faithfully rebuild the edge from the stale
    /// text on the very next editor save. Both sides need cleaning:
    /// backfill and the editor's applyReciprocalLinks wrote the link onto
    /// the counterpart too (reciprocal family row, partnerName), and
    /// FamilyEdgeSync runs around whichever profile is saved next.
    private func clearBackfill(for other: Person?, role: Role) {
        guard let other else { return }
        if role == .partner,
           subject.partnerName.compare(other.name, options: .caseInsensitive) == .orderedSame {
            subject.partnerName = ""
        }
        // The legacy free-text children list feeds FamilyEdgeSync alongside
        // the family rows — a removed child left there resurrects on the
        // subject's own next save.
        if role == .child {
            removeChildName(other.name, from: subject)
        }
        for member in subject.familyMembersArray where
            member.name.compare(other.name, options: .caseInsensitive) == .orderedSame
            && matchesRole(member.relation, role: role) {
            context.delete(member)
        }

        // The counterpart's fields describe the subject from their side —
        // the subject's parent lists the subject as a child, and partners
        // name each other.
        if role == .partner,
           other.partnerName.compare(subject.name, options: .caseInsensitive) == .orderedSame {
            other.partnerName = ""
        }
        if role == .parent {
            removeChildName(subject.name, from: other)
        }
        for member in other.familyMembersArray where
            member.name.compare(subject.name, options: .caseInsensitive) == .orderedSame
            && matchesRoleAsWholeLabel(member.relation, role: inverse(of: role)) {
            context.delete(member)
        }

        // Removing the hidden "You" node from this profile's links must
        // also clear the profile's own "relationship to you" label —
        // syncSelfEdge treats that label as authoritative and would
        // rebuild the edge on the subject's very next editor save. The
        // label describes the subject from the user's side, so it maps
        // through the inverted role ("Mother" ↔ the self node being the
        // subject's child). Only chartable presets ever feed syncSelfEdge,
        // so a custom label ("Childhood neighbour") is never cleared.
        if other.isSelf,
           FamilyRelation.isChartable(subject.relationshipToUser),
           matchesRole(subject.relationshipToUser, role: inverse(of: role)) {
            subject.relationshipToUser = ""
        }

        if subject.isSelf {
            let l = other.relationshipToUser.trimmed.lowercased()
            let mapsHere: Bool
            switch role {
            case .parent: mapsHere = FamilyEdgeBuilder.isDirectParentTerm(l)
            case .child: mapsHere = FamilyEdgeBuilder.isDirectChildTerm(l)
            case .partner: mapsHere = FamilyEdgeBuilder.isPartnerTerm(l)
            }
            if mapsHere { other.relationshipToUser = "" }
        }
    }

    /// How the removed link reads from the counterpart's side.
    private func inverse(of role: Role) -> Role {
        switch role {
        case .parent: return .child
        case .child: return .parent
        case .partner: return .partner
        }
    }

    /// Drops one name from a profile's free-text children list, keeping
    /// the remaining names in the comma form `childNames(of:)` parses.
    private func removeChildName(_ name: String, from person: Person) {
        let current = childNames(of: person)
        let remaining = current.filter {
            $0.compare(name, options: .caseInsensitive) != .orderedSame
        }
        guard remaining.count != current.count else { return }
        person.childrenNames = remaining.joined(separator: ", ")
    }

    private func matchesRole(_ relation: String, role: Role) -> Bool {
        let l = relation.trimmed.lowercased()
        switch role {
        case .parent: return FamilyEdgeBuilder.isDirectParentTerm(l)
        case .child: return FamilyEdgeBuilder.isDirectChildTerm(l)
        case .partner: return FamilyEdgeBuilder.isPartnerTerm(l)
        }
    }

    /// True when the relation reads as this role *on its own* — everything
    /// backfill and applyReciprocalLinks write ("Partner", "Stepmother").
    /// The keyword matchers alone would also hit hand-written compounds
    /// ("Mum's partner", "Father's brother") that describe a different
    /// link; deleting those from a profile the user never opened would
    /// destroy their own words, so counterpart cleanup leaves them be.
    private func matchesRoleAsWholeLabel(_ relation: String, role: Role) -> Bool {
        guard matchesRole(relation, role: role) else { return false }
        let l = relation.trimmed.lowercased()
        return !l.contains("'s") && !l.contains("\u{2019}s") && !l.contains(" of ")
    }
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
