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

// MARK: - Family graph derivation (edges → generations, couples, siblings)

/// Turns the raw `Parentage`/`Partnership` edges into the structure the tree
/// layout draws: every reachable person's generation relative to the self
/// node, the couples, and the sibling groups (children keyed by their exact
/// set of parents, so full siblings cluster and half-siblings fall into
/// separate groups). Pure and self-contained, so it can be tested in isolation.
struct FamilyGraph {
    let generation: [PersistentIdentifier: Int]
    let couples: [Couple]
    let siblingGroups: [SiblingGroup]

    struct Couple: Identifiable {
        let id = UUID()
        let a: Person
        let b: Person
        let kind: PartnershipKind
    }

    struct SiblingGroup: Identifiable {
        let id = UUID()
        let parents: [Person]   // the one or more shared parents
        let children: [Person]  // full siblings — they share this exact parent set
    }

    static func build(rootedAt root: Person, among people: [Person]) -> FamilyGraph {
        // Generation via breadth-first search from the self node: a parent is
        // one generation up, a child one down, a partner on the same rung.
        // Shortest-path (BFS) wins if remarriage creates more than one route.
        var generation: [PersistentIdentifier: Int] = [root.persistentModelID: 0]
        var queue = [root]
        var head = 0
        while head < queue.count {
            let person = queue[head]; head += 1
            let g = generation[person.persistentModelID] ?? 0
            func visit(_ other: Person, _ gen: Int) {
                guard generation[other.persistentModelID] == nil else { return }
                generation[other.persistentModelID] = gen
                queue.append(other)
            }
            for parent in person.parents { visit(parent, g + 1) }
            for child in person.children { visit(child, g - 1) }
            for (_, partner) in person.partnerEdges { visit(partner, g) }
        }

        let placed = Set(generation.keys)
        func isPlaced(_ p: Person) -> Bool { placed.contains(p.persistentModelID) }

        // Couples, de-duplicated by unordered pair.
        var seenPairs = Set<Set<PersistentIdentifier>>()
        var couples: [Couple] = []
        for person in people where isPlaced(person) {
            for (edge, other) in person.partnerEdges where isPlaced(other) {
                let key: Set = [person.persistentModelID, other.persistentModelID]
                guard seenPairs.insert(key).inserted else { continue }
                couples.append(Couple(a: person, b: other, kind: PartnershipKind(rawValue: edge.kind) ?? .partner))
            }
        }

        // Sibling groups: bucket children by their exact parent set, keyed
        // on object identity — persistentModelID's string form isn't
        // guaranteed distinct for unsaved models, and a collision would
        // silently merge unrelated sibling groups.
        var buckets: [String: (parents: [Person], children: [Person])] = [:]
        for person in people where isPlaced(person) {
            let parents = person.parents.filter(isPlaced)
            guard !parents.isEmpty else { continue }
            let key = parents
                .map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue)) }
                .sorted()
                .joined(separator: "|")
            buckets[key, default: (parents, [])].children.append(person)
        }
        let siblingGroups = buckets.values.map { SiblingGroup(parents: $0.parents, children: $0.children) }

        return FamilyGraph(generation: generation, couples: couples, siblingGroups: siblingGroups)
    }
}

// MARK: - Pedigree layout engine

/// Positions a `FamilyGraph` for drawing: a layered layout (one row per
/// generation) with a few relaxation passes that pull each person toward the
/// average x of their parents, children and partner, then de-overlap each row.
/// Emits node points, couple bars, and parent→children descent lines. Not a
/// crossing-minimal tidy layout, but reads as a conventional pedigree.
struct FamilyTreeLayout {
    struct Node: Identifiable { let id: PersistentIdentifier; let person: Person; let point: CGPoint }
    struct CoupleBar: Identifiable { let id = UUID(); let a: CGPoint; let b: CGPoint; let dashed: Bool }
    struct Descent: Identifiable { let id = UUID(); let anchor: CGPoint; let children: [ChildStub] }
    struct ChildStub: Identifiable { let id = UUID(); let point: CGPoint; let dashed: Bool }

    let nodes: [Node]
    let coupleBars: [CoupleBar]
    let descents: [Descent]
    let size: CGSize

    static let hGap: CGFloat = 112
    static let vGap: CGFloat = 150
    static let nodeR: CGFloat = 30
    static let margin: CGFloat = 40

    static func compute(_ graph: FamilyGraph, people: [Person]) -> FamilyTreeLayout {
        let placedIDs = Set(graph.generation.keys)
        let placed = people.filter { placedIDs.contains($0.persistentModelID) }
        guard !placed.isEmpty else { return .init(nodes: [], coupleBars: [], descents: [], size: .zero) }

        var byGen: [Int: [Person]] = [:]
        for p in placed { byGen[graph.generation[p.persistentModelID] ?? 0, default: []].append(p) }
        let gens = byGen.keys.sorted(by: >)
        let topGen = gens.first ?? 0
        func rowY(_ g: Int) -> CGFloat { CGFloat(topGen - g) * vGap + margin + nodeR }

        func placedNeighbours(_ list: [Person]) -> [Person] { list.filter { placedIDs.contains($0.persistentModelID) } }

        // Initial order, top generation down: each row is sequenced by the
        // average position of its parents in the row above (a barycenter
        // seed), so children start under their parents and full sibling groups
        // stay contiguous. The relaxation below then refines it. Without this
        // seed, an arbitrary (name) order leaves siblings interleaved and the
        // descent lines cross.
        var x: [PersistentIdentifier: CGFloat] = [:]
        for (rowIndex, g) in gens.enumerated() {
            let row = byGen[g]!
            let ordered: [Person]
            if rowIndex == 0 {
                ordered = row.sorted { $0.name < $1.name }
            } else {
                func parentKey(_ p: Person) -> CGFloat {
                    let px = placedNeighbours(p.parents).compactMap { x[$0.persistentModelID] }
                    return px.isEmpty ? .greatestFiniteMagnitude : px.reduce(0, +) / CGFloat(px.count)
                }
                ordered = row.sorted { (parentKey($0), $0.name) < (parentKey($1), $1.name) }
            }
            for (i, p) in ordered.enumerated() { x[p.persistentModelID] = CGFloat(i) * hGap }
        }

        for _ in 0..<10 {
            var desired: [PersistentIdentifier: CGFloat] = [:]
            for p in placed {
                var samples = [x[p.persistentModelID] ?? 0]
                let kids = placedNeighbours(p.children).compactMap { x[$0.persistentModelID] }
                if !kids.isEmpty { samples.append(kids.reduce(0, +) / CGFloat(kids.count)) }
                let par = placedNeighbours(p.parents).compactMap { x[$0.persistentModelID] }
                if !par.isEmpty { samples.append(par.reduce(0, +) / CGFloat(par.count)) }
                let prt = placedNeighbours(p.partnerEdges.map(\.other)).compactMap { x[$0.persistentModelID] }
                if !prt.isEmpty { samples.append(prt.reduce(0, +) / CGFloat(prt.count)) }
                desired[p.persistentModelID] = samples.reduce(0, +) / CGFloat(samples.count)
            }
            for g in gens {
                let row = byGen[g]!.sorted { (desired[$0.persistentModelID] ?? 0) < (desired[$1.persistentModelID] ?? 0) }
                var last = -CGFloat.greatestFiniteMagnitude
                for p in row {
                    var nx = desired[p.persistentModelID] ?? 0
                    if nx < last + hGap { nx = last + hGap }
                    x[p.persistentModelID] = nx
                    last = nx
                }
            }
        }

        let minX = x.values.min() ?? 0
        func point(_ p: Person) -> CGPoint? {
            guard let px = x[p.persistentModelID], let g = graph.generation[p.persistentModelID] else { return nil }
            return CGPoint(x: px - minX + margin + nodeR, y: rowY(g))
        }

        let nodes: [Node] = placed.compactMap { p in point(p).map { Node(id: p.persistentModelID, person: p, point: $0) } }

        var seen = Set<Set<ObjectIdentifier>>()
        var coupleBars: [CoupleBar] = graph.couples.compactMap { c in
            let key: Set = [ObjectIdentifier(c.a), ObjectIdentifier(c.b)]
            guard seen.insert(key).inserted, let pa = point(c.a), let pb = point(c.b) else { return nil }
            return CoupleBar(a: pa, b: pb, dashed: c.kind.isDashed)
        }

        var descents: [Descent] = []
        for grp in graph.siblingGroups {
            // Placed co-parents, left to right, so the joining bar and its
            // midpoint follow the drawn order rather than the edge order.
            let placedParents = grp.parents
                .compactMap { p in point(p).map { (person: p, point: $0) } }
                .sorted { $0.point.x < $1.point.x }
            let parentPts = placedParents.map(\.point)
            guard !parentPts.isEmpty else { continue }
            // Co-parents with no recorded partnership still get a joining
            // bar — without one, their shared trunk would hang from the
            // empty space between them, touching neither. Three or more
            // co-parents (say bio mother + bio father + step-parent) get a
            // bar spanning them all, one segment per adjacent pair.
            for (a, b) in zip(placedParents, placedParents.dropFirst()) {
                let key: Set = [ObjectIdentifier(a.person), ObjectIdentifier(b.person)]
                if seen.insert(key).inserted {
                    coupleBars.append(CoupleBar(a: a.point, b: b.point, dashed: false))
                }
            }
            let midAnchor = CGPoint(
                x: (parentPts[0].x + parentPts[parentPts.count - 1].x) / 2,
                y: parentPts.map(\.y).reduce(0, +) / CGFloat(parentPts.count))
            // A couple's anchor stays at centre height: it sits on the
            // (possibly just-added) bar between the two portraits. But a
            // trunk starting within a portrait's span — a single parent,
            // or an odd co-parent count whose bar midpoint lands behind
            // the middle portrait — hangs from the *bottom edge* instead:
            // from centre height it would show through the ring halo
            // around the circle (the nodeR + 3 trim rule).
            let anchor = parentPts.contains(where: { abs($0.x - midAnchor.x) < nodeR + 3 })
                ? CGPoint(x: midAnchor.x, y: midAnchor.y + nodeR + 3)
                : midAnchor
            let stubs: [ChildStub] = grp.children.compactMap { kid in
                guard let pt = point(kid) else { return nil }
                let dashed = kid.parentEdges.contains { e in
                    grp.parents.contains { $0 === e.parent } && (ParentageKind(rawValue: e.kind)?.isDashed ?? false)
                }
                return ChildStub(point: pt, dashed: dashed)
            }
            descents.append(Descent(anchor: anchor, children: stubs))
        }

        let maxX = nodes.map(\.point.x).max() ?? 0
        let maxY = nodes.map(\.point.y).max() ?? 0
        // +24 gives the bottom row's name labels (drawn as overlays below
        // the circles, outside the layout frames) room inside the plate.
        return .init(nodes: nodes, coupleBars: coupleBars, descents: descents,
                     size: CGSize(width: maxX + margin + nodeR, height: maxY + margin + nodeR + 24))
    }
}

/// Renders a `FamilyTreeLayout` as a pan/scrollable pedigree: couple bars and
/// descent lines drawn in a Canvas, portraits laid over them.
struct PedigreeTreeView: View {
    let layout: FamilyTreeLayout
    var accent: Color = Theme.gold

    @State private var scale: CGFloat = 1
    @State private var pinchStart: CGFloat = 1

    private var lineColor: Color { Theme.bark.opacity(0.55) }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            chartBody
            .scaleEffect(scale, anchor: .topLeading)
            // Reserve the scaled footprint so the ScrollView can reach every
            // corner when zoomed in.
            .frame(width: max(layout.size.width, 1) * scale,
                   height: max(layout.size.height, 1) * scale,
                   alignment: .topLeading)
            .padding(20)
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in scale = (pinchStart * value).clamped(to: 0.4...2.5) }
                .onEnded { _ in pinchStart = scale }
        )
        // Click-reachable zoom: pinch works on touch screens and trackpads,
        // but a mouse on the Mac has no pinch input at all — without these
        // buttons, Mac mouse users could never zoom the pedigree.
        .overlay(alignment: .bottomTrailing) { zoomControls }
    }

    /// The chart itself, split out of the ScrollView so it can also be
    /// rendered headlessly (ImageRenderer) for verification.
    var chartBody: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(&ctx) }
            ForEach(layout.nodes) { node in
                pedigreeNode(node.person)
                    .position(node.point)
            }
        }
        .frame(width: max(layout.size.width, 1), height: max(layout.size.height, 1))
        .background(treeParchmentGradient)
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button {
                adjustZoom(-0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Zoom out")
            Divider().frame(height: 18)
            Button {
                adjustZoom(0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Zoom in")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .padding(12)
    }

    private func adjustZoom(_ delta: CGFloat) {
        withAnimation(.snappy(duration: 0.2)) {
            scale = (scale + delta).clamped(to: 0.4...2.5)
        }
        pinchStart = scale
    }

    /// Where lines meet portraits: at the outer bark rule (circle radius
    /// + 3), never the centre — a centre-anchored segment shows through
    /// the transparent halo between the avatar's edge and its outer ring.
    private static let lineEnd = FamilyTreeLayout.nodeR + 3

    private func draw(_ ctx: inout GraphicsContext) {
        for bar in layout.coupleBars {
            // Trim the couple bar back to each portrait's frame edge.
            let dx = bar.b.x - bar.a.x, dy = bar.b.y - bar.a.y
            let length = max(hypot(dx, dy), 0.001)
            let t = min(Self.lineEnd / length, 0.49)
            var p = Path()
            p.move(to: CGPoint(x: bar.a.x + dx * t, y: bar.a.y + dy * t))
            p.addLine(to: CGPoint(x: bar.b.x - dx * t, y: bar.b.y - dy * t))
            ctx.stroke(p, with: .color(lineColor), style: stroke(bar.dashed))
        }
        for d in layout.descents where !d.children.isEmpty {
            let busY = (d.anchor.y + (d.children.map(\.point.y).min() ?? d.anchor.y)) / 2
            var trunk = Path(); trunk.move(to: d.anchor); trunk.addLine(to: CGPoint(x: d.anchor.x, y: busY))
            ctx.stroke(trunk, with: .color(lineColor), style: stroke(false))
            let xs = d.children.map(\.point.x)
            var bus = Path()
            bus.move(to: CGPoint(x: min(d.anchor.x, xs.min() ?? d.anchor.x), y: busY))
            bus.addLine(to: CGPoint(x: max(d.anchor.x, xs.max() ?? d.anchor.x), y: busY))
            ctx.stroke(bus, with: .color(lineColor), style: stroke(false))
            for stub in d.children {
                var s = Path(); s.move(to: CGPoint(x: stub.point.x, y: busY))
                s.addLine(to: CGPoint(x: stub.point.x, y: stub.point.y - Self.lineEnd))
                ctx.stroke(s, with: .color(lineColor), style: stroke(stub.dashed))
            }
        }
    }

    private func stroke(_ dashed: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: dashed ? [3, 4] : [])
    }

    @ViewBuilder
    private func pedigreeNode(_ person: Person) -> some View {
        // Real profiles open on tap; the self node and name-only ghosts don't.
        if !person.isSelf && !person.isGhost {
            NavigationLink { PersonDetailView(person: person) } label: { portrait(person) }
                .buttonStyle(.plain)
        } else {
            portrait(person)
        }
    }

    private func portrait(_ person: Person) -> some View {
        // The view's geometric frame is the circle alone, so `.position`
        // puts the circle's CENTRE exactly on the layout point every line
        // aims at. Folding the name into the frame (the old VStack) shifted
        // every circle up by half the label's height — lines stopped short
        // of some portraits and cut through the ring halo of others.
        AvatarView(data: person.profilePhotoData,
                   name: person.isSelf ? "You" : person.name,
                   size: FamilyTreeLayout.nodeR * 2,
                   desaturated: person.isDeceased,
                   business: person.isBusiness)
            // Gilt ring with a fine bark rule floating outside, matching
            // the classic chart's framed-portrait look.
            .overlay(Circle().stroke(accent.opacity(person.isSelf ? 0.9 : 0.55),
                                     lineWidth: person.isSelf ? 2.5 : 1.5))
            .overlay(Circle().stroke(Theme.bark.opacity(person.isSelf ? 0.6 : 0.35), lineWidth: 0.5).padding(-3))
            // The name hangs below as an overlay, outside layout.
            .overlay(alignment: .bottom) {
                Text(person.isSelf ? "You" : person.name)
                    .font(.system(.caption2, design: .serif).weight(person.isSelf ? .semibold : .regular))
                    .foregroundStyle(person.isGhost ? Color.secondary : .primary)
                    .lineLimit(1)
                    .frame(width: 96)
                    .offset(y: 22)
            }
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
    /// False for image export: ImageRenderer doesn't render the content of
    /// UIKit-backed ScrollViews, so exported lanes lay their people out in
    /// plain rows instead (the export frames itself at `exportWidth`, wide
    /// enough for its widest row).
    var scrollableLanes = true
    var onDropInGeneration: ((String, Int) -> Void)? = nil

    @State private var targetedGeneration: Int? = nil
    // Width of the chart, so a lane with only a person or two can centre
    // them across it instead of leaving them pinned to the left edge.
    @State private var laneWidth: CGFloat = 0

    private var ruleColor: Color { corporate ? Theme.graphite : Theme.bark }
    // Total horizontal inset the lane adds around its scroll area; the
    // node row fills the chart width minus this so centring lines up.
    private static let laneHorizontalPadding: CGFloat = 16
    private static let nodeSpacing: CGFloat = 12

    /// The frame width an export needs so its widest generation fits.
    /// The in-app chart hides an overflowing row behind its horizontal
    /// ScrollView; the export lays lanes out flat, and the fixed-width
    /// portrait cells can't compress — a narrower frame slices the
    /// outermost people off both edges of the PNG.
    static func exportWidth(for rows: [TreeRow], minimum: CGFloat) -> CGFloat {
        let widestRow = rows.map { row in
            let count = CGFloat(row.nodes.count)
            return count * FamilyNodeView.cellWidth + max(count - 1, 0) * nodeSpacing
        }.max() ?? 0
        // + the lane's padding and the node row's own 2pt on each side.
        return max(minimum, widestRow + laneHorizontalPadding + 4)
    }

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
            // The anchors are live, so a crowded lane scrolled sideways
            // reports portrait centres past the chart's edges — clip so
            // their stubs and the spanning bar never stroke beyond the
            // plate onto the surrounding page.
            .clipped()
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
            } else if scrollableLanes {
                // A crowded generation overflows its lane sideways; the
                // visible indicator is what makes that scrollable at all
                // with a mouse on the Mac, where there's no swipe.
                ScrollView(.horizontal, showsIndicators: true) {
                    nodeRow(row)
                        // Fill the chart width so a sparse generation
                        // centres; a crowded one exceeds it and the
                        // ScrollView takes over. (maxWidth: .infinity is
                        // inert inside a horizontal ScrollView, which sizes
                        // content to its natural width.)
                        .frame(minWidth: max(0, laneWidth - Self.laneHorizontalPadding), alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else {
                nodeRow(row)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(laneTint(row.id), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.vertical, 1)
    }

    private func nodeRow(_ row: TreeRow) -> some View {
        HStack(spacing: Self.nodeSpacing) {
            ForEach(row.nodes) { node in
                FamilyNodeView(
                    node: node,
                    dragPayload: (dragEnabled && !node.isFocus) ? node.name : nil,
                    corporate: corporate
                )
            }
        }
        .padding(.horizontal, 2)
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

    /// Fixed portrait-cell width; `FamilyTreeContent.exportWidth` sums it
    /// to size exports, so keep the two in step.
    static let cellWidth: CGFloat = 88

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
                desaturated: node.isDeceased,
                business: node.linkedPerson?.isBusiness ?? corporate
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
        .frame(width: Self.cellWidth)
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
    @State private var exportedTree: TreeImageExport.Item?

    private var pedigreeLayout: FamilyTreeLayout? {
        guard let selfNode = people.canonicalSelfNode else { return nil }
        return FamilyTreeLayout.compute(FamilyGraph.build(rootedAt: selfNode, among: people), people: people)
    }

    private var workspace: Workspace {
        Workspace(rawValue: storedWorkspace) ?? .personal
    }

    /// In Business the same sheet renders a corporate ladder: business
    /// contacts placed by working relationship (who reports to whom)
    /// instead of relatives placed by generation.
    private var isLadder: Bool { workspace == .business }

    /// The ladder's population: business contacts with a chartable working
    /// relationship. (The family pedigree draws from edges, not labels.)
    private var labeled: [Person] {
        people.filter {
            let label = $0.relationshipToUser.trimmed
            guard !label.isEmpty, $0.isBusiness else { return false }
            // Custom "Other…" relationships describe someone without
            // placing them on the chart.
            return BusinessRelation.isChartable(label)
        }
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
                generation: BusinessRelation.level(of: person.relationshipToUser)
            )
        }
        nodes.append(TreeNode(
            name: "You", relation: "", photoData: nil,
            linkedPerson: nil, isDeceased: false, isFocus: true, generation: 0
        ))
        return buildTreeRows(
            nodes: nodes,
            subjectTitle: "You",
            ensureGenerations: [-1, 0, 1],
            titleFor: { BusinessRelation.rowTitle(for: $0) }
        )
    }

    /// Shown when you've recorded no family yet — the pedigree would
    /// otherwise be a lone "You". Points at the same editor the toolbar's
    /// "Edit Family Links" opens.
    private var newTreeEmptyState: some View {
        ContentUnavailableView {
            Label("No Family Yet", systemImage: "tree")
        } description: {
            Text("Add your parents, partner and children — or link relatives you already keep in Memento — and your tree draws itself.")
        } actions: {
            Button("Add Family") { showingSelfLinks = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var body: some View {
        // Build the pedigree once per render (and not at all in Business
        // mode, where the ladder is shown instead) — it was computed twice,
        // here and again in the toolbar's `.disabled`, each a full graph
        // BFS + layout pass.
        let layout = isLadder ? nil : pedigreeLayout
        return NavigationStack {
            Group {
                if isLadder {
                    ladderBody
                } else if let layout, layout.nodes.count > 1 {
                    PedigreeTreeView(layout: layout, accent: workspace.accent)
                } else {
                    newTreeEmptyState
                }
            }
            .background(workspace.background)
            // Cards on this screen (the ladder plate) must wear the same
            // workspace surfaces as the background behind them.
            .environment(\.cardWorkspace, workspace)
            .navigationTitle(isLadder ? "Corporate Ladder" : "My Family Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !isLadder {
                        Button("Edit Family Links", systemImage: "point.3.connected.trianglepath.dotted") {
                            showingSelfLinks = true
                        }
                    }
                    Button {
                        exportTreeImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(isLadder ? "Share ladder as picture" : "Share tree as picture")
                    .disabled(isLadder ? labeled.isEmpty : (layout?.nodes.count ?? 0) <= 1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exportedTree) { item in
                ActivityShareSheet(url: item.url)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSelfLinks) {
                if let selfNode = people.canonicalSelfNode {
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
                ForEach(BusinessRelation.labels(forLevel: move.generation), id: \.self) { label in
                    Button(label) { apply(label: label, to: move.person) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { move in
                Text("They're currently your \(move.person.relationshipToUser.lowercased()). Nothing changes until you pick their new relationship — only ones that belong on that rung are offered.")
            }
        }
    }

    /// The Business ladder keeps the classic lane chart — reporting lines
    /// are labels, not graph edges, and drag-between-rungs suits them.
    private var ladderBody: some View {
        ScrollView {
            if labeled.isEmpty {
                ContentUnavailableView {
                    Label("No Ladder Yet", systemImage: "building.2")
                } description: {
                    Text("Set \"Working Relationship to You\" on your business contacts in Edit Person — manager, client, direct report — and your corporate ladder builds itself.")
                }
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap anyone to open their profile. Hold a person and drag them to another rung to change how you work together.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    FamilyTreeContent(rows: rows, dragEnabled: true, corporate: true) { name, level in
                        handleDrop(name: name, generation: level)
                    }
                    .historicalTreePlate(corporate: true)
                    .mementoCard(padding: 10)
                }
                .padding()
            }
        }
    }

    /// The rung name as the dialog should say it.
    private func destinationName(for level: Int) -> String {
        level == 0 ? "your rung" : BusinessRelation.rowTitle(for: level).lowercased()
    }

    /// Renders the visible tree — pedigree or ladder — into a watermarked
    /// PNG and hands it to the share sheet.
    private func exportTreeImage() {
        if isLadder {
            guard !labeled.isEmpty else { return }
            let exportRows = rows
            let content = FamilyTreeContent(rows: exportRows, corporate: true, scrollableLanes: false)
                .historicalTreePlate(corporate: true)
                .frame(width: FamilyTreeContent.exportWidth(for: exportRows, minimum: 780))
            exportedTree = TreeImageExport.export(content, background: workspace.background, filename: "Corporate Ladder")
        } else {
            guard let layout = pedigreeLayout, layout.nodes.count > 1 else { return }
            let content = PedigreeTreeView(layout: layout, accent: workspace.accent).chartBody
            exportedTree = TreeImageExport.export(content, background: workspace.background, filename: "My Family Tree")
        }
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
        guard BusinessRelation.level(of: person.relationshipToUser) != generation else { return }
        pendingMove = MoveRequest(person: person, generation: generation)
    }

    private func apply(label: String, to person: Person) {
        person.relationshipToUser = label
        // Keep the edge graph in step — without this, the drag would move
        // them on the classic chart while the (default) pedigree kept
        // drawing the old relationship indefinitely.
        FamilyEdgeSync.apply(around: person, context: context)
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
    @State private var exportedTree: TreeImageExport.Item?

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

        // The same relative can arrive from two sources — a FamilyMember
        // row and the free-text partner/children fields (reciprocal links
        // and the links editor write rows without filling those fields,
        // which the user may later fill by hand). Dedupe by the same
        // case-insensitive name identity the chart links profiles by,
        // preferring the FamilyMember row: its preset relation ("Wife",
        // "Son") is more specific than the fields' generic Partner/Child.
        var seenNames = Set<String>()
        func appendUnique(_ rawName: String, relation: String) {
            guard seenNames.insert(rawName.trimmed.lowercased()).inserted else { return }
            result.append(node(named: rawName, relation: relation))
        }
        for member in person.familyMembersArray where !member.name.trimmed.isEmpty {
            appendUnique(member.name, relation: member.relation)
        }
        if !person.partnerName.trimmed.isEmpty {
            appendUnique(person.partnerName, relation: "Partner")
        }
        for child in childNames(of: person) {
            appendUnique(child, relation: "Child")
        }
        return result
    }

    private func node(named rawName: String, relation: String) -> TreeNode {
        let name = rawName.trimmed
        // Link only on an unambiguous match — same convention as
        // handleDrop and applyReciprocalLinks. With two profiles sharing
        // this name, guessing would lend the wrong person's photo,
        // deceased state and tap-through profile to the row, so an
        // ambiguous name renders unlinked instead.
        // Real profiles are matched first, hidden graph nodes only as a
        // fallback — an invisible ghost sharing a contact's name must not
        // spoil the one-match rule for the real profile (the same split
        // applyReciprocalLinks and import's duplicate check make).
        let named = people.filter {
            $0.persistentModelID != person.persistentModelID &&
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        let real = named.filter { !$0.isSelf && !$0.isGhost }
        let match = real.count == 1
            ? real.first
            : (real.isEmpty && named.count == 1 ? named.first : nil)
        // Hidden graph nodes (the "You" self node, name-only ghosts) lend
        // their photo to the chart but never a navigation link — a tappable
        // self node would expose Delete Person, which cascades away every
        // family-tree edge. Mirrors PedigreeTreeView.pedigreeNode.
        let linkable = (match?.isSelf == true || match?.isGhost == true) ? nil : match
        return TreeNode(
            name: name,
            relation: relation,
            photoData: match?.profilePhotoData,
            linkedPerson: linkable,
            isDeceased: match?.isDeceased ?? false,
            isFocus: false,
            generation: FamilyRelation.generation(of: relation)
        )
    }

    /// Presets read naturally lowercased mid-sentence ("Your mother");
    /// custom text renders verbatim so names and acronyms survive — the
    /// same rule Quick Info's relationship row applies, both vocabularies
    /// checked because a workspace flip can leave either kind of label.
    private var relationshipChipText: String {
        let relation = person.relationshipToUser
        let isPreset = (FamilyRelation.presets + BusinessRelation.presets).contains {
            $0.compare(relation, options: .caseInsensitive) == .orderedSame
        }
        return "Your \(isPreset ? relation.lowercased() : relation)"
    }

    var body: some View {
        VStack(spacing: 16) {
            if !person.relationshipToUser.trimmed.isEmpty {
                Label(relationshipChipText, systemImage: "person.2.fill")
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
                    // Share this tree as a watermarked picture, from right
                    // on the plate — same export the big tree offers.
                    .overlay(alignment: .topTrailing) {
                        Button {
                            let exportRows = buildTreeRows(nodes: nodes, subjectTitle: person.name)
                            let content = FamilyTreeContent(rows: exportRows, scrollableLanes: false)
                                .historicalTreePlate()
                                .frame(width: FamilyTreeContent.exportWidth(for: exportRows, minimum: 720))
                            exportedTree = TreeImageExport.export(
                                content,
                                background: Theme.background,
                                filename: "\(person.name) — Family Tree"
                            )
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 30, height: 30)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.quaternary, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share \(person.name)'s tree as picture")
                        .padding(8)
                    }

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
        .sheet(item: $exportedTree) { item in
            ActivityShareSheet(url: item.url)
                .presentationDetents([.medium, .large])
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
