# ClipKeeper

A clipboard manager for macOS that keeps your hands on the keyboard.

Everything you copy lands in a shelf at the right edge of the screen. Press
⌃⌘V, or move the mouse to the right edge of your screen. Move with the arrow
keys, press Return, and the clip pastes into the app you were in. Text, code,
Markdown, rich text, images, links, colors, and files each render as what
they are. Hover or click the ⓘ on a card for its details.

![The shelf](docs/images/shelf.png)

## Why

- **Every type renders.** Markdown is rendered. Code is syntax colored with
  its language named. Rich text keeps its formatting. Images show as
  thumbnails with their format. Links show the page title and icon. Colors
  show a swatch.
- **Keyboard first.** Arrow keys, Emacs keys, or vim keys. Return pastes the
  clip into the active application. Esc closes. Every key is remappable.
- **Nothing is lost.** Editing text or cropping an image makes a new clip.
  Collections, named sets that you fill on purpose, hold clips that never
  expire. Only Delete removes a clip.
- **Original formats stay.** A paste puts back every format the source app
  provided. Paste as… and Save as… offer conversions on request: rich text
  can be saved as Markdown, an image can change format, a link can become a
  Markdown link, and so on.
- **Private by design.** Clips stay on your Mac in files only your account
  can read. Password manager copies are skipped. Deleted clips are gone.

## Install

Requirements: macOS 15 or later, and Xcode 26 or the Command Line Tools to
build it.

```sh
git clone <this repository> && cd ClipKeeper
scripts/build-with-swiftpm.sh run
```

The script checks the tools, creates a local signing identity on the first
run, builds `build/spm/ClipKeeper.app`, and launches it. When macOS asks
whether `codesign` may use the new key, click Always Allow. On first launch
a welcome window walks you through the hotkey, the Accessibility permission,
and launch at login. See [docs/BUILDING.md](docs/BUILDING.md) for the Xcode
method, code signing, and dependency safety.

## Quick start

**Open the shelf**
- Press ⌃⌘V. Press it again, or Esc, to close.
- Or rest the mouse at the right edge of the screen for a moment.
- Drag the grip on the shelf's left edge to change its width.
- ⌘⇧P pins the shelf open for drag and drop. Esc still closes it.

**Pick a clip**
- ↓ ↑, or ⌃N ⌃P (Emacs), or ⌃J ⌃K (vim) move the selection.
- Type to search. Words can be in any order; a prefix is enough. Switch the
  results between Best match and Newest with the control above the list.
- Space shows the full clip with its details and action buttons.
- Hover or click the ⓘ on a card for the type, the formats on the
  clipboard, the size, the source, and the time.

**Paste**
- ⏎ pastes into the app you came from and closes the shelf.
- ⇧⏎ pastes as plain text.
- ⌥⏎ copies to the clipboard without pasting.
- ⌘⇧⏎ opens Paste as… with the formats for the clip.
- ⌘1 to ⌘9 paste the first nine clips directly.
- Double-click a card to paste it.

**Keep and organize**
- ← → or ⌃B ⌃F switch between History and your collections.
- ⌘N makes a collection. ⌘M moves the selected clip into one. Dragging a
  clip onto a tab does the same.
- ⌘P pins a clip to the top.

**Change and export**
- ⌘E edits text, or crops an image. The result is a new clip; the original
  stays.
- ⌘S saves the clip as a file. The save panel offers the formats for that
  type, original first.
- ⌘O opens a link in the browser, or reveals files in Finder.

**Bring files in**
- ⌘I imports files as separate clips: a Markdown file becomes a Markdown
  clip, an image file an image clip, and so on. Or drag files onto the
  shelf.
- In Finder, select files and press the shortcut you gave the "Add to
  ClipKeeper" service, set once in System Settings › Keyboard › Services.
- ⌘⇧I on a Files clip imports the contents of those files.

**Remove**
- ⌘⌫, or the trash icon on the card. ClipKeeper asks first.
- Check the boxes on several cards, with a click or ⌘⇧A, for a bulk move,
  save, or delete.

**Everything else**
- ⌘, opens Settings: hotkeys, keys, privacy, and storage limits.
- The menu bar icon has Pause Capture, an eyedropper for grabbing a color
  off the screen, and the User Guide.

The full [User Guide](docs/USER-GUIDE.md) covers every feature, every clip
type, and the answers to common problems.

## Default keys

| Key | Action |
|---|---|
| ⌃⌘V | Open or close the shelf |
| ↓ ↑ ⌃N ⌃P ⌃J ⌃K | Move the selection |
| ← → ⌃B ⌃F ⇥ ⇧⇥ | Switch sets |
| ⏎ ⇧⏎ ⌥⏎ ⌘⇧⏎ | Paste, paste plain, copy only, paste as… |
| ⌘1 – ⌘9 | Paste slot 1 to 9 |
| ␣ (space) | Full preview |
| ⌘E ⌘S ⌘O | Edit or crop, save as…, open |
| ⌘I ⌘⇧I | Import files, import a Files clip's contents |
| ⌘P ⌘M ⌘D ⌘⌫ | Pin, move to collection, duplicate, delete |
| ⌘N ⌘R | New collection, rename collection |
| ⌘⇧A ⌘A ⇧↓ ⇧↑ | Check the clip, check all, check and move |
| ⌘, | Settings |
| ⌘⇧P | Keep the shelf open |
| esc | Close |

Change any of them in Settings › Keys.

## Privacy and safety

- Clips stay on your Mac, in a folder only your account can read.
- The only network request fetches the title and icon of a copied link. Turn
  it off in Settings › Privacy.
- Copies from password managers are skipped. Any app can be excluded. Pause
  capture before copying something you do not want kept.
- Delete removes the clip from the database and from disk. There is no trash.

## For developers

- [docs/BUILDING.md](docs/BUILDING.md): build with SwiftPM or Xcode, tests,
  code signing, debug hooks.
- [docs/ROADMAP.md](docs/ROADMAP.md): what comes next, in phases.
- [docs/COMPETITIVE-ANALYSIS.md](docs/COMPETITIVE-ANALYSIS.md): how
  ClipKeeper compares with the other clipboard managers.
- [docs/PLAN.md](docs/PLAN.md): the design as agreed before implementation.
- Source layout: `ClipKeeper/` holds the app in folders per concern
  (Clipboard, Storage, Shelf, Keys, Editors, Settings). `ClipKeeperTests/`
  holds the Swift Testing suites.
