# Building ClipKeeper

## Two build paths

**SwiftPM.** Works with the Command Line Tools alone. Makes a full app bundle.

```sh
scripts/bundle-spm.sh          # build/spm/ClipKeeper.app
scripts/bundle-spm.sh run      # build, then launch
swift test -c release -Xswiftc -enable-testing
```

The tests use Swift Testing, which the Command Line Tools include. Release
mode is required: one dependency uses `#Preview`, which only Xcode can
expand.

**Xcode.** Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
scripts/build.sh run           # debug build, then launch
scripts/build.sh test          # unit tests
scripts/build.sh install       # release build into /Applications
```

The script generates `ClipKeeper.xcodeproj` from `project.yml`, draws the app
icon with `scripts/make-icon.swift`, and runs `xcodebuild`. It passes
`DEVELOPER_DIR` for Xcode.app, so no `xcode-select` change is needed. The
Xcode license must be accepted once: `sudo xcodebuild -license accept`.

## Code signing

The Accessibility permission is tied to the code signature. An ad-hoc
signature changes on every build, and macOS then forgets the permission.
Both build paths sign with a stable local identity instead:

```sh
scripts/make-dev-cert.sh       # once: "ClipKeeper Development" in the login keychain
```

When macOS asks whether `codesign` may use the key, click **Always Allow**.
Allow alone permits one build, and the dialog returns on the next.

To reset a stale permission entry:

```sh
tccutil reset Accessibility com.raymondpeck.ClipKeeper
```

To sign with an Apple Development certificate instead:

1. Open Xcode › Settings › Accounts. Add your Apple ID.
2. Select the account, then Manage Certificates. Click + and choose Apple Development.
3. In `project.yml`, set `CODE_SIGN_IDENTITY: "Apple Development"` and
   `DEVELOPMENT_TEAM` to your team ID.
4. Run `scripts/build.sh install`.

## Dependencies

| Package | Use | Size in the app |
|---|---|---|
| MarkdownUI | Markdown rendering | in the binary |
| Highlightr | Syntax colors through highlight.js | 2.1 MB resource bundle |
| KeyboardShortcuts | Global hotkeys and the recorder control | 64 KB |
| GRDB | SQLite with FTS5 | in the binary |

The app bundle is about 13 MB. KeyboardShortcuts is pinned below 1.16
because later versions use `#Preview`.

## Debug hooks

All are environment variables read at launch.

- `CLIPKEEPER_DATA_DIR=<dir>` uses that folder for the database and blobs
  instead of Application Support. Use it for demos and for tests against a
  clean store.
- `CLIPKEEPER_DEBUG=1` logs every capture with its duration, and every
  pasteboard read slower than 50 ms.
- `CLIPKEEPER_SNAPSHOT_DIR=<dir>` renders the shelf, its overlays, Settings,
  onboarding, the editor, and the crop window to PNG files in that directory
  about ten seconds after launch. Add `CLIPKEEPER_SNAPSHOT_QUIT=1` to quit
  afterwards.

```sh
CLIPKEEPER_SNAPSHOT_DIR=/tmp/snaps CLIPKEEPER_SNAPSHOT_QUIT=1 build/spm/ClipKeeper.app/Contents/MacOS/ClipKeeper
```

The screenshots in `docs/images` come from that flow, run against a demo
store (`CLIPKEEPER_DATA_DIR`) at a 440 point shelf width. The captures are
2x Retina. The files in `docs/images` are scaled to three eighths of the
capture's pixel width with `sips --resampleWidth` (a 440 point shelf becomes
a 330 pixel image), because Markdown has no size syntax that works on
GitHub. Keep that ratio for new screenshots.

## Layout

```
ClipKeeper/
  App/          AppDelegate, main
  Model/        Clip, ClipCollection, PasteboardSnapshot, ClipKind
  Storage/      Database (GRDB + FTS5), BlobStore, ClipStore
  Clipboard/    PasteboardMonitor, ContentClassifier, detectors, Paster, Exporter
  Keys/         KeyCombo, KeyAction, KeyBindingStore
  Shelf/        ShelfPanel, ShelfController, ShelfViewModel, views, EdgeTrigger
  Editors/      TextEditorWindow, CropWindow, SaveAsDialog
  Settings/     Settings and onboarding windows
  Support/      Preferences, Accessibility, LoginItem, helpers, DebugSnapshots
ClipKeeperTests/
scripts/        build.sh, bundle-spm.sh, make-dev-cert.sh, make-icon.swift
docs/           USER-GUIDE.md, BUILDING.md, PLAN.md
```

Data lives in `~/Library/Application Support/ClipKeeper/`: a SQLite database
and a `blobs` folder with pasteboard snapshots, thumbnails, and favicons.

## Notes on capture

- macOS has no clipboard change event. The monitor polls the change count
  every 150 ms.
- The capture reads every type the source app wrote, but skips types the
  pasteboard server translates on demand. Reading a translated type can
  block until the owning app services the request, which loses the copies
  made during the wait.
- A hidden shelf does not reload or render. Captures never wait on the
  interface.
- highlight.js loads on a background thread at launch, because the load
  takes about a second.
