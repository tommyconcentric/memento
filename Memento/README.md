# Memento

A personal iOS app for remembering the people in your life — friends, colleagues and family. Keep a running notebook per person, a quick-reference card of details, auto-generated family trees, a calendar of everyone's important dates, and voice-powered note capture.

Built with SwiftUI + SwiftData. No third-party dependencies. All records stay on your device; the only network calls are the ones you trigger with Smart Capture's AI analysis.

## Features

- **People with profile photos** — colored-initials avatars when no photo is set.
- **Folders** — Close Friends, Friends, Work Colleagues and Family are created for you; add, rename, reorder or delete folders freely.
- **Quick Info card (separate from notes)** — relationship to you, birthday (with age and countdown), partner, children, family, work, hobbies, hometown, how you met, food & drink, **phone, email and address**, plus custom important dates.
- **Family trees, auto-generated** — label each person's *Relationship to You* (mother, brother, grandson…) and the **tree icon** on the main screen draws your family tree from those labels, placed by generation. Every person also gets their own **Family tab**: their tree builds itself from their partner, children and any named family members you add. Tree nodes link to profiles when the name matches someone in Memento. The tree looks the part — leafy olive lanes for older generations, warm bark below, a trunk that thickens toward the roots — and on **My Family Tree you can hold a person and drag them to another row**, then pick their new label. Family and partner fields can **link to existing profiles** (tap the magnifier or type an exact name) and the inverse relationship is written to the other person automatically, so it shows both ways. Indirect relations get a plain-English line like *"Your father's brother's daughter."* Profile photos now open a **circular cropper** (pan and pinch, with everything outside the circle darkened) before saving.
- **Import contacts** — the **＋ menu → Import Contacts** offers two honest routes: **iOS Contacts** opens Apple's picker so you choose exactly who to import (names, photos, numbers, emails, addresses and birthdays come along — and since WhatsApp uses your phone's address book, this covers your WhatsApp people). **Facebook export / CSV**: Facebook shut down its friends API years ago, so instead import the friends JSON from Facebook's *Download Your Information* (names only — Facebook doesn't export friends' birthdays) or any CSV with name, birthday, phone, email, address columns. Either way you review the list, untick anyone, and pick the folder before saving. Duplicates are flagged.
- **Important-dates calendar** — the **calendar icon** shows a month view where each birthday, anniversary or custom date appears as that person's photo (or initials circle) on the day. Tap a day for the full list with "turns 34" and profile links.
- **Birthday & date reminders** — flip the toggle in Settings for a 9 AM notification on birthdays and important dates (skips people marked in memoriam; iOS caps scheduled notifications, so the nearest 60 dates are kept and refreshed as data changes).
- **Running notes timeline** — notes with date, location and event photos with captions.
- **Dictation** — tap the mic in the note editor and speak.
- **Smart Capture (AI)** — record a conversation, on-device transcription, then Claude drafts a note and suggests profile updates you approve one by one.
- **In Memoriam** — mark someone as deceased; their profile grays and birthday countdowns/reminders pause.
- **Made for iPhone, iPad and Mac** — the layout adapts: a stack on iPhone, a split view (people list beside the open profile) on iPad and Mac. Soft continuous-corner cards, a pill tab bar, rounded display type and a sun-motif header keep the UI clean and modern.
- **Mamma Mia palette** — Aegean blues, whitewash, bougainvillea, olive, terracotta and gold; deep night-sea dark mode.

## Logo & app icon

The mark is a small tree whose canopy is three connected people-nodes — family tree meets relationship graph — with the crown node in island gold. `AppLogo.swift` draws it in-app (sidebar, empty states); `AppIcon-1024.png` is the ready-made icon (open Assets.xcassets → AppIcon and drop it in the 1024 slot); `memento-logo.svg` is the source for anything else.

The design language got a refresh too: New York serif display type, a clean rectangular hero panel, circular portraits with a matching circular crop, underline tabs, hairline cards, journal-style date rails on notes, and a hand-drawn line icon set instead of emoji.

## Requirements

- A Mac with **Xcode 15 or newer**
- **iOS 17.0+ / iPadOS 17.0+** deployment target (SwiftData); runs on Mac via **Mac Catalyst**
- iPhone, iPad, Mac or the Simulator (speech recognition is far more reliable on real hardware)
- For Smart Capture's AI analysis only: internet + an **Anthropic API key**

## Setup (about 5 minutes)

1. Xcode → **File → New → Project…** → **iOS → App**.
2. Name it **Memento**, Interface **SwiftUI**, Language **Swift**. Leave Core Data and tests unchecked.
3. Delete the two generated Swift files (`MementoApp.swift` and `ContentView.swift`) — "Move to Trash".
4. Drag all the `.swift` files from this folder into the project navigator. Tick **"Copy items if needed"**, target **Memento** checked.
5. Project → target **Memento** → General → **Minimum Deployments: iOS 17.0**.
6. Target → **Info** tab → add two keys (required, or dictation/Smart Capture will crash):
   - `Privacy - Microphone Usage Description` → `Memento uses the microphone to dictate notes and capture conversations.`
   - `Privacy - Speech Recognition Usage Description` → `Memento transcribes your recordings into notes.`
   (The contacts picker and local notifications need no Info.plist entries — the picker never reads your address book without you choosing people, and notification permission is asked in-app.)
7. Run.

> **Upgrading from an earlier build?** Delete the old app from the device/simulator first — the data model gained family trees, relationship labels and addresses.

## iPad & Mac

The interface is adaptive out of the box — no extra code needed, just destinations:

- **iPad:** already included. In the target's General tab, Supported Destinations lists iPhone and iPad by default; pick an iPad simulator and run. You'll get the split view with the people list on the left and the open profile on the right.
- **Mac:** in Supported Destinations click **+** and add **Mac (Mac Catalyst)**. For the most Mac-like controls, select that destination row and tick **"Optimize Interface for Mac"**. Dictation, Smart Capture, the contacts picker, notifications and the Keychain all run through the same code.
- **Zero-setup alternative** on Apple Silicon Macs: add **Mac (Designed for iPad)** instead — the unmodified iPad app runs as a window.

## Setting up Smart Capture

1. Create an API key at **console.anthropic.com** (billed separately from any Claude.ai subscription).
2. Tap the **gear icon** in Memento and paste the key — it's stored in the device **Keychain**; requests go straight from your phone to Anthropic and standard API rates apply.
3. The model is set in `ClaudeService.swift` (`claude-sonnet-4-6`); current model names: https://docs.claude.com/en/api/overview.

Only the transcript text plus that person's existing profile summary leave your phone, and only when you tap Analyze. Recording-consent laws vary by place — make sure everyone is happy to be recorded. Don't distribute your build with your API key inside it.

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
| `NotesTimelineView.swift` | Notes timeline, photo grid, viewer, Smart Capture entry |
| `NoteComposerView.swift` | Note editor: date, location, text, dictation, photos |
| `SmartCaptureView.swift` | Record → transcribe → Claude analysis → review-and-approve |
| `SpeechTranscriber.swift` | Live speech-to-text engine |
| `ClaudeService.swift` | Anthropic Messages API call and parsing |
| `SettingsView.swift` | API key, reminders toggle, explainers |
| `KeychainHelper.swift` | Secure key storage |
| `PersonEditorView.swift` | Add/edit person: photo, folder, relationship, family members, all fields |
| `GroupsManagerView.swift` | Folder management |
| `Utilities.swift` | Avatar view, info rows, image compression, date helpers |

## Using the app

- **＋ menu** adds a person or imports contacts; **tree** opens your family tree; **calendar** shows everyone's dates; **folder** manages folders; **gear** opens Settings.
- On a person: **Quick Info** for details, **Family** for their tree, **Notes** for the timeline.
- Set *Relationship to You* in Edit Person to grow your own tree; add named family members to grow theirs.

## Data & privacy

Everything lives in a local SwiftData database; the API key lives in the Keychain. The contacts picker only hands over people you explicitly select. Deleting the app deletes everything.

## Ideas for later

iCloud sync, camera capture, speaker labels in transcripts, linking tree nodes as explicit parent/child pairs, and export/backup. Happy to add any of these.
