# ClipKeeper — Design Plan

Revision 2. This revision applies the review feedback from 2026-09-13.
Decided items are stated as facts. Open items are in the last section.

## What I plan to build

### Platform and stack

- Swift 6. SwiftUI for the views. AppKit for the panel, the pasteboard, and the global hotkey.
- Target macOS 15 (Sequoia).
- Menu bar app with no Dock icon. The menu bar item has Pause, Open Shelf, Settings, and Quit.
- SQLite for the history. The search index is an FTS5 table with bm25 ranking.
- Images and rich text blobs go to files on disk in Application Support.
- Build from the command line with `xcodebuild`. Each build passes `DEVELOPER_DIR` for Xcode, so no global `xcode-select` change is needed.

### Capture

- macOS gives no clipboard change event. The app polls the pasteboard change count about six times per second. Every clipboard manager does this. It is cheap.
- Every copy goes into the top slot of History. Nothing is dropped.
- If the same content is copied again, the existing clip moves to the top. No duplicate is made.
- The app records the source app for each clip and shows its icon.
- The app skips clips that a password manager marks as concealed or transient. You can turn this off.
- **Eyedropper.** A menu bar action and a hotkey open the system color sampler. The sampled color becomes a color clip.

### Content types and formats

The rule for every type: **the original format is kept.** A plain paste puts back the full original pasteboard with every type. "Paste as…" and "Save as…" offer conversions.

- **Plain text.** Save as .txt.
- **Markdown.** Detected by heuristics on the text. Rendered as Markdown. Save as .md.
- **Code.** Detected by heuristics (shebang, keywords, punctuation shape). Rendered as a syntax-highlighted code block. Save with the right extension (.py, .sh, .ts, and so on).
- **Rich text** (RTF, RTFD, HTML). Rendered as rich text.
  - Paste: original rich text. Paste as: plain text, Markdown.
  - Save as: .rtf or .rtfd (original), .html, .md (converted), .txt.
  - The Markdown converter handles headings, bold, italic, links, and lists.
- **Images** (PNG, TIFF, JPEG, HEIC, screenshots). Thumbnail in the shelf. Crop tool in the editor.
  - Paste: original image data. Paste as: PNG, JPEG, TIFF.
  - Save as: original format, PNG, JPEG, TIFF, HEIC.
- **Links.** Show the title, the host, and the favicon.
  - How links work on the Mac pasteboard: a copied URL carries a plain-text type with the URL string, and often a URL type. A text field takes the plain-text type, so a paste into the browser bar or Emacs gives only the URL. A .webloc is a bookmark file. Finder opens it in the browser. Its text form is the URL.
  - Paste: the original types, so a text field receives the URL. Paste as: URL, title, Markdown link `[title](url)`.
  - Save as: .webloc, .txt, .md.
- **Colors.** A swatch with the hex and rgb values. Detected from a color pasteboard type, from the eyedropper, or from text such as `#4cb39a` or `rgb(...)`.
  - Paste as: hex, rgb(), Swift `Color(...)`, CSS. Save as: .txt.
- **Files.** Icon plus path. Paste puts the file references back on the pasteboard. Paste as: path text.

### Shelf

- An NSPanel that slides in from the right edge of the screen that holds the focused window.
- The panel takes keyboard input but does not activate the app. The previous app keeps focus and receives the paste.
- Search field at the top, focused on open, Spotlight style. Typing filters with FTS5 bm25 ranking. Up and Down move the selection while you type.
- Clip set tabs across the top. History is the first set and is always present.
- The selected clip shows a larger preview. Space toggles a full-size preview.
- **Number badges.** Clips 1 to 9 of the current set show a small badge with their ⌘ number.
- **Key hint bar.** A footer shows the actions for the selected clip with their keys: Enter Paste, ⇧Enter Plain, ⌥Enter Copy, ⌘S Save as…, and a Paste as… menu. A right-click menu shows the same actions.
- **Multi-select.** Each clip has a checkbox. It is visible on hover, and always visible in select mode. ⌘⇧A toggles select mode. ⌘A selects all. ⇧↑ and ⇧↓ extend the selection. Bulk actions: delete, save as… into a folder, move to a set.

### Editing

- Editing is never lossy. An edit or a crop makes a new clip on top. The original stays.
- Only an explicit delete removes a clip, and delete asks for confirmation.

### Keys (all remappable in Settings)

- ⌘⇧V toggles the shelf. Esc closes it.
- Enter pastes the selected clip and closes the shelf. ⇧Enter pastes as plain text. ⌥Enter copies to the clipboard without a paste.
- ⌘⇧Enter opens the Paste as… menu.
- ↑ ↓ ^N ^P move the selection. ← → ^B ^F switch clip sets. Tab and ⇧Tab always switch clip sets.
- ⌘1 to ⌘9 paste slot 1 to 9 of the current set.
- ⌘E edits (text) or crops (image). ⌘S opens Save as…. ⌘P pins. ⌘M moves to a set.
- ⌫ deletes, after a confirmation. ⌘⇧A toggles select mode. ⌘A selects all.
- Settings shows a table of every action with a shortcut recorder for each.

### First run and Settings

- **First run.** An onboarding window walks through two steps: enable Accessibility (with a button that opens the System Settings pane), and launch at login (a yes or no choice). Both can be changed later in Settings.
- **General:** hotkey, launch at login, paste behavior, Accessibility status with a button to the System Settings pane.
- **Keybindings:** the table above.
- **Privacy:** app exclusion list, concealed-clip skip, link-title fetch on or off.
- **Storage:** history count limit (default 1000), age limit (default off), image size limit (default 50 MB). Each limit has an "unlimited" choice. The count and age limits combine with OR: a clip expires when it is past the count limit or past the age limit. The page states this rule in words. Pinned clips and clips in named sets never expire.

## Decisions from the review

1. **Paste on Enter** sends a synthetic ⌘V and needs Accessibility. The app asks on first run and falls back to copy-and-close if it is denied. Settings has a button to the pane.
2. **Sets.** Every copy goes to History. A clip goes into a named set on purpose: ⌘M, then pick a set with the keyboard. Drag and drop also works. A copy never goes straight into the active named set.
3. **Left and Right.** When the search field is empty, ← → and ^B ^F switch sets. When it has text, they move the caret. Tab and ⇧Tab always switch sets.
4. **Edit** makes a new clip on top. Never lossy.
5. **Rich text Save as…** offers .md (converted) and .rtf (original). Same for HTML.
6. **Link titles** are fetched by default, with a Privacy switch to turn it off.
7. **Retention** defaults: 1000 clips, no age limit, 50 MB image limit. All three can be set to unlimited.
8. **Packages.** A small set of Swift packages is allowed. I report the size of each package and the final app size after the first build. Target: a modest download.
9. **Signing** with an Apple Development certificate. I give step-by-step instructions at build time.
10. **Import** is a future feature. Not in this build.
11. **Shelf height:** full screen height with a small margin.

## Open items

- **Name for the sets.** iClip calls them "Clip Sets" and the auto-filled set the "Recorder." ClipKeeper uses **History** for the auto-filled set. Proposed name for the named sets: **Collections**. Confirm, or give another name.
- **Xcode.** Installed: 26.3. Latest stable: 26.6. Update from the App Store before the first build. Xcode 27 is a release candidate and needs macOS 26, so it is not an option on this Mac.

## Future

- Import from Ledge (JSON history).
- Import from iClip (SQLite database).
- Import from Nate B. Jones's Shelf app.
