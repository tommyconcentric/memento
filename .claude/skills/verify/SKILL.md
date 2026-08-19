---
name: verify
description: Build, launch and observe Memento to verify UI changes end-to-end (iOS Simulator screenshots; Mac wrapper install; debug launch args)
---

# Verifying Memento changes

## Build

Scheme `Memento`, project `Memento.xcodeproj`. Destinations (ids from
`xcodebuild -showdestinations`; the quoted "Designed for [iPad,iPhone]"
variant string breaks shell parsing, so use `id=`):

- My Mac (Designed for iPad): `-destination 'id=<mac-udid>'` → product in
  `DerivedData/Memento-*/Build/Products/Debug-iphoneos/Memento.app`
- iPad/iPhone Simulator: `-destination 'id=<sim-udid>'` → `Debug-iphonesimulator/`

**The repo lives in a OneDrive-synced folder, and the file provider
re-stamps build products with `com.apple.fileprovider.fpfs#P`. Codesign
then fails with "resource fork, Finder information, or similar detritus
not allowed".** Simulator builds don't sign so they escape; any *signed*
build (Mac destination, device) must use `-derivedDataPath` outside the
synced tree, e.g. `/tmp/memento-dd`. (`xattr -cr` doesn't stick, because
the provider re-tags.)

## Observe on the iOS Simulator

`simctl io booted screenshot` needs no permissions. Use an iPad
simulator. The Mac build is the unmodified iPad app, so the
split-view/selection idiom matches.

`screencapture` and AppleScript/System Events also work from shell
sessions now (TCC granted 2026-07-26; an older note here claimed they
hang, but that note is stale). Safari has "Allow JavaScript from Apple
Events" enabled, so `osascript … do JavaScript` can drive and read web
pages; screenshot the screen with `screencapture -x /tmp/x.png` and Read
the file.

```bash
xcrun simctl boot <udid> && xcrun simctl bootstatus <udid>
xcrun simctl install <udid> <path>/Debug-iphonesimulator/Memento.app
xcrun simctl launch <udid> brickcedar.Memento --stress-seed 60   # debug builds only
xcrun simctl io <udid> screenshot /tmp/shot.png
xcrun simctl spawn <udid> log show --last 3m --predicate 'subsystem == "brickcedar.Memento"'
```

First launch with seeding renders a blank screen for ~10s. Screenshot
again a few seconds later before concluding anything is broken.

There is no tap injection (no simctl tap, no cliclick/idb installed). For
flows that need interaction, add temporary `#if DEBUG` launch-argument
probes (pattern: `--ui-probe <name>` checked in a `.task`, driving the
same @State/model paths a tap would) on a throwaway local branch. Never
merge probe code. Log probe outcomes via `Logger(subsystem:
"brickcedar.Memento", category: "probe")` when screenshots aren't enough.

## Run on this Mac (Designed for iPad)

A raw `Debug-iphoneos/Memento.app` won't `open` ("incorrect executable
format"). It needs the wrapper-bundle shape. After swapping the inner
bundle the old registration goes stale ("Launchd job spawn failed"), so
recreate and re-register:

```bash
mkdir -p ~/Applications/Memento.app/Wrapper
cp -R <path>/Debug-iphoneos/Memento.app ~/Applications/Memento.app/Wrapper/
ln -sf Wrapper/Memento.app ~/Applications/Memento.app/WrappedBundle
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/Memento.app
open ~/Applications/Memento.app --args --stress-seed 60
```

Use `~/Applications`. Auto-mode permission rules block writes to
`/Applications` (the user's own install lives there; leave it alone).

**`open --args` only reaches a freshly spawned process.** If any Memento
instance is already running, `open` foregrounds it and the args go
nowhere. Run `tell application "Memento" to quit`, wait, then `open`.
Confirm with `ps -o lstart=,command= -p <pid> -ww` that the start time is
now and the args are on the command line.

Confirm behavior via
`/usr/bin/log show --predicate 'subsystem == "brickcedar.Memento"'`
(use the full path: the user's zsh profile defines a `log` function that
shadows the system tool and fails with "too many arguments").

Reading the app container (`~/Library/Containers/brickcedar.Memento`)
from the shell hangs on TCC. Don't try to inspect the SwiftData store
directly; go through the app.

## Gotchas

- After touching `Models.swift`, actually launch the app. CloudKit schema
  validation only happens when the ModelContainer is constructed (see CLAUDE.md).
- `--stress-seed N` / StressSeeder is DEBUG-only and idempotent (marker
  person "Stress 001 Aegean Papadopoulos").
- A CloudKit record type only exists once a record of that model has
  actually been *saved* by a debug build. `CD_Project` was missing from
  the Development schema until 2026-07-26 because nothing (not even the
  stress seeder) had ever saved a `Project`. After adding a `@Model`,
  save one record of it before any "Deploy Schema Changes to Production"
  (see `docs/app-store-submission.md`).
