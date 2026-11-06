<p align="center"><img src="assets/logo.png" width="128" height="128" alt="Cut"></p>

<h1 align="center">Cut</h1>

<p align="center">Cut and paste files in Finder with ⌘X and ⌘V. Private, no network, one permission.</p>

Select files in Finder, press **⌘X**, go to another folder, press **⌘V**: the files move. Like Windows and
Linux. About 850 lines of Swift, no dependencies, nothing that phones home.

## How it works

Finder can already move files: copy them (⌘C), then **⌥⌘V** ("Move Item Here"). Cut turns your ⌘X into ⌘C
and, while that copy is still on the clipboard, your next ⌘V into ⌥⌘V. Finder does the move, so Cut never
touches a file, and **⌘Z** in Finder undoes the move as usual. Until you paste, nothing happens to the files.

- One move per cut: the next ⌘V pastes a copy again, like Windows.
- Copy anything else after a cut and ⌘V is a normal paste again.
- In rename fields, the search field and Go to Folder, ⌘X and ⌘V cut and paste text as always.
- Works in **Finder** and **ForkLift**. A cut made in one moves in the other.
- A short sound confirms a cut (alert volume; off with "Play user interface sound effects" or in Settings).
- The menu bar icon fills in while files are cut: Finder can't dim them, so this shows a cut is waiting.
  Its menu says how many items and can cancel the cut.

## Private by design

- **No network.** At launch Cut puts itself in a kernel sandbox profile that refuses every IP connection and
  DNS lookup, and that it can't lift. Not a promise: the kernel enforces it.
- **Keystrokes only in Finder and ForkLift.** Cut's key listener is switched off whenever another app is in
  front, so macOS doesn't hand it a single key typed anywhere else. In Finder it acts only on ⌘X and ⌘V and
  logs nothing about keys.
- **One permission**, Accessibility: to see ⌘X / ⌘V in Finder, press ⌘C / ⌥⌘V in their place, and check
  whether a text field has focus.
- **No updater, analytics or crash reports.** No dependencies. Settings live in
  `~/Library/Preferences/com.ahmadawais.cut.plist`; nothing else is stored.

## Install

Apple charges $99 a year to notarize apps. Cut skips that: the app is signed on your Mac, by you, and it
never carries the download flag Gatekeeper checks. Two ways, same result.

**1. Download the release (no Xcode):**

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadawais/cut/main/scripts/get.sh | bash
```

[`get.sh`](scripts/get.sh) downloads the latest [release](https://github.com/ahmadawais/cut/releases),
checks its SHA-256 sums, signs it with a certificate it creates in your login keychain (once; macOS asks for
your password), and installs it to `/Applications`. Run it again to update. With the
[GitHub CLI](https://cli.github.com) signed in, it also checks the build provenance: proof the zip was built by
this repo's [release workflow](.github/workflows/release.yml) from the tagged commit, not uploaded by hand.
Check it yourself any time with `gh attestation verify Cut.zip --repo ahmadawais/cut`.

Prefer reading before running? `curl -fsSLO https://raw.githubusercontent.com/ahmadawais/cut/main/scripts/get.sh`,
read it, then `bash get.sh`.

**2. Build from source** (Xcode Command Line Tools: `xcode-select --install`):

```bash
git clone https://github.com/ahmadawais/cut.git && cd cut
./scripts/make-cert.sh        # once per Mac: the local signing certificate
./scripts/install.sh          # builds, signs, copies to /Applications, launches
```

Then allow it once: **System Settings → Privacy & Security → Accessibility → Cut** (macOS 27: **Device
Control and Data Access**). Cut relaunches by itself.

**Why the certificate?** macOS ties the Accessibility permission to the app's signature. The local certificate
makes that signature the same on every update, so the permission stays. Its private key never leaves your
login keychain and only `codesign` may use it. Skip it (`LOCAL_ADHOC=1` for `get.sh`) and Cut is signed
ad-hoc: it works the same, but you turn it off and on again in that list after each update.

## Settings

- **General**: Accessibility status, play sound when cutting, launch at login, menu bar icon.
- **Shortcuts**: what ⌘X and ⌘V do, and which file managers are installed.
- **Privacy**: whether the network block is active, and what Cut sees and stores.

Hid the menu bar icon? Open Cut again from Spotlight to get to Settings.

## Limits

- Cut files aren't dimmed in Finder: no app can change how Finder draws them.
- Edit → Paste in Finder's menu still copies; the move happens on ⌘V. (⌥ turns that menu item into
  Move Item Here.)
- Pasting into a subfolder expanded inside its parent (list view), or into a column whose parent is a tag,
  fails in Finder itself, with or without Cut.

## Why not the App Sandbox

The App Sandbox blocks the Accessibility API (`deny mach-lookup com.apple.axserver`), which Cut needs to tell
the file list from a rename field. Cut uses a narrower kernel sandbox instead: everything is allowed except
networking (`Sources/CutKit/NoNetwork.swift`, a seven-line profile). `NoNetworkTests` run `curl`, `nc` and
`host` under that exact profile and check that they fail. **Settings → Privacy** shows whether it is active.

## Build & test

```bash
./scripts/test.sh             # Swift Testing: cut logic, controller, event tap, layout, prefs, settings renders
./scripts/build.sh            # build/Cut.app
git tag vX.Y.Z && git push --tags   # CI: test, universal build, provenance, GitHub release
```

Settings renders land in `.build/renders/` for review.

```
Sources/Cut/main.swift         app entry
Sources/CutKit/
  Cutter.swift                 when ⌘X cuts and ⌘V moves: a small state machine, pure and unit-tested
  Controller.swift             key in → verdict → key out, clipboard watching
  Keys.swift                   event tap (on only in file managers), keys sent, keyboard layout
  Focus.swift                  text-field check and the Accessibility permission
  NoNetwork.swift              kernel sandbox profile: no networking
  Prefs.swift                  settings and the cut sound
  Settings.swift               SwiftUI settings window
  AppDelegate.swift            menu bar, permission, front app
Sources/CNoNetwork/             10 lines of C: calls sandbox_init from <sandbox.h>
```

## License

MIT.
