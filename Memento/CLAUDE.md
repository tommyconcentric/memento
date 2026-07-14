# Memento

Personal-CRM app for remembering friends, colleagues and family: per-person notes timeline, quick-info card, auto-generated family trees, dates calendar, reminders, contact import, dictation, and AI "Smart Capture" via the Anthropic API.

## Stack & targets

- SwiftUI + SwiftData, **iOS/iPadOS 17.0+**, macOS via **Mac Catalyst**. No third-party dependencies.
- These sources drop into a standard Xcode iOS App project named **Memento** (delete the template `MementoApp.swift`/`ContentView.swift` first). Project settings live in Xcode, not in this folder.
- Required Info.plist keys: `Privacy - Microphone Usage Description`, `Privacy - Speech Recognition Usage Description`. Contacts picker and local notifications need no plist entries.
- Root layout is `NavigationSplitView` (sidebar people list + detail); collapses to a stack on iPhone.

## File map

- `MementoApp.swift` — entry point, SwiftData container (register every new `@Model` here), seeds starter folders once (`didSeedDefaultGroups` in UserDefaults).
- `Models.swift` — `Person`, `PersonGroup` (folders), `NoteEntry`, `EventPhoto`, `ImportantDate`, `FamilyMember` + helper extensions.
- `Theme.swift` — Mamma Mia palette (aegean, sky, bougainvillea, sunshine, olive, terracotta, gold; dynamic `background`/`card`).
- `Utilities.swift` — `AvatarView`, `InfoRow`, `.mementoCard()` modifier, `PillPicker`, `UIImage.compressedData`, `String.trimmed`/`personInitials`, `Date.daysUntilNextOccurrence`.
- `PeopleListView.swift` — split view, sidebar list with selection, toolbar (settings/folders/tree/calendar/add-import menu).
- `PersonDetailView.swift` — gradient header, `PillPicker` tabs: Quick Info / Family / Notes.
- `QuickInfoView.swift`, `FamilyTreeView.swift`, `CalendarView.swift`, `NotesTimelineView.swift`, `NoteComposerView.swift`, `SmartCaptureView.swift`, `ImportContactsView.swift`, `PersonEditorView.swift`, `GroupsManagerView.swift`, `SettingsView.swift`.
- `SpeechTranscriber.swift` — segmented `SFSpeechRecognizer` engine (auto-restarts for long recordings; on-device when supported).
- `ClaudeService.swift` — Anthropic Messages API (`https://api.anthropic.com/v1/messages`, headers `x-api-key` + `anthropic-version: 2023-06-01`, model constant `claude-sonnet-4-6`), strict-JSON `ConversationInsights` parsing.
- `NotificationManager.swift` — yearly 9 AM reminders; keeps nearest 60 (iOS 64-pending cap).
- `KeychainHelper.swift` — API key storage. Never move the key to UserDefaults, never log or echo it.

## Conventions (follow these when editing)

- **Colors/surfaces:** always `Theme.*`; cards via `.mementoCard()` (continuous 18pt corners); never raw system backgrounds.
- **Typography:** display text (person names, tab labels, wordmark) uses `.serif` design (New York); body stays system sans. Don't reintroduce `.rounded`.
- **Brand:** `LogoMark`/`LogoWordmark` in `AppLogo.swift` draw the tree-of-people mark; `AppIcon-1024.png` and `memento-logo.svg` share its geometry. Signature shapes: the arched hero (UnevenRoundedRectangle 170pt top corners) and underline tabs (`PillPicker`, despite the legacy name). Cards are flat: hairline border, 3pt shadow — no glows. Geometry: avatars, tree portraits and the crop preview are circles (people are round); everything else is rectangular — chips/markers at 8–9pt corners, rectangular hero panel, no capsules in chrome.
- **Avatars:** always `AvatarView` (initials fallback, `desaturated:` for deceased). Compress images with `compressedData` before storing.
- **Editors are cancel-safe:** copy model → local `@State` drafts in `loadInitial()` (guarded by `loadedInitial`), write back only in `save()`. To-many collections (`importantDates`, `familyMembers`, note photos) are replaced wholesale on save.
- **Deceased (`Person.isDeceased`):** desaturate avatars, hide birthday countdowns and skip reminders, leaf/“In Memoriam” markers, no age math.
- **After any save that can change birthdays/important dates** (person editor, import, Smart Capture, deletes): call `NotificationManager.refreshFromContext(context)`.
- **Photo cropping:** new profile photos route through `PhotoCropperView` (pan/pinch, darkened outside the circle) before storage; keep any new photo entry points on that path.
- **Two-way links:** family/partner fields can reference existing profiles (picker or exact name match). `applyReciprocalLinks` in the editor writes the inverse (`FamilyRelation.inverse(of:)`) onto the other person at save. Links are name-based — renames don't propagate.
- **Deep relations:** `RelationshipPath.description` BFSes label/partner/children edges from "you" and renders chains like "Your father's brother's daughter" on the Family tab.
- **Tree UI:** foliage-tinted lanes (olive above, bark below), a bark trunk that thickens downward, leaf rings on nodes. My Family Tree supports hold-drag between lanes (`.draggable`/`.dropDestination`, String name payload) with a label chooser on drop.
- **Family trees** are derived, not stored: `Person.relationshipToUser` labels build "My Family Tree"; a person's own tree comes from partner + children text + `FamilyMember` rows, placed by `FamilyRelation.generation(of:)` keyword matching. Tree nodes link to profiles by case-insensitive name match.
- **Privacy stance:** Smart Capture sends only transcript text + that person's profile summary, and only on explicit user action. Contact import uses `CNContactPickerViewController` (no Contacts permission). Keep it that way.
- Swift style: no force unwraps outside static-URL literals, guard-let early exits, 4-space indent, comments only where intent isn't obvious.

## Gotchas

- If an old `PeopleNotesApp.swift` exists from the first version, **delete it** — `MementoApp.swift` is the entry point now.
- The SwiftData schema grew over versions (isDeceased, relationshipToUser, address, FamilyMember). After replacing sources over an old build, delete the installed app from the simulator/device once.
- Speech recognition is flaky on the Simulator; test dictation/Smart Capture on hardware.
- `Person`/`PersonGroup` are `@Model` classes — compare with `persistentModelID`, not `==` on properties.
- Xcode owns the `.pbxproj`; when adding new source files, add them to the Memento target.

## No tests yet

Manual verification on iPhone + iPad simulators and a Catalyst build. If adding tests, prefer exercising `FamilyRelation.generation`, CSV parsing in `ImportContactsView`, and `ConversationInsights` decoding first.
