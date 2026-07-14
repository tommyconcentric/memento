# Memento

Personal-CRM app for remembering friends, colleagues and family: per-person notes timeline, quick-info card, auto-generated family trees, dates calendar, reminders, contact import, dictation, CloudKit sync across a user's own devices, an optional PIN/Face ID app lock, and a recolorable app icon.

## Stack & targets

- SwiftUI + SwiftData, **iOS/iPadOS 17.0+**, macOS via **Mac Catalyst**. No third-party dependencies.
- Data syncs across devices via CloudKit (`Memento.entitlements`, container `iCloud.brickcedar.Memento`); building/running needs a Team selected under Signing & Capabilities with the iCloud and Background Modes (Remote notifications) capabilities enabled.
- Alternate app icons need `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` (Build Settings) — without it Xcode only compiles the primary `AppIcon` set into `Assets.car` and every alternate silently 404s at runtime.
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
- `QuickInfoView.swift`, `FamilyTreeView.swift`, `CalendarView.swift`, `NotesTimelineView.swift`, `NoteComposerView.swift`, `ImportContactsView.swift`, `PersonEditorView.swift`, `GroupsManagerView.swift`, `SettingsView.swift`.
- `SpeechTranscriber.swift` — segmented `SFSpeechRecognizer` engine (auto-restarts for long recordings; on-device when supported).
- `NotificationManager.swift` — yearly 9 AM reminders; keeps nearest 60 (iOS 64-pending cap).
- `AppLockView.swift` — `AppLock` enum (Keychain-backed PIN, `LogoColorScheme`-independent), `AppLockView` (lock screen), `PINSetupView`.
- `KeychainHelper.swift` — generic Keychain read/save/delete, currently only used for the app-lock PIN.
- `AboutView.swift` — version info + the app icon color picker (`LogoColorScheme.allCases`, in `AppLogo.swift`).
- `Scripts/generate_icons.swift` — regenerates the alternate app icon PNGs; run standalone with `swift Scripts/generate_icons.swift`, not part of the app target.

## Conventions (follow these when editing)

- **Colors/surfaces:** always `Theme.*`; cards via `.mementoCard()` (continuous 18pt corners); never raw system backgrounds.
- **Typography:** display text (person names, tab labels, wordmark) uses `.serif` design (New York); body stays system sans. Don't reintroduce `.rounded`.
- **Brand:** `LogoMark`/`LogoWordmark` in `AppLogo.swift` draw the tree-of-people mark; `AppIcon-1024.png` and `memento-logo.svg` share its geometry. Signature shapes: the arched hero (UnevenRoundedRectangle 170pt top corners) and underline tabs (`PillPicker`, despite the legacy name). Cards are flat: hairline border, 3pt shadow — no glows. Geometry: avatars, tree portraits and the crop preview are circles (people are round); everything else is rectangular — chips/markers at 8–9pt corners, rectangular hero panel, no capsules in chrome.
- **Recoloring the logo:** `LogoMark`/`LogoWordmark` take a `colorScheme: LogoColorScheme` (default `.default`); every view that shows the logo should read the user's actual pick from `@AppStorage("logoColorScheme")` rather than hardcoding `.default`, or the sidebar/empty-state logo will disagree with the Home Screen icon. Adding a 9th color needs three things kept in sync: a `LogoColorScheme` case + colors in `AppLogo.swift`, a matching `Variant` in `Scripts/generate_icons.swift`, and a new `AppIcon-<Name>.appiconset` folder.
- **App Lock:** the 4-digit PIN (`AppLock`, Keychain-backed) is always the source of truth; Face ID/Touch ID is only ever an optional fast-path on top of it. Never let a setting enable biometrics without a PIN already set — that's how you build a permanent lockout.
- **Avatars:** always `AvatarView` (initials fallback, `desaturated:` for deceased). Compress images with `compressedData` before storing.
- **Editors are cancel-safe:** copy model → local `@State` drafts in `loadInitial()` (guarded by `loadedInitial`), write back only in `save()`. To-many collections (`importantDates`, `familyMembers`, note photos) are replaced wholesale on save.
- **Deceased (`Person.isDeceased`):** desaturate avatars, hide birthday countdowns and skip reminders, leaf/“In Memoriam” markers, no age math.
- **After any save that can change birthdays/important dates** (person editor, import, deletes): call `NotificationManager.refreshFromContext(context)`.
- **Photo cropping:** new profile photos route through `PhotoCropperView` (pan/pinch, darkened outside the circle) before storage; keep any new photo entry points on that path.
- **Two-way links:** family/partner fields can reference existing profiles (picker or exact name match). `applyReciprocalLinks` in the editor writes the inverse (`FamilyRelation.inverse(of:)`) onto the other person at save. Links are name-based — renames don't propagate.
- **Deep relations:** `RelationshipPath.description` BFSes label/partner/children edges from "you" and renders chains like "Your father's brother's daughter" on the Family tab.
- **Tree UI:** foliage-tinted lanes (olive above, bark below), a bark trunk that thickens downward, leaf rings on nodes. My Family Tree supports hold-drag between lanes (`.draggable`/`.dropDestination`, String name payload) with a label chooser on drop.
- **Family trees** are derived, not stored: `Person.relationshipToUser` labels build "My Family Tree"; a person's own tree comes from partner + children text + `FamilyMember` rows, placed by `FamilyRelation.generation(of:)` keyword matching. Tree nodes link to profiles by case-insensitive name match.
- **Privacy stance:** no data leaves the user's own iCloud account — the only network traffic is CloudKit sync. Contact import uses `CNContactPickerViewController` (no Contacts permission). Keep it that way; think hard before adding any third-party network call, since that reopens App Store privacy-disclosure and policy work this app currently avoids.
- Swift style: no force unwraps outside static-URL literals, guard-let early exits, 4-space indent, comments only where intent isn't obvious.

## Gotchas

- **CloudKit schema validation is runtime-only.** `xcodebuild build` compiling cleanly proves nothing about the CloudKit configuration — SwiftData only validates the schema (every to-many relationship Optional, every attribute has a default) when the `ModelContainer` is actually constructed at launch. A bad schema change will build fine and then crash on first launch with "CloudKit integration requires that all relationships be optional." Always actually run the app after touching `Models.swift`, not just build it.
- To-many relationships (`notes`, `importantDates`, `familyMembers`, `people`, `photos`) are declared `Optional` in `Models.swift` for that reason — use the non-optional `notesArray`/`importantDatesArray`/`familyMembersArray`/`peopleArray`/`photosArray` computed accessors everywhere else; don't reintroduce raw non-optional array properties.
- If an old `PeopleNotesApp.swift` exists from the first version, **delete it** — `MementoApp.swift` is the entry point now.
- The SwiftData schema grew over versions (isDeceased, relationshipToUser, address, FamilyMember). After replacing sources over an old build, delete the installed app from the simulator/device once.
- Speech recognition is flaky on the Simulator; test dictation on hardware.
- `Person`/`PersonGroup` are `@Model` classes — compare with `persistentModelID`, not `==` on properties.
- Xcode owns the `.pbxproj`; when adding new source files, add them to the Memento target.

## Git identity in Claude Code sessions

Claude Code's remote execution environment defaults every commit to `Claude <noreply@anthropic.com>` via a platform-level global gitconfig that's reapplied fresh each session — it can't be fixed by editing this repo's git config (and editing global git config isn't something a session should do anyway). Any commit made through a Claude Code session in this repo should override identity per-invocation instead, e.g.:
`git -c user.name="Tommy Le" -c user.email="tommy@concentric.health" commit ...`
The actual durable fix is setting `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL` as environment variables on the Claude Code environment configuration — git honors those over the global config for every commit in every future session on that environment.

## No tests yet

Manual verification on iPhone + iPad simulators and a Catalyst build. If adding tests, prefer exercising `FamilyRelation.generation` and CSV parsing in `ImportContactsView` first.
