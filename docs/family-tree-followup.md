# Follow-up: true per-parent-child family trees

Status: **in progress**. Phase 1 (CloudKit spike) complete; Phases 2 to 6
pending. This is the agreed design for turning the current generation-lane
chart into a real genealogical tree with individual parent→child edges,
couples, and correctly distinguished sibling/step/half relations.

**Phase 1 result:** the `Parentage`/`Partnership` join models and
`isSelf`/`isGhost` flags ship as of this change. Validated at runtime on the
simulator. The `ModelContainer` builds against the CloudKit configuration with
no "relationships must be optional" error, and a throwaway probe confirmed edges
insert, save, refetch, and resolve inverses (a self node reading both its
parents through the two Person→`Parentage` relationships). The models are not
yet used by any UI.

## Confirmed decisions

1. **Ghost nodes**: relatives named in free text (no profile) are represented
   as nodes so they can carry edges. They are *not* real contacts.
2. **Hidden self profile**: "You" becomes a real but non-listed `Person`, so
   the pedigree can root on it with genuine edges.
3. **Full pedigree**: ancestors *and* descendants, plus collaterals (siblings,
   aunts/uncles, cousins), not just a descendant chart.
4. **Dashed styling**: step and foster links draw dashed; bio and adopted draw
   solid (adopted optionally badged).
5. **Full build**: new edge model + layout engine, not the name-based
   middle-ground.

## Why the current model can't do this

`Person` stores only free-text relationship strings (`relationshipToUser`,
`partnerName`, `childrenNames`, `FamilyMember.name/relation`) and no parentage
edges or IDs. It records "how this person relates to the focus person" (a
generation), never "who this person's parents are." A real tree needs explicit,
typed edges between specific individuals. Everything else is layout on top.

## Data model

Use **join models** rather than bare self-referential `Person` relationships:
they store the edge *type*, and a self-referential many-to-many across the
CloudKit mirror is the riskiest possible shape (see Phase 1).

```
@Model Parentage    { parent: Person?; child: Person?; kind: String = "bio" }   // bio | adopted | foster | step
@Model Partnership  { a: Person?;      b: Person?;     kind: String = "married" } // married | partner | engaged | former
```

`Person` gains:
- `isSelf: Bool = false`: the single hidden self node.
- `isGhost: Bool = false`: an un-profiled relative (name only).
- inverse optional relationships to `Parentage` (as parent and as child) and
  `Partnership`.

CloudKit rules (see `CLAUDE.md` "Gotchas"): every relationship Optional, every
attribute defaulted, and **the schema only validates when the `ModelContainer`
is built at launch**, so it must be run, not just compiled. Register both new
models in `MementoApp.swift`.

### `isSelf` / `isGhost` are cross-cutting

Both must be excluded everywhere the people list is surfaced. Known touch
points to audit: `PeopleListView` (`people` query, `workspacePeople`, folder
sections, search, counts), `StressSeeder`, `SettingsView` reset counts,
`ImportContactsView`, `NotificationManager`/`CalendarSyncManager` scans, and the
`PersonPickerSheet`. A single computed "listed people" filter should gate all of
them to avoid leaks. This breadth is the main correctness risk after CloudKit.

## Relation semantics → edges/lines

- **Full sibling**: shares both parents. **Half-sibling**: shares exactly one.
  Derived from `Parentage`, not stored.
- **Step-parent**: a parent's partner (`Partnership`) who has no `Parentage`
  edge to you → drawn as spouse-of-parent with a **dashed** link to you.
- **Step-sibling**: child of a step-parent via a different union.
- **Adopted**: solid parent edge, `kind = adopted` (optional badge).
- **Foster**: dashed parent edge, `kind = foster`.
- **Former partner**: `Partnership.kind = former` → dashed couple bar.

## Editor / UX

A dedicated "Family" editor: link parents (0 to 2), partner(s), and children
from existing profiles via `PersonPickerSheet`, or type a name to spawn a
ghost; pick the edge `kind`. Stay cancel-safe (draft → `save()`), and write
reciprocal edges (a `Parentage` is inherently two-sided; no manual inverse
needed, unlike today's `applyReciprocalLinks`). Ghosts get a "promote to full
profile" action.

## Layout engine (largest, riskiest piece)

Replace the generation-lane + horizontal-`ScrollView` layout:

1. Assign generations from the edge graph (BFS from self across parent/child).
2. Order within each generation so partners are adjacent and sibling groups sit
   centered under their parents' union; minimize edge crossings (a tidy
   per-subtree layout, as in the Reingold and Tilford or Walker algorithms).
3. Emit node coordinates + typed connector segments: couple bars, union→sibling
   descent drops, sibling bars, and per-child stubs.
4. Render with a custom SwiftUI `Layout` + `Canvas`; dashed vs solid per edge
   `kind`. Needs pan/zoom for large trees and must work on Mac (no swipe).

The generation-level connectors already shipped (PR #50) are the throwaway
predecessor of this. They connect whole rows, not individuals.

## Migration & compatibility

- On first launch of the new version: create the self `Person`; convert each
  `relationshipToUser` into edges relative to self where determinable
  (Mother/Father → `Parentage`; Son/Daughter → `Parentage`; partner terms →
  `Partnership`; step/half/adopted/foster → set `kind`). Convert
  `partnerName`/`childrenNames`/`FamilyMember` into edges, linking to an existing
  profile by case-insensitive name match or spawning a ghost.
- Keep the old free-text fields intact for a release; **feature-flag** the new
  chart so the shipped generation chart stays the default until the new one is
  proven. Self is created only when the pedigree is first opened.

## Phases & effort

1. ✅ **CloudKit spike**: the two join models + `isSelf`/`isGhost` launching
   cleanly against iCloud. *Done: schema validates and edges persist.*
2. ✅ Model + reciprocal edges + migration. *Done: hidden self node + list
   exclusion (2a), one-time best-effort migration of direct relations into
   edges with ghost creation (2b). Indirect relations left in the old fields.*
3. ✅ Family-linking editor (incl. ghosts, promote-to-profile). *Done:
   `FamilyLinksEditor` edits a subject's parents/partners/children live, adding
   via profile pick or ghost name, with per-edge kind menus and ghost-promote.
   Reachable from a person's Family tab and (for the self node) the tree's Edit
   button.*
4. ✅ Derivation: generations, couples, full/half/step logic. *Done:
   `FamilyGraph.build` derives each reachable person's generation (BFS from
   self), the couples, and sibling groups keyed by exact parent set, so full
   siblings cluster and half-siblings split into separate groups. Pure/testable.*
5. ✅ Layout engine (draws the real tree). *`FamilyTreeLayout` (layered layout
   with barycenter row seeding + relaxation passes) + `PedigreeTreeView` (Canvas
   connectors, parchment/gilt styling, pinch-zoom, tap-to-open) render couple
   bars, sibling groups and per-parent-child descent, crossing-free on a dense
   two-sided pedigree.*
6. ✅ Default flip. *The new pedigree is now the default (`useNewFamilyTree`
   defaults on) with a "New tree layout" toggle in the tree menu to fall back to
   the classic generation chart, and a "No Family Yet" empty state. The classic
   chart is kept, not retired.*

**Status: feature complete**. The new per-parent-child family tree is the
default, with a classic fallback toggle.
4. Derivation: generations, couples, full/half/step logic. *Medium.*
5. Layout engine + typed connector rendering + pan/zoom. *Large.*
6. Hidden-self wiring across all list surfaces; reconcile/replace the existing
   generation chart behind the flag. *Medium.*

Overall **XL** (several focused days). Phases 1 and 5 drive the risk.

## Open sub-decisions (can be settled during Phases 1 and 2)

- Self node's display name: literal "You", or the user's own name (editable)?
- Adopted badge: show a small marker, or rely on the editor only?
- Max pedigree depth to render before requiring tap-to-expand (performance).
