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
        if l.contains("mother") || l.contains("father") || l.contains("parent") { return "Child" }
        if l.contains("aunt") || l.contains("uncle") { return "Niece/Nephew" }
        if l.contains("niece") || l.contains("nephew") { return "Aunt/Uncle" }
        if l.contains("daughter") || l.contains("son") || l.contains("child") { return "Parent" }
        if l.contains("wife") || l.contains("husband") || l.contains("partner") || l.contains("spouse") { return "Partner" }
        if l.contains("cousin") { return "Cousin" }
        return "Family"
    }
}

// MARK: - Deep relationship description ("Your father's brother's daughter")

enum RelationshipPath {
    /// Breadth-first search from "you" across relationship labels, partner
    /// and children links. Returns a possessive chain for indirect
    /// relations (2+ hops); direct relations already show as a chip.
    static func description(to target: Person, people: [Person], maxHops: Int = 4) -> String? {
        func key(_ name: String) -> String { name.trimmed.lowercased() }
        func exists(_ name: String) -> Bool {
            people.contains { $0.name.compare(name.trimmed, options: .caseInsensitive) == .orderedSame }
        }

        var adjacency: [String: [(to: String, label: String)]] = [:]
        for p in people where !p.relationshipToUser.trimmed.isEmpty {
            adjacency["you", default: []].append((key(p.name), p.relationshipToUser.lowercased()))
        }
        for p in people {
            var edges: [(to: String, label: String)] = []
            if !p.partnerName.trimmed.isEmpty, exists(p.partnerName) {
                edges.append((key(p.partnerName), "partner"))
            }
            for child in childNames(of: p) where exists(child) {
                edges.append((key(child), "child"))
            }
            for member in p.familyMembers where exists(member.name) {
                edges.append((key(member.name), member.relation.lowercased()))
            }
            if !edges.isEmpty { adjacency[key(p.name), default: []].append(contentsOf: edges) }
        }

        let goal = key(target.name)
        var queue: [(node: String, labels: [String])] = [("you", [])]
        var seen: Set<String> = ["you"]
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
            p.persistentModelID != excludeID &&
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
