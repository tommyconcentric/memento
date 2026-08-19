# App Store submission pack

Everything needed to publish Memento to the App Store (iPhone + iPad) and make it available on the Mac App Store as an *iPhone & iPad App on Apple Silicon*. This file holds the listing copy to paste into App Store Connect and the checklist of steps only a human with the developer account can do.

## Repo pre-flight (verified 2026-07-24)

- **Release build:** compiles clean in the Release configuration: zero warnings, zero errors on a full *clean* build (re-verified 2026-08-14 for 1.1; incremental builds hide compiler diagnostics, so always judge from a clean build).
- **No dev tooling in the shipping binary:** `StressSeeder` and the `--ui-probe` verification hooks are `#if DEBUG` only. Both are confirmed absent from the Release build's strings.
- **Version:** `MARKETING_VERSION 1.1`, `CURRENT_PROJECT_VERSION 3` (bump the build number for every upload).
- **Deployment target:** iOS 17.0 (a stray project-level 26.5 default is overridden by the target; effective value is 17.0).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` is set, so there is no per-upload encryption prompt.
- **Category:** Productivity. **Bundle id:** `brickcedar.Memento`. **Team:** `7V79F7AY68`.
- **App Store Connect Apple ID:** `6791973402` (store name "Memento Vivere"). Direct links: version page `https://appstoreconnect.apple.com/apps/6791973402/distribution`, TestFlight `.../6791973402/testflight`. This is the number that belongs in `SettingsView.appStoreID`. See the last section.
- **Icon:** single 1024×1024 App Store icon present. **Entitlements:** iCloud + CloudKit (container `iCloud.brickcedar.Memento`).
- **Privacy:** `PrivacyInfo.xcprivacy` declares Product Interaction (anonymous usage counts, not linked, no tracking); `PRIVACY.md` and the App Store description below now match that (the description no longer claims "no analytics").

Still requires a human with the developer account: distribution certificate, CloudKit production schema deploy, App Store Connect record + metadata, screenshots, archive & upload, TestFlight, and submit. All of those are covered below.

---

## Version 1.1 status (August 2026)

Prepared through the console on 2026-08-15; only the on-device TestFlight pass and the final submission remain.

1. [x] **CloudKit schema deployed to Production** (2026-08-15). `CD_currentCity` (String) and `CD_didAutoPinAsPartner` (Int64) added to `CD_Person` directly in the Development schema via the console (the types mirror `CD_hometown`/`CD_isPinned`). Deploy Schema Changes then confirmed showing exactly those two fields, and both were verified present in the Production schema afterwards. (No debug-run materialization was needed; the console's manual field editor covered it.)
2. [x] **Archived & uploaded**: build **1.1 (3)** archived with `xcodebuild -allowProvisioningUpdates` and uploaded via `-exportArchive` with `destination: upload` (Xcode's saved account session authenticated). Processed in App Store Connect same day.
3. [x] **Version 1.1 created in App Store Connect**: release notes below pasted into What's New, build 3 attached, saved. Status: *Prepare for Submission*. Privacy label unchanged (city search is Apple-bound; nothing new collected).
4. [x] **TestFlight on real hardware**: the hardware pass was confirmed by the developer 2026-08-15 (camera capture, city autocomplete, typed dates, popovers, sync).
5. [x] **Submitted for review** 2026-08-15: iOS App 1.1 (3), "1 Item Submitted", review within ~48h, email on completion. Release follows approval.

**Release notes (paste as "What's New"):**

> Phone numbers now format themselves as you type, with the right spacing and brackets for each country. You get a flag when the number starts with a country code.
>
> You can now type birthdays and dates instead of only picking them: day and month, with or without a year. Dates across the app now show as DD/MM/YYYY, and you can change that in Settings → Dates.
>
> Hometown and a new "Currently based in" field suggest real cities as you type, using Apple Maps. That is the one new network feature. It only ever sends what you type in those two fields, and only to Apple.
>
> Sort your people by age or by city, hide folders or cities from the list, and change a profile photo right from the profile. Take a new photo or pick one you already have. Your partner gets a heart and sits pinned on top, Family leads the folder order, and tips now sit behind a tap of the ⓘ.

(The city-search sentence keeps PRIVACY.md's promise that network-behavior changes are called out in release notes.)

---

## Listing copy (paste into App Store Connect)

**Name:** Memento Vivere (plain "Memento" was taken at app creation, July 2026). The app itself still shows "Memento" on the Home Screen and in its UI. A store name and a bundle display name are allowed to differ.

**Subtitle** (30 chars max): `Remember everyone who matters`

**Category:** Productivity (secondary: Lifestyle)

**Description:**

> Memento is a personal CRM for the people in your life: friends, family, colleagues, and everyone in between.
>
> Keep a running notebook for each person: what you talked about, where you met, photos from the day. Glance at their quick-info card for the details you always forget: birthday, partner, kids, hobbies, how you met, their coffee order.
>
> TWO WORKSPACES
> Memento Personal for friends and family, Memento Business for clients and colleagues. One app, two separate address books, switched with a tap.
>
> A FAMILY TREE THAT DRAWS ITSELF
> Tell Memento who's your mother, brother, or grandson and your family tree grows on its own, drawn like a page from an old genealogy chart. Every person gets their own tree too, built from the family you record.
>
> NEVER MISS A DATE
> Birthdays and important dates appear on a beautiful calendar, fire gentle 9 AM reminders, and can sync into Apple Calendar as their own toggleable calendar.
>
> FAST TO FILL
> Import from your contacts: names, photos, birthdays, and every number, email and address come along. Dictate notes hands-free with on-device transcription.
>
> PRIVATE BY DESIGN
> No accounts, no ads, no tracking. Everything you write lives on your device and in your own private iCloud, never on our servers, and it syncs across your iPhone, iPad and Mac. The only thing Memento reports is an anonymous, opt-out count of app opens and contacts added, so we know how many people use it. Lock the app with a PIN and Face ID.

**Keywords** (100 chars max):
`personal crm,contacts,relationships,birthday,reminder,family tree,notes,networking,friends,people`

**Promotional text** (170 chars, editable without review):
`Remember the conversations, the birthdays, the coffee orders. Memento keeps the people in your life close, privately, on your own iCloud.`

**Support URL:** your choice. The GitHub repo works: `https://github.com/tommyconcentric/memento`

**Privacy Policy URL:** host `PRIVACY.md`. The simplest option is the raw GitHub page:
`https://github.com/tommyconcentric/memento/blob/main/PRIVACY.md`

**What's New (v1.0):** `First release.`

---

## Privacy nutrition label answers (App Store Connect → App Privacy)

- **Do you or your third-party partners collect data from this app?** → **Yes.**
- **Product Interaction** (under Usage Data) → collected, **used for Analytics**, **not linked to the user's identity**, **not used for tracking**.
  (This is the anonymous usage counters: a random install id plus daily app-open and contacts-created counts, sent to the app's public CloudKit database. See `UsageAnalytics.swift` and the disclosure in `PRIVACY.md`. Users can opt out in Settings.)
- Every other category → **not collected.** Everything the user creates stays on device / in their private CloudKit database, which the developer cannot access. No third-party SDKs.
- Tracking: **No.**

The bundled `PrivacyInfo.xcprivacy` matches these answers (no tracking; Product Interaction collected, not linked, analytics purpose; UserDefaults declared with reason CA92.1). **If collection ever changes again, the manifest, `PRIVACY.md` and this label must all be redone together.**

Also before release: in the CloudKit Console, deploy the public-database `UsagePing` schema (with queryable indexes on `pingDate` and `installID`) from Development to Production. Debug builds create it just-in-time in Development only, and TestFlight/App Store builds ping Production.

---

## App Review notes (paste into the Review Information box)

> Memento is fully usable without any account or sign-in. All data is stored locally and in the user's private iCloud (CloudKit). There is no developer server.
>
> To exercise the main features: add a person (+ button), set "Family Relationship to You" to see the auto-generated family tree (tree toolbar icon), add a birthday to see the calendar and reminders, and try Settings → Sync with Apple Calendar. Dictation (in a note) requires microphone + speech permissions. The optional app lock is under Settings → App Lock.

---

## Screenshot plan

Required sizes: 6.9" iPhone (1320×2868) and 13" iPad (2064×2752). Suggested five shots, taken with a handful of seeded people:

1. People list with pinned people and the Personal/Business badge
2. A person's profile: quick info card with starred contact and birthday countdown
3. My Family Tree (the engraved-chart look is the visual signature)
4. Important Dates calendar with avatars on the grid
5. A notes timeline with photos

Simulator: `xcrun simctl status_bar <device> override --time 9:41 --batteryLevel 100` before capturing.

---

## Checklist: things only you can do

**Accounts & certificates**
- [ ] Apple Developer Program membership active (paid) for team `7V79F7AY68`.
- [x] **Apple Distribution certificate exists** on this machine (`Apple Distribution: Ha Bao Trung Le (7V79F7AY68)`, verified 2026-07-25). Archiving and App Store export both work without further certificate setup.

**One-time Xcode capability check**
- [x] Signing & Capabilities → confirm iCloud (CloudKit, container `iCloud.brickcedar.Memento`) shows no errors, and add **Background Modes → Remote notifications** if the checkbox isn't already reflected. Verified 2026-07-26 from the exported App Store `.ipa` itself: iCloud/CloudKit entitlements and the `remote-notification` background mode are all present in the shipping package. (The optional Push Notifications capability remains unadded, which is fine for CloudKit pushes.)

**CloudKit: critical, easy to forget**
- [x] CloudKit Console (icloud.developer.apple.com) → container `iCloud.brickcedar.Memento` → **Deploy Schema Changes to Production**. Deployed and verified in Production 2026-07-26: all ten `CD_*` record types plus `UsagePing` with its queryable `pingDate`/`installID` indexes. (`CD_Project` had never materialized in Development, because no debug build had ever saved a `Project`, the stress seeder included. It had to be created first by saving a real record; a schema type only exists once a record of it has been saved.) **Redo this any time the SwiftData schema changes**. If a new `@Model` is added, save at least one record of it in a debug build first, or the type won't be in the schema to deploy. **⚠️ 1.1 needs this redone**. See "Version 1.1" above (`CD_currentCity`, `CD_didAutoPinAsPartner` on `CD_Person`).

**App Store Connect**
- [x] Create the app: bundle ID `brickcedar.Memento`, store name "Memento Vivere" (plain "Memento" was taken). iOS platform only. Mac availability comes from the "Make this app available on Mac" checkbox, not the macOS platform.
- [ ] Paste in the listing copy, keywords, URLs and privacy answers above.
- [ ] **Pricing & Availability → confirm "Make this app available on Mac"** (iPhone & iPad Apps on Apple Silicon Macs) is ON. That is the Mac App Store presence for this project. (A native Mac Catalyst app would be a separate future project.)
- [ ] Upload screenshots (iPhone 6.9" + iPad 13").
- [ ] Age rating questionnaire (all "None" → 4+).

**Build & submit**
- [ ] Xcode: Product → Archive → Distribute App → App Store Connect (or `xcodebuild archive` + `-exportArchive` with an `app-store` export options plist once the distribution cert exists).
- [ ] TestFlight the build on a real iPhone, iPad and a Mac first. Check especially: CloudKit sync between two devices, calendar sync end-to-end, dictation, app lock with a sheet open (the EventKit and lock code paths are flagged in CLAUDE.md as needing on-device verification).
- [ ] Submit for review.

**After the listing exists**
- [x] Put the numeric Apple ID of the app into `SettingsView.appStoreID` so "Rate Memento" deep-links to the review page (set to `6791973402`, 2026-07-26, and it ships with the first build).
- [ ] If the app name on the store ends up different, update the About screen copy if desired.

**Housekeeping per release**
- [ ] Bump `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build number) for every upload. (Done for 1.1 → 1.1 (3), 2026-08-14.)
