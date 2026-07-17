---
name: verify
description: Build, launch and observe Memento to verify UI changes end-to-end (iOS Simulator screenshots; Mac wrapper install; debug launch args)
---

# Verifying Memento changes

## Build

Scheme `Memento`, project `Memento.xcodeproj`. Destinations (ids from
`xcodebuild -showdestinations`; the quoted "Designed for [iPad,iPhone]"
variant string breaks shell parsing — use `id=`):

- My Mac (Designed for iPad): `-destination 'id=<mac-udid>'` → product in
  `DerivedData/Memento-*/Build/Products/Debug-iphoneos/Memento.app`
- iPad/iPhone Simulator: `-destination 'id=<sim-udid>'` → `Debug-iphonesimulator/`

## Observe on the iOS Simulator (preferred — no TCC needed)

`screencapture` and AppleScript/System Events are TCC-blocked for shell
sessions on this Mac (they hang or fail), so drive verification on the
Simulator instead; `simctl io booted screenshot` needs no permissions.
Use an iPad simulator — the Mac build is the unmodified iPad app, so the
split-view/selection idiom matches.

```bash
xcrun simctl boot <udid> && xcrun simctl bootstatus <udid>
xcrun simctl install <udid> <path>/Debug-iphonesimulator/Memento.app
xcrun simctl launch <udid> brickcedar.Memento --stress-seed 60   # debug builds only
xcrun simctl io <udid> screenshot /tmp/shot.png
xcrun simctl spawn <udid> log show --last 3m --predicate 'subsystem == "brickcedar.Memento"'
```

First launch with seeding renders a blank screen for ~10s — screenshot
again a few seconds later before concluding anything is broken.

There is no tap injection (no simctl tap, no cliclick/idb installed). For
flows that need interaction, add temporary `#if DEBUG` launch-argument
probes (pattern: `--ui-probe <name>` checked in a `.task`, driving the
same @State/model paths a tap would) on a throwaway local branch — never
merge probe code. Log probe outcomes via `Logger(subsystem:
"brickcedar.Memento", category: "probe")` when screenshots aren't enough.

## Run on this Mac (Designed for iPad)

A raw `Debug-iphoneos/Memento.app` won't `open` ("incorrect executable
format"). It needs the wrapper-bundle shape, and after swapping the inner
bundle the old registration goes stale ("Launchd job spawn failed") —
recreate and re-register:

```bash
rm -rf /Applications/Memento.app
mkdir -p /Applications/Memento.app/Wrapper
cp -R <path>/Debug-iphoneos/Memento.app /Applications/Memento.app/Wrapper/
ln -s Wrapper/Memento.app /Applications/Memento.app/WrappedBundle
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Memento.app
open /Applications/Memento.app --args --stress-seed 60
```

The Mac app's screen can't be captured from here (TCC); confirm behavior
via `/usr/bin/log show --predicate 'subsystem == "brickcedar.Memento"'`
(full path — the user's zsh profile defines a `log` function that shadows
the system tool and fails with "too many arguments").

Reading the app container (`~/Library/Containers/brickcedar.Memento`)
from the shell hangs on TCC — don't try to inspect the SwiftData store
directly; go through the app.

## Gotchas

- After touching `Models.swift`, actually launch the app — CloudKit schema
  validation only happens when the ModelContainer is constructed (see CLAUDE.md).
- `--stress-seed N` / StressSeeder is DEBUG-only and idempotent (marker
  person "Stress 001 Aegean Papadopoulos").
