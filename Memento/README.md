# Memento

A personal iOS app for remembering the people in your life: friends, colleagues and family. Keep a running notebook per person, a quick-reference card of details, auto-generated family trees, a calendar of everyone's important dates, and voice-powered note capture.

Built with SwiftUI + SwiftData. No third-party dependencies. Records sync across your own devices via CloudKit; there are no other network calls.

## Features

- **People with profile photos**: colored-initials avatars when no photo is set.
- **Folders**: Close Friends, Friends, Work Colleagues and Family are created for you. Add, rename, reorder or delete folders freely.
- **Quick Info card (separate from notes)**: relationship to you, birthday (with age and countdown), partner, children, family, work, hobbies, hometown, how you met, food & drink, **phone, email and address**, plus custom important dates.
- **Family trees, auto-generated**: label each person's *Relationship to You* (mother, brother, grandson…) and the **tree icon** on the main screen draws your family tree from those labels, placed by generation. Every person also gets their own **Family tab**: their tree builds itself from their partner, children and any named family members you add. Tree nodes link to profiles when the name matches someone in Memento. The tree looks the part: leafy olive lanes for older generations, warm bark below, and a trunk that thickens toward the roots. On **My Family Tree you can hold a person and drag them to another row**, then pick their new label. Family and partner fields can **link to existing profiles** (tap the magnifier or type an exact name) and the inverse relationship is written to the other person automatically, so it shows both ways. Indirect relations get a plain-English line like *"Your father's brother's daughter."* Profile photos now open a **circular cropper** (pan and pinch, with everything outside the circle darkened) before saving.
- **Import contacts**. The **＋ menu → Import Contacts** offers two honest routes: **iOS Contacts** opens Apple's picker so you choose exactly who to import (names, photos, numbers, emails, addresses and birthdays come along, and since WhatsApp uses your phone's address book, this covers your WhatsApp people). **Facebook export / CSV**: Facebook shut down its friends API years ago, so instead import the friends JSON from Facebook's *Download Your Information* (names only, because Facebook doesn't export friends' birthdays) or any CSV with name, birthday, phone, email, address columns. Either way you review the list, untick anyone, and pick the folder before saving. Duplicates are flagged.
- **Important-dates calendar**: the **calendar icon** shows a month view where each birthday, anniversary or custom date appears as that person's photo (or initials circle) on the day. Tap a day for the full list with "turns 34" and profile links.
- **Birthday & date reminders**: flip the toggle in Settings for a 9 AM notification on birthdays and important dates (skips people marked in memoriam; iOS caps scheduled notifications, so the nearest 60 dates are kept and refreshed as data changes).
- **Running notes timeline**: notes with date, location and event photos with captions.
- **Dictation**: tap the mic in the note editor and speak.
- **In Memoriam**: mark someone as deceased. Their profile grays. Birthday countdowns and reminders pause.
- **iCloud sync**: your people, notes and photos sync automatically across your own iPhone, iPad and Mac via CloudKit.
- **App Lock**: an optional 4-digit PIN (Settings → App Lock), with Face ID/Touch ID as a faster unlock on top of it. The PIN is the source of truth, so as long as you know it you can't be locked out. If you forget it you have to reinstall, and your data restores from iCloud.
- **About & app icon color**: tap the logo (top-left) for version info and a pick of 8 Home Screen icon colors (plus a matching in-app logo tint): Default, Red, Purple, Orange, Pink, Green, Navy Blue, Monochrome.
- **Made for iPhone, iPad and Mac**. The layout adapts: a stack on iPhone, a split view (people list beside the open profile) on iPad and Mac. Soft continuous-corner cards, a pill tab bar, rounded display type and a sun-motif header keep the UI clean and modern.
- **Mamma Mia palette**: Aegean blues, whitewash, bougainvillea, olive, terracotta and gold; deep night-sea dark mode.

## Logo & app icon

The mark is a small tree whose canopy is three connected people-nodes (family tree meets relationship graph), with the crown node in island gold. `AppLogo.swift` draws it in-app (sidebar, empty states); `AppIcon-1024.png` is the ready-made icon (open Assets.xcassets → AppIcon and drop it in the 1024 slot); `memento-logo.svg` is the source for anything else.

Seven more colors live alongside the default as alternate Home Screen icons: `Assets.xcassets/AppIcon-<Name>.appiconset` for each, picked from the About screen via `UIApplication.setAlternateIconName`. `Scripts/generate_icons.swift` renders all of them from the same tree-of-people geometry (run with `swift Scripts/generate_icons.swift`); `LogoColorScheme` in `AppLogo.swift` holds the matching in-app tint for each one, so the sidebar logo always agrees with whatever's on the Home Screen.

The design language got a refresh too: New York serif display type, a clean rectangular hero panel, circular portraits with a matching circular crop, underline tabs, hairline cards, journal-style date rails on notes, and a hand-drawn line icon set instead of emoji.

## Requirements

- A Mac with **Xcode 15 or newer**
- **iOS 17.0+ / iPadOS 17.0+** deployment target (SwiftData); runs on Mac via **Mac Catalyst**
- iPhone, iPad, Mac or the Simulator (speech recognition is far more reliable on real hardware)
- An Apple Developer Program membership and a signed-in iCloud account, for CloudKit sync

## Setup (about 5 minutes)

1. Xcode → **File → New → Project…** → **iOS → App**.
2. Name it **Memento**, Interface **SwiftUI**, Language **Swift**. Leave Core Data and tests unchecked.
3. Delete the two generated Swift files (`MementoApp.swift` and `ContentView.swift`), choosing "Move to Trash".
4. Drag all the `.swift` files from this folder into the project navigator. Tick **"Copy items if needed"**, target **Memento** checked.
5. Project → target **Memento** → General → **Minimum Deployments: iOS 17.0**.
6. Target → **Info** tab → add two keys (required, or dictation will crash):
   - `Privacy - Microphone Usage Description` → `Memento uses the microphone to dictate notes and capture conversations.`
   - `Privacy - Speech Recognition Usage Description` → `Memento transcribes your recordings into notes.`
   (The contacts picker and local notifications need no Info.plist entries. The picker never reads your address book without you choosing people, and notification permission is asked in-app.)
7. Run.

> **Upgrading from an earlier build?** Delete the old app from the device/simulator first. The data model gained family trees, relationship labels and addresses.

## iPad & Mac

The interface is adaptive out of the box. There's no extra code to write, only destinations to add:

- **iPad:** already included. In the target's General tab, Supported Destinations lists iPhone and iPad by default; pick an iPad simulator and run. You'll get the split view with the people list on the left and the open profile on the right.
- **Mac:** in Supported Destinations click **+** and add **Mac (Mac Catalyst)**. For the most Mac-like controls, select that destination row and tick **"Optimize Interface for Mac"**. Dictation, the contacts picker, notifications and CloudKit sync all run through the same code.
- **Zero-setup alternative** on Apple Silicon Macs: add **Mac (Designed for iPad)** instead. The unmodified iPad app runs as a window.

## File guide

| File | What it does |
|---|---|
| `MementoApp.swift` | App entry, SwiftData container, seeds the starter folders |
| `Theme.swift` | Mamma Mia palette with dark-mode variants |
| `Models.swift` | `Person`, `PersonGroup`, `NoteEntry`, `EventPhoto`, `ImportantDate`, `FamilyMember` |
| `PeopleListView.swift` | Adaptive split view: people sidebar with search and birthday chips, detail pane, toolbar to tree/calendar/import |
| `PersonDetailView.swift` | Gradient header, Quick Info / Family / Notes tabs, memoriam toggle |
| `QuickInfoView.swift` | Preset details card, separate from notes |
| `FamilyTreeView.swift` | Relationship presets + generation logic, My Family Tree, per-person trees |
| `CalendarView.swift` | Month calendar of birthdays and important dates with avatar chips |
| `ImportContactsView.swift` | iOS contact picker + Facebook-export/CSV import with review and folder pick |
| `NotificationManager.swift` | Yearly 9 AM reminders for birthdays and dates |
| `NotesTimelineView.swift` | Notes timeline, photo grid, viewer |
| `NoteComposerView.swift` | Note editor: date, location, text, dictation, photos |
| `SpeechTranscriber.swift` | Live speech-to-text engine |
| `SettingsView.swift` | Reminders toggle, App Lock setup |
| `AppLockView.swift` | PIN pad, Face ID/Touch ID, lock screen |
| `KeychainHelper.swift` | Secure PIN storage |
| `AboutView.swift` | Version info, app icon color picker |
| `PersonEditorView.swift` | Add/edit person: photo, folder, relationship, family members, all fields |
| `GroupsManagerView.swift` | Folder management |
| `Utilities.swift` | Avatar view, info rows, image compression, date helpers |

## Using the app

- **＋ menu** adds a person or imports contacts; **tree** opens your family tree; **calendar** shows everyone's dates; **folder** manages folders; **gear** opens Settings; the **logo** opens About and the app icon color picker.
- On a person: **Quick Info** for details, **Family** for their tree, **Notes** for the timeline.
- Set *Relationship to You* in Edit Person to grow your own tree; add named family members to grow theirs.

## Data & privacy

Everything lives in a local SwiftData database, synced to your own iCloud account via CloudKit. Apple, not Memento, is the only place your data goes. The contacts picker only hands over people you explicitly select. Deleting the app deletes everything.

## Ideas for later

Camera capture, speaker labels in transcripts, linking tree nodes as explicit parent/child pairs, and export/backup. Happy to add any of these.
