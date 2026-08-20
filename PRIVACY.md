# Memento Privacy Policy

_Last updated: August 14, 2026_

Memento is a personal-CRM app for remembering the people in your life. It is built so that **your data belongs to you and never reaches us**.

## What we collect

**Nothing you create.** Memento has no accounts, no advertising, no third-party SDKs, and no servers of our own. We cannot see, access, or recover anything you put in the app: not a name, note, photo, date, or relationship.

The only thing Memento reports is **anonymous usage statistics**: once a day it can send a random install identifier (a coin-flip ID created on first launch, tied to nothing about you), the number of times the app was opened that day, the number of contacts created that day, the app version, and the device type (iPhone/iPad/Mac). That's the entire list. These counters exist so the developer can answer "how many people use Memento?" The counters can't identify you, and we never use them for tracking or advertising. (Typing in the two city fields also queries Apple Maps directly. See "City search" below. Those queries go to Apple, and we never see them either.)

You can turn this off any time in **Settings → Anonymous Usage Statistics**; switching it off also deletes the counts your device already sent. The counters are stored in the app's public CloudKit database (Apple infrastructure, no third parties).

## Where your data lives

Everything you enter (people, notes, photos, dates, family relationships) is stored on your device and, if you're signed into iCloud, synced through **your own private iCloud database (CloudKit)**. That sync is between your devices and Apple; the developer has no access to it. Apple's handling of iCloud data is covered by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

The optional app lock PIN is stored only in your device's Keychain and never leaves the device.

## City search (Apple Maps)

When you type in the **Hometown** or **Currently based in** fields, Memento asks Apple Maps for matching city names so you can pick one. Only what you type in those two fields is sent, it goes to **Apple's Maps servers** (never to us or any third party), and nothing about it is stored outside your own data. Apple's handling of Maps queries is covered by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/). If you're offline, the fields simply work as plain text. This and your own iCloud sync are the only network traffic in the app.

## Device permissions Memento may ask for

- **Microphone & Speech Recognition**: only when you use dictation to compose a note. Transcription uses Apple's speech recognition (on-device when your device supports it). We never receive the audio or the transcript.
- **Calendars**: only if you turn on Apple Calendar sync, so Memento can maintain its "Memento" calendar of birthdays and important dates on your device.
- **Contacts**: Memento uses the system contact picker, which shares only the specific contacts you select. It never reads your address book.
- **Photos**: Memento uses the system photo picker, which shares only the photos you choose.
- **Camera**: only if you choose "Take Photo" for a profile picture. The photo goes straight into Memento on your device (and your own iCloud sync). We never see it.
- **Face ID / Touch ID**: only if you turn it on for the optional app lock. Biometric data never leaves the device and is handled entirely by the system.
- **Notifications**: only if you turn on birthday and date reminders. These are local notifications scheduled on your device.

## Data deletion

Delete a person or note in the app and it's deleted from your devices and your private iCloud database. Deleting the app and removing its iCloud data (Settings → your name → iCloud → Manage Account Storage) removes everything.

## Children

Memento is not directed at children and collects no personal data from anyone; the anonymous usage counters above contain nothing that could identify any person.

## Changes

If Memento's privacy practices ever change, this policy will be updated and the change called out in the App Store release notes before it ships. Changes so far: **August 2026**. We added Apple Maps city search (the "City search" section above). It's the app's first network feature beyond your own iCloud sync.

## Contact

Questions or concerns: **tommyle@outlook.com**
