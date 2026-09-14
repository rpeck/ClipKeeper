# ClipKeeper

A native Mac clipboard manager. Everything you copy lands in a shelf that
slides in from the right edge of the screen. Your hands stay on the keyboard.

## What it does

- **Captures every copy.** Text, Markdown, code, rich text, images, links, colors, and files.
- **Renders each type.** Markdown is rendered. Code is syntax-highlighted. Images show as thumbnails. Links show the page title and favicon. Colors show a swatch.
- **Keyboard first.** ⌘⇧V opens the shelf. Arrow keys or ⌃N ⌃P move. ← → or ⌃B ⌃F switch sets. Return pastes. Esc closes.
- **Collections.** History fills on every copy. Named collections hold clips you put there on purpose.
- **Never lossy.** Editing text or cropping an image makes a new clip. The original stays until you delete it.
- **Paste as… and Save as…** keep the original format by default and offer conversions.

## Build

Requirements: macOS 15, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
scripts/build.sh run        # debug build, then launch
scripts/build.sh test       # unit tests
scripts/build.sh install    # release build into /Applications
```

The script generates the Xcode project from `project.yml`, draws the app icon
with `scripts/make-icon.swift`, and builds with `xcodebuild`. It sets
`DEVELOPER_DIR` to Xcode.app, so no global `xcode-select` change is needed.

`Package.swift` also builds the same sources with SwiftPM:

```sh
swift build
swift test
```

The SwiftPM build produces a bare executable, not an app bundle. Use it for
compile checks and tests.

## Keys

All keys are changeable in Settings › Keys. Defaults:

| Key | Action |
|---|---|
| ⌘⇧V | Open or close the shelf (global) |
| ↑ ↓ ⌃N ⌃P | Move the selection |
| ← → ⌃B ⌃F ⇥ ⇧⇥ | Switch between History and collections |
| ⏎ | Paste the selected clip |
| ⇧⏎ | Paste as plain text |
| ⌥⏎ | Copy to the clipboard without a paste |
| ⌘⇧⏎ | Paste as… |
| ⌘1 – ⌘9 | Paste slot 1 to 9 |
| ␣ | Full preview |
| ⌘E | Edit text, or crop an image |
| ⌘S | Save as… |
| ⌘P | Pin or unpin |
| ⌘M | Move to a collection |
| ⌘D | Duplicate |
| ⌘N | New collection |
| ⌘⌫ | Delete (asks first) |
| ⌘⇧A | Select mode; ⌘A selects all; ⇧↑ ⇧↓ extend |
| ⎋ | Close |

When the search field holds text, ← → and ⌫ edit the text. ⇥ and ⇧⇥ still switch sets.

## Permissions

- **Accessibility.** ClipKeeper presses ⌘V on your behalf to paste into the front app. Without the permission, Return copies the clip and closes the shelf, and you press ⌘V.
- **Network.** Copied links get their page title and favicon from the link's site. Turn this off in Settings › Privacy.

## Code signing

The Accessibility permission is tied to the code signature. An ad-hoc signed
build gets a new signature hash on every rebuild, so macOS forgets the
permission. Both build scripts sign with a stable local identity instead:

```sh
scripts/make-dev-cert.sh     # once: creates "ClipKeeper Development" in the login keychain
```

If macOS asks whether `codesign` may use the key, click Always Allow.

When the permission is on in System Settings but the app still reports it
missing, the entry belongs to an older build. Remove ClipKeeper from the
Accessibility list with the − button, then click Request Permission in
Settings › General. Or reset it from the terminal:

```sh
tccutil reset Accessibility com.raymondpeck.ClipKeeper
```

To sign with an Apple Development certificate instead:

1. Open Xcode › Settings › Accounts. Add your Apple ID.
2. Select the account, then Manage Certificates. Click + and choose Apple Development.
3. In `project.yml`, set `CODE_SIGN_IDENTITY: "Apple Development"` and `DEVELOPMENT_TEAM` to your team ID.
4. Run `scripts/build.sh install`.

## Layout

```
ClipKeeper/
  App/          AppDelegate, main
  Model/        Clip, ClipCollection, PasteboardSnapshot, ClipKind
  Storage/      Database (GRDB + FTS5), BlobStore, ClipStore
  Clipboard/    PasteboardMonitor, ContentClassifier, detectors, Paster, Exporter
  Keys/         KeyCombo, KeyAction, KeyBindingStore
  Shelf/        ShelfPanel, ShelfController, ShelfViewModel, views
  Editors/      TextEditorWindow, CropWindow, SaveAsDialog
  Settings/     Settings and onboarding windows
  Support/      Preferences, Accessibility, LoginItem, helpers
ClipKeeperTests/
scripts/        build.sh, make-icon.swift
docs/           PLAN.md
```

Data lives in `~/Library/Application Support/ClipKeeper/`: a SQLite database
and a `blobs` folder with pasteboard snapshots, thumbnails, and favicons.
