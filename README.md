<p align="center"><img src="assets/logo.png" width="128" height="128" alt="Cut"></p>

<h1 align="center">Cut</h1>

<p align="center">Cut and Paste files in Mac. Finally.</p>

Select files, press ⌘X, open another folder, press ⌘V. Done.

Cut turns ⌘X into ⌘C and the next ⌘V into ⌥⌘V, Finder's own move. Finder does the work, so ⌘Z undoes it
and Cut never touches your files. Rename and search fields still cut text. Works in ForkLift too.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadawais/cut/main/scripts/get.sh | bash
```

Then allow it in **System Settings → Privacy & Security → Accessibility**.

Or build it: `./scripts/make-cert.sh && ./scripts/install.sh` (Xcode Command Line Tools).

## Private

- No network. The kernel blocks it.
- Sees keys only while Finder or ForkLift is in front.
- One permission. No updater, no analytics, no dependencies.

## Develop

```bash
./scripts/test.sh
./scripts/build.sh
```

Tag `vX.Y.Z` to release.

MIT
