# Memento data export/import

Two ways to get data out of Memento and back in, from **Settings → Backup & Transfer**.

## 1. Full backup — `.memento` (JSON)

A single self-describing JSON file holding **everything**: every person in both
workspaces, all their profile fields, notes, important dates, family-member
rows, extra contacts, projects, the folders, the hidden "You" node, and the
family-tree edges — with profile photos and note photos embedded as base64.

Implemented in `DataArchive.swift` (`DataArchiveExport` / `DataArchiveImport`).

### Compatibility contract

A file written by *any* version of Memento can be read by *any* other version.
That guarantee rests on one discipline: **every schema change is additive and
optional.**

- Every field of every archive struct is optional (or defaulted), so a file
  **missing** a field an app expects falls back to the default → an **older**
  file always loads into a **newer** app.
- `JSONDecoder` ignores keys it doesn't recognize, so a file **carrying** fields
  a later feature added still loads into an app that predates them → a **newer**
  file always loads into an **older** app (it drops the parts it can't store).

Rules, forever (enforced by convention, like the privacy manifest):

1. **Only ever add optional fields.** Never remove, rename, or change the type
   or meaning of a field. A retired feature's field stays in the struct — kept
   and ignored — so old files still parse.
2. Bump `formatVersion` only for a genuinely breaking change, with a migration
   path keyed on it. Additive changes never bump it.
3. Dates are ISO-8601; photos are base64 — the file is inspectable and stable
   across time zones and platforms.

Honest boundary: an app only preserves fields it understands, so round-tripping
a *newer* file *through* an older app drops the newer fields. Importing directly
between versions never loses data the two versions share.

### Import behaviour

Additive and idempotent: people are matched to existing ones by **name +
workspace**, so re-importing the same backup doesn't duplicate anyone. Only
genuinely new people bring in their notes, photos and dates. Folders are matched
by name (built-ins reused). The archived "You" node is folded into the device's
own self node, filling blanks without clobbering existing data. Family-tree
edges reconnect via archive-local ids, skipping any that already exist.

## 2. Spreadsheet — `.csv`

A single standalone CSV that also round-trips through Memento, for people who
want their data in a spreadsheet. It **cannot** carry photos or the family-tree
graph, but it covers the everyday data: every listed person in both workspaces,
their quick-info fields, their **notes** and their **important dates**, plus
extra contact rows.

Implemented in `DataCSV.swift` (`MementoCSV`).

One file holds several row kinds, told apart by a leading **Type** column
(`Person`, `Note`, `Date`, `Contact`). `Note`/`Date`/`Contact` rows point at
their owner through the `PersonID` written on the matching `Person` row, so the
whole file re-imports as connected data. Unknown `Type` values and unknown
columns are ignored — same forward/backward tolerance as the JSON archive.
Birthdays use `yyyy-MM-dd`, or `--MM-dd` for a year-less birthday (matching the
contact-import convention).

The CSV import and the "Import from Contacts" screen are separate: this one
reads Memento's own typed-row export; that one reads a plain address-book CSV.

## Importing

**Settings → Backup & Transfer → Import Backup or CSV…** accepts either format
and detects which by content (a `.memento` backup is marked; anything else is
tried as a Memento CSV). Nothing is wiped — an import merges into whatever is
already there.
