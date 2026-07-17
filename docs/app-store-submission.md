# App Store submission pack

Everything needed to publish Memento to the App Store (iPhone + iPad) and make it available on the Mac App Store as an *iPhone & iPad App on Apple Silicon*. The repo side is done (privacy manifest, compliance keys, category, background mode); this file holds the listing copy to paste into App Store Connect and the checklist of steps only a human with the developer account can do.

---

## Listing copy (paste into App Store Connect)

**Name:** Memento Vivere (plain "Memento" was taken at app creation, July 2026). The app itself still shows "Memento" on the Home Screen and in its UI — a store name and bundle display name are allowed to differ.

**Subtitle** (30 chars max): `Remember everyone who matters`

**Category:** Productivity (secondary: Lifestyle)

**Description:**

> Memento is a personal CRM for the people in your life — friends, family, colleagues, and everyone in between.
>
> Keep a running notebook for each person: what you talked about, where you met, photos from the day. Glance at their quick-info card for the details you always forget — birthday, partner, kids, hobbies, how you met, their coffee order.
>
> TWO WORKSPACES
> Memento Personal for friends and family, Memento Business for clients and colleagues — one app, two clean address books, switched with a tap.
>
> A FAMILY TREE THAT DRAWS ITSELF
> Tell Memento who's your mother, brother, or grandson and your family tree grows on its own, drawn like a page from an old genealogy chart. Every person gets their own tree too, built from the family you record.
>
> NEVER MISS A DATE
> Birthdays and important dates appear on a beautiful calendar, fire gentle 9 AM reminders, and can sync into Apple Calendar as their own toggleable calendar.
>
> FAST TO FILL
> Import from your contacts — names, photos, birthdays, and every number, email and address come along. Dictate notes hands-free with on-device transcription.
>
> PRIVATE BY DESIGN
> No accounts, no analytics, no servers. Everything lives on your device and in your own private iCloud, synced across your iPhone, iPad and Mac. Lock the app with a PIN and Face ID.

**Keywords** (100 chars max):
`personal crm,contacts,relationships,birthday,reminder,family tree,notes,networking,friends,people`

**Promotional text** (170 chars, editable without review):
`Remember the conversations, the birthdays, the coffee orders. Memento keeps the people in your life close — privately, on your own iCloud.`

**Support URL:** your choice — the GitHub repo works: `https://github.com/tommyconcentric/memento`

**Privacy Policy URL:** host `PRIVACY.md` — simplest is the raw GitHub page:
`https://github.com/tommyconcentric/memento/blob/main/PRIVACY.md`

**What's New (v1.0):** `First release.`

---

## Privacy nutrition label answers (App Store Connect → App Privacy)

- **Do you or your third-party partners collect data from this app?** → **No, we do not collect data from this app.**
  (Everything stays on device / in the user's private CloudKit database, which the developer cannot access — that qualifies as "not collected" under Apple's definitions. No analytics, no third-party SDKs.)
- Tracking: **No.**

The bundled `PrivacyInfo.xcprivacy` matches these answers (no tracking, no collected data, UserDefaults declared with reason CA92.1). **If any analytics or third-party SDK is ever added, both the manifest and the nutrition label must be redone.**

---

## App Review notes (paste into the Review Information box)

> Memento is fully usable without any account or sign-in. All data is stored locally and in the user's private iCloud (CloudKit) — there is no developer server.
>
> To exercise the main features: add a person (+ button), set "Family Relationship to You" to see the auto-generated family tree (tree toolbar icon), add a birthday to see the calendar and reminders, and try Settings → Sync with Apple Calendar. Dictation (in a note) requires microphone + speech permissions. The optional app lock is under Settings → App Lock.

---

## Screenshot plan

Required sizes: 6.9" iPhone (1320×2868) and 13" iPad (2064×2752). Suggested five shots, taken with a handful of seeded people:

1. People list with pinned people and the Personal/Business badge
2. A person's profile — quick info card with starred contact and birthday countdown
3. My Family Tree (the engraved-chart look is the visual signature)
4. Important Dates calendar with avatars on the grid
5. A notes timeline with photos

Simulator: `xcrun simctl status_bar <device> override --time 9:41 --batteryLevel 100` before capturing.

---

## Checklist — things only you can do

**Accounts & certificates**
- [ ] Apple Developer Program membership active (paid) for team `7V79F7AY68`.
- [ ] In Xcode: Settings → Accounts → Manage Certificates → create an **Apple Distribution** certificate (only Apple Development exists on this machine today).

**One-time Xcode capability check**
- [ ] Signing & Capabilities → confirm iCloud (CloudKit, container `iCloud.brickcedar.Memento`) shows no errors, and add **Background Modes → Remote notifications** if the checkbox isn't already reflected (the Info.plist key is now set; the capability UI should agree). Optionally add the Push Notifications capability — recommended for CloudKit change pushes.

**CloudKit — critical, easy to forget**
- [ ] CloudKit Console (icloud.developer.apple.com) → container `iCloud.brickcedar.Memento` → **Deploy Schema Changes to Production**. A TestFlight/App Store build talks to the *production* CloudKit environment; without this, sync silently fails for release users. Redo this any time the SwiftData schema changes.

**App Store Connect**
- [x] Create the app: bundle ID `brickcedar.Memento`, store name "Memento Vivere" (plain "Memento" was taken). iOS platform only — Mac availability comes from the "Make this app available on Mac" checkbox, not the macOS platform.
- [ ] Paste in the listing copy, keywords, URLs and privacy answers above.
- [ ] **Pricing & Availability → confirm "Make this app available on Mac"** (iPhone & iPad Apps on Apple Silicon Macs) is ON — that's the Mac App Store presence for this project. (A native Mac Catalyst app would be a separate future project.)
- [ ] Upload screenshots (iPhone 6.9" + iPad 13").
- [ ] Age rating questionnaire (all "None" → 4+).

**Build & submit**
- [ ] Xcode: Product → Archive → Distribute App → App Store Connect (or `xcodebuild archive` + `-exportArchive` with an `app-store` export options plist once the distribution cert exists).
- [ ] TestFlight the build on a real iPhone, iPad and a Mac first — especially: CloudKit sync between two devices, calendar sync end-to-end, dictation, app lock with a sheet open (the EventKit and lock code paths are flagged in CLAUDE.md as needing on-device verification).
- [ ] Submit for review.

**After the listing exists**
- [ ] Put the numeric Apple ID of the app into `SettingsView.appStoreID` so "Rate Memento" deep-links to the review page, and ship it in the next build.
- [ ] If the app name on the store ends up different, update the About screen copy if desired.

**Housekeeping per release**
- [ ] Bump `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build number) for every upload.
