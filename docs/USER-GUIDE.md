# ClipKeeper User Guide

ClipKeeper is a clipboard manager for macOS that keeps text, code, images,
links, colors, and files. It stores everything you copy and shows it in a
shelf at the right edge of the screen. You choose a clip with the keyboard, or
double-click it; it pastes into the app you were using. This guide covers
every feature. The README has the short version.

Keys are written like this: `⌘⇧V`. Safety notes are marked with 🛡.

## Contents

- [The idea in three terms](#the-idea-in-three-terms)
- [First run](#first-run)
- [The menu bar icon](#the-menu-bar-icon)
- [Open and close the shelf](#open-and-close-the-shelf)
- [The shelf](#the-shelf)
- [Move and search](#move-and-search)
- [Preview a clip](#preview-a-clip)
- [Paste](#paste)
- [Clip types](#clip-types)
- [Special cases](#special-cases)
- [Collections](#collections)
- [Pin, duplicate, delete](#pin-duplicate-delete)
- [Work with several clips at once](#work-with-several-clips-at-once)
- [Edit and crop](#edit-and-crop)
- [Save a clip as a file](#save-a-clip-as-a-file)
- [Open links and files](#open-links-and-files)
- [The eyedropper](#the-eyedropper)
- [Pause capture](#pause-capture)
- [Settings](#settings)
- [Keyboard reference](#keyboard-reference)
- [Privacy and safety](#privacy-and-safety)
- [Where the data lives](#where-the-data-lives)
- [Problems and answers](#problems-and-answers)

## The idea in three terms

- **Clip.** One thing you copied: text, code, an image, a link, a color, or
  files. ClipKeeper keeps every format the source app provided, so a paste
  is the same as the original copy.
- **History.** Every Copy operation adds a clip to the top of History. Old
  clips leave the bottom of History when it reaches the limits you set. See
  [Settings › Storage](#settings).
- **Collection.** A named set of clips that you keep intentionally, for
  example a collection of AI prompts, or of email signatures. Clips in a
  collection never expire. You move a clip into a collection yourself. A
  copy never lands in a collection by itself.

## First run

ClipKeeper lives in the menu bar. It has no Dock icon and no main window.
On the first launch a welcome window walks you through three steps.

1. **Hotkey.** The default is `⌘⇧V`. If you want to change the hotkey, click
   the field and press the keys you want.
2. **Accessibility.** When you tell it to paste a clip, ClipKeeper presses
   `⌘V` for you in the app you came from. macOS asks for the Accessibility
   permission for that.
   - Click Open Accessibility Settings.
   - Turn on ClipKeeper in the list.
3. **Launch at login.** Turn it on so the shelf is always ready.

Without the Accessibility permission, `Return` copies the clip to the
clipboard and closes the shelf. You then press `⌘V` yourself. The shelf
footer says "Copy" instead of "Paste" while the permission is missing.

You can change all three later in Settings › General.

## The menu bar icon

Click the clipboard icon in the menu bar for these items:

- **Open Shelf.** Same as the hotkey.
- **Pause Capture / Resume Capture.** Stops or restarts recording. See
  [Pause capture](#pause-capture).
- **Pick a Color with Eyedropper….** See [The eyedropper](#the-eyedropper).
- **Settings….** Opens the Settings window.
- **User Guide.** Opens this document.
- **Quit ClipKeeper.**

The icon fills for a moment each time a copy is recorded.

## Open and close the shelf

There are three ways to open the shelf:

- **Hotkey.** Press `⌘⇧V`. Press it again, or press `Escape`, to close.
- **Mouse.** Rest the pointer at the right edge of the screen for a moment.
  The shelf slides in on that screen. Move the pointer away from the shelf
  and it slides out again.
- **Menu bar.** Click the icon and choose Open Shelf.

The shelf also closes when you click anywhere outside it, and after a
paste.

The shelf opens on the screen that holds the window you are working in. The
mouse trigger opens it on the screen that holds the pointer.

## The shelf

![The shelf](images/shelf.png)

From top to bottom the shelf has:

- **Search field.** It has the keyboard focus when the shelf opens. Type to
  filter. The gear button opens Settings.
- **Clip set tabs.** History is first. Each collection has a tab. The `+`
  button makes a new collection.
- **Clip list.** Newest first. Pinned clips stay at the top. The selected clip
  has a blue border.
- **Key hints.** The footer shows the keys that apply to the selected clip.

Drag the left edge of the shelf to change its width, from 200 to 800
points. A small grip marks the edge. The width is remembered, and Settings ›
General has a slider for it too.

Each clip card shows:

- A checkbox at the left, for
  [working with several clips at once](#work-with-several-clips-at-once).
- The content, rendered by type.
- The icon of the app you copied from.
- A summary, such as `40 lines · 1545 characters · Python` or `PNG · 2548 × 1204 · 563 KB`.
- An ⓘ icon. Hover it, or click it, for the type, the formats on the
  clipboard (such as PNG or JPEG), the size, the source app, and the copy
  time. The [preview](#preview-a-clip) shows the same details in its header.
- The age of the clip.
- A `⌘1` to `⌘9` badge on the first nine clips.
- A trash icon that deletes the clip.
- A pin icon when the clip is pinned.

## Move and search

- `↓` `↑`, or `⌃N` `⌃P` (Emacs), or `⌃J` `⌃K` (vim) move the selection.
- `←` `→` or `⌃B` `⌃F` switch between History and the collections.
  `⇥` and `⇧⇥` do the same.
- `Space` opens the [preview](#preview-a-clip).
- **Type** to search. The list filters as you type.
- When the search field holds text, `←` `→` move the caret and `⌫` deletes
  text. `⇥` `⇧⇥` still switch sets. Clear the field with the ⓧ button.

Click a clip to select it. Double-click a clip to paste it.

**How search ranks the results.** Search matches whole words and word
prefixes: `rel` finds "Release checklist". Words can be in any order and do
not have to be next to each other. A clip that contains more of your words,
or contains them more often, ranks higher. A word that is rare across your
clips counts more than a common one, and a match in the first line counts
more than a match deep in the text. Short clips rank above long clips with
the same matches. Pinned clips stay on top.

![Search results](images/search.png)

A control above the results switches the order between **Best match** and
**Newest**. The choice is remembered.

## Preview a clip

Press `Space`, or choose Full Preview from a card's right-click menu, to see
the whole clip. The header shows the type, the formats on the clipboard,
the size, the source app, and the copy time. The buttons at the bottom
paste, copy, save, or edit the clip.

![The preview](images/preview.png)

- `Space` or `Escape` closes the preview.
- `↓` `↑` move to the next or previous clip while the preview is open.

## Paste

- `Return` pastes the selected clip into the app you came from and closes
  the shelf. The clip goes back to the clipboard in its original form, with
  every format the source app provided:
  - Rich text pastes with its formatting.
  - Images paste as images, in their original format.
  - A link pastes as its URL.
  - A color pastes as its text, and as a color object for apps that take one.
  - Files paste as file references, so a paste in Finder copies the files.
- `⇧Return` pastes as plain text. For a link it pastes the URL. For a color
  it pastes the hex value. For files it pastes the paths.
- `⌥Return` copies the clip to the clipboard and closes the shelf, without
  a paste. Use this to paste later, or in an app that needs a special paste
  command.
- `⌘⇧Return` opens Paste as…. Pick a representation with `↓` `↑` and
  `Return`, or press its number. The choices depend on the type; see
  [Clip types](#clip-types).
- `⌘1` to `⌘9` paste the first nine clips of the current set without moving
  the selection.

**Without the Accessibility permission**, every paste action above copies
the clip to the clipboard and closes the shelf, and you press `⌘V` in the
app yourself. Settings › General shows the permission status.

By default the pasted clip stays where it is in History. Turn on
"Move a clip to the top of History after pasting it" in Settings › General
to keep History in most-recently-used order.

## Clip types

ClipKeeper looks at each copy and decides its type. The type sets the
preview, the Paste as… choices, and the Save as… formats.

**Text**
- Plain text.
- Save as .txt.

**Markdown**
- Text with headings, lists, links, emphasis, fences, or tables.
- Rendered as Markdown, with syntax colors in fenced code blocks.
- Save as .md or .txt.

**Code**
- Text that looks like source code. ClipKeeper recognizes Python, JavaScript,
  TypeScript, Swift, shell, JSON, YAML, HTML, XML, CSS, SQL, Go, Rust, C, C++,
  Objective-C, Java, Kotlin, C#, Ruby, PHP, TOML, Lisp, Dockerfile, Makefile,
  and diffs.
- Rendered with syntax colors. The language shows in the summary line.
- Save with the language's extension, as .txt, or as a Markdown code block.

**Rich text**
- Copies with fonts, bold, italic, links, or lists, from a browser, Mail,
  Pages, Word, or TextEdit.
- Rendered as formatted text.
- Paste as: original, plain text, Markdown, HTML.
- Save as: .rtf, .rtfd (with attachments), .html, .md, .txt. The original
  format is first in the list.

**Image**
- Screenshots and copied images. PNG, TIFF, JPEG, HEIC, and GIF. The
  summary line and the ⓘ details name the format.
- Rendered as a thumbnail. `Space` shows the full image.
- Paste as: original, PNG, JPEG, TIFF.
- Save as: the original format, PNG, JPEG, TIFF, or HEIC.
- `⌘E` opens the crop tool. Cropping makes a new clip; the original is
  unchanged.

**Link**
- A web address, such as `https://example.com/page`.
- Shows the page title and the site icon. ClipKeeper fetches them from the
  site once. Turn this off in Settings › Privacy.
- Paste as: original, URL, title, Markdown link `[title](url)`.
- Save as .webloc, .txt, or .md.
- `⌘O` opens the link in the browser.

**Color**
- A color from a color picker, from the eyedropper, or text such as
  `#4cb39a`, `rgb(76, 179, 154)`, or `hsl(160, 40%, 50%)`.
- Shows a swatch with the hex and rgb values.
- Paste as: original, hex, `rgb()`, CSS, SwiftUI `Color(...)`.

**Files**
- Files copied in Finder.
- Shows each file with its icon and folder.
- `Return` pastes the file references, so a paste in Finder copies the files.
- Paste as: original, or the paths as text.
- `⌘O` reveals the files in Finder.

## Special cases

- 🛡 **Passwords.** Password managers mark their copies as concealed, and
  ClipKeeper does not record those.
  - Covered: 1Password, Bitwarden, and similar apps, and the built-in
    password managers of Safari, Chrome, Edge, and the macOS Passwords app.
  - Not covered: a password you type and copy yourself from a document. That
    is ordinary text and is recorded.
  - See [Privacy and safety](#privacy-and-safety).
- **Copying the same thing twice.** The existing clip moves to the top of
  History. No duplicate is made.
- **Very large images.** Images above the size limit in Settings › Storage
  are not recorded. The default limit is 50 MB.
- **Excluded apps.** Copies made in apps on the list in Settings › Privacy
  are never recorded.

## Collections

Every Copy operation adds to History, and History follows the retention
limits. A collection is a named set of clips that you keep intentionally,
for example a collection of AI prompts. Clips in a collection never expire.

- **New collection.** Press `⌘N`, or click `+` in the tab row. Type a name and
  press `Return`.
- **Move a clip.** Select it and press `⌘M`. Pick the collection with `↓` `↑`
  and `Return`, or press its number. The last item in the picker makes a new
  collection and moves the clip there in one step.
- **Drag a clip** onto a collection tab to move it there. Drag it onto the
  History tab to move it back.
- **Rename.** Open the collection and press `⌘R`, or right-click its tab.
- **Delete.** Right-click the tab and choose Delete Collection. The clips move
  back to History. Nothing is lost.
- **Order in a collection.** Newest addition first. Pinned clips stay at the
  top.

![The collection picker](images/picker.png)

A copy always goes to History, never straight into a collection. Move it
there intentionally.

## Pin, duplicate, delete

- `⌘P` pins or unpins the selected clip. Pinned clips stay at the top of
  their set and never expire.
- `⌘D` duplicates the selected clip.
- `⌘⌫` deletes the selected clip. The trash icon on the card does the same.
- `⌫` also deletes when the search field is empty.

🛡 **What can remove a clip.** Only two things: you delete it, or a History
limit in Settings › Storage removes an old, unpinned History clip. Editing,
cropping, and moving never change or remove a clip. Before a delete,
ClipKeeper asks: `Return` confirms, `Escape` cancels. Turn the question off
in Settings › General if you prefer.

![The delete confirmation](images/confirm.png)

## Work with several clips at once

Every card has a checkbox at the left. It is faint until you hover the card
or check it.

![Checked clips](images/checked.png)

- Click a checkbox to check or uncheck that clip.
- `⌘⇧A` checks or unchecks the selected clip, so you never need the mouse.
- `⇧↓` checks the selected clip and moves down. `⇧↑` does the same going
  up. Hold `⇧` and repeat to check a run of clips.
- `⌘A` checks every clip in the list. Press it again to uncheck them all.

While any clip is checked, these actions apply to all checked clips:

- `⌘M` moves them to a collection.
- `⌘S` saves them into a folder, each in its default format.
- `⌘⌫` deletes them after one confirmation.

With nothing checked, the same actions apply to the selected clip.

## Edit and crop

🛡 Editing never changes the original. The result is a new clip at the top
of History. Delete the original yourself if you do not want it. Safety first!

**Text, Markdown, code, rich text, links, colors**
1. Select the clip and press `⌘E`.
2. An editor window opens with the text. Code uses a monospaced font.
3. Press `⌘Return`, or click Save as New Clip. `Escape` cancels.

![The editor](images/editor.png)

The new clip is plain text. ClipKeeper classifies it again, so edited code
stays code and edited Markdown stays Markdown. Rich text becomes plain text,
because the editor edits the text, not the formatting.

**Images**
1. Select the clip and press `⌘E`.
2. Drag on the image to draw the area to keep.
3. Drag inside the area to move it. Drag a corner or an edge handle to
   resize it. Drag outside the area to start over.
4. The footer shows the size in pixels.
5. Press `Return`, or click Crop and Save as New Clip. `Escape` cancels. Reset
   restores the full image.

![The crop tool](images/crop.png)

The cropped image is a new PNG clip. The original image is unchanged. If
you need the cropped image in another format, use Paste as… or Save as… on
the new clip.

## Save a clip as a file

1. Select the clip and press `⌘S`.
2. The save panel opens with a file name made from the clip. Choose the
   folder.
3. The Format menu at the bottom of the panel lists the formats for this
   type. The first one is the original format. Changing the format changes
   the file extension.
4. Click Save.

With several clips checked, `⌘S` asks for a folder and saves each clip in
its default format. Names that collide get a number.

## Open links and files

- `⌘O` on a link opens it in the default browser.
- `⌘O` on files reveals them in Finder.
- `⌘O` on other text opens the first web address found in the text. If
  there is none, a brief message says "No link in this clip".

## The eyedropper

The eyedropper captures a color from anywhere on the screen.

1. Click the menu bar icon and choose Pick a Color with Eyedropper…, or press
   the eyedropper hotkey set in Settings › General.
2. Move the loupe over the color and click.

The color becomes a clip at the top of History and goes to the clipboard as
its hex value.

## Pause capture

🛡 Pause capture before you copy something that must not be kept, such as a
credit card number.

Choose Pause Capture from the menu bar icon. While paused:

- Copy and paste work as always in every app. ClipKeeper only stops
  watching. Nothing you copy while paused is written to History.
- The shelf shows an orange Paused badge next to the search field. Click the
  badge to resume.
- Pasting from the shelf still works.

Choose Resume Capture, or click the badge, to watch the clipboard again.
For safety, ClipKeeper does not keep any record of what you copied while
paused, so those copies cannot be recovered later.

## Settings

Open Settings with `⌘,` from the shelf, the gear button in the shelf, or the
menu bar icon. `Escape` closes the Settings window.

**General**
- Hotkeys for the shelf and the eyedropper. Click a field and press the
  desired keys.
- Paste into the front app when I press Return. When off, `Return` copies
  the content to the clipboard but does not paste it into the application.
- Accessibility status, with buttons to request the permission and to open
  System Settings.
- Move a clip to the top of History after pasting it. This keeps History in
  most-recently-used (LRU) order instead of copy order.
- Shelf width, from 200 to 800 points. Dragging the shelf's left edge sets
  the same value.
- Ask before deleting clips.
- Mouse: open the shelf at the right edge, the delay before it opens, and
  whether it closes when the pointer leaves.
- Launch ClipKeeper at login.

**Keys**

![The Keys tab](images/settings-keys.png)

- Every shelf action with its key combinations. A key combination is a chord
  such as `⌘⇧A`: hold the modifiers and press the key.
- To add a combination, click `+` at the right of the row, then press the
  keys. `Escape` stops the recording. When no recording is active, `Escape`
  closes the window.
- Click `⨉` on a combination to remove it.
- A combination belongs to one action. Adding it to another action
  reassigns it.
- Reset, at the right of a row, restores the default keys for that one
  action. Reset All to Defaults, at the bottom, restores the defaults for
  every action.

**Privacy**
- Skip clips that password managers mark as concealed or transient.
- Fetch page titles and icons for copied links.
- Excluded apps. Copies made in these apps are never recorded. Click Add App…
  and choose the app.

**Storage**

![The Storage tab](images/settings-storage.png)

- Keep at most N clips in History. Default 1000.
- Delete clips older than N days. Default off.
- Skip images larger than N MB. Default 50.
- Each limit is a switch with a number. Turn the switch off and that limit
  no longer applies: History has no size limit, or no age limit, or images
  of any size are recorded.
- With both History limits on, a clip is deleted when it is past the count
  OR older than the age. Either one is enough. Pinned clips and clips in
  collections are never deleted by the limits.
- Usage shows the clip count and disk use. Show in Finder opens the data
  folder. Clear History deletes the unpinned clips in History.

## Keyboard reference

These are the defaults. Each one can be changed in Settings › Keys.

Inside a picker: `↓` `↑` choose, `Return` selects, a number selects
directly, `Escape` cancels. Inside a confirmation: `Return` confirms,
`Escape` cancels.

| Key | Action |
|---|---|
| `⌘⇧V` | Open or close the shelf (global) |
| `↓` `↑` | Move the selection |
| `⌃N` `⌃P` | Move the selection (Emacs) |
| `⌃J` `⌃K` | Move the selection (vim) |
| `←` `→` | Previous or next set |
| `⌃B` `⌃F` | Previous or next set |
| `⇥` `⇧⇥` | Next or previous set, also while searching |
| `⏎` | Paste |
| `⇧⏎` | Paste as plain text |
| `⌥⏎` | Copy to the clipboard only |
| `⌘⇧⏎` | Paste as… |
| `⌘1` – `⌘9` | Paste slot 1 to 9 |
| `␣` (space) | Full preview |
| `⌘E` | Edit text, or crop an image |
| `⌘S` | Save as… |
| `⌘O` | Open link, or reveal files |
| `⌘P` | Pin or unpin |
| `⌘M` | Move to collection… |
| `⌘D` | Duplicate |
| `⌘⌫` | Delete |
| `⌘⇧A` | Check or uncheck the selected clip |
| `⌘A` | Check all, or uncheck all |
| `⇧↓` `⇧↑` | Check and move |
| `⌘N` | New collection |
| `⌘R` | Rename collection |
| `⌘,` | Settings |
| `esc` | Close |

## Privacy and safety

- 🛡 ClipKeeper stores clips only on your Mac. Nothing is uploaded.
- The one network use is the title and icon fetch for a copied link.
  - ClipKeeper downloads that page once, reads the title from it, and
    fetches the site's icon.
  - It is a normal page load, the same as a visit in a browser, but it
    happens without you opening the link.
  - Turn it off in Settings › Privacy.
- Password managers mark their copies as concealed. ClipKeeper skips those.
- Add apps whose copies must never be recorded to the excluded list.
- Pause capture before you copy something you do not want kept.
- 🛡 **Delete removes the data.** A deleted clip's record is removed from the
  database, and the database overwrites the freed space with zeros. The
  clip's files on disk are removed. Nothing is kept in a trash.
- 🛡 The data folder and every file in it are readable and writable only by
  your own user account. Other accounts on the Mac cannot open them.

## Where the data lives

`~/Library/Application Support/ClipKeeper/`

- `clipkeeper.sqlite` holds the clip records and the search index.
- `blobs/snapshots` holds one file per clip with every pasteboard format.
- `blobs/thumbnails` holds image previews.
- `blobs/favicons` holds site icons.

ClipKeeper sets the folder to mode 700 and the files to mode 600 on every
launch: your user only, no group, no others.

Delete the folder to start over. Quit ClipKeeper first.

## Problems and answers

**Return copies the clip to the clipboard but does not paste it.**
The Accessibility permission is missing. Open Settings › General and click
Request Permission, then turn on ClipKeeper in System Settings.

**The permission is on, but Settings still shows the warning.**
The entry in System Settings belongs to an older build of the app. Remove
ClipKeeper from the Accessibility list with the − button, then click Request
Permission again.

**A copy did not show up.**
Check these in order:
- Capture is paused. Look for the Paused badge in the shelf.
- The app is on the excluded list in Settings › Privacy.
- The copy came from a password manager, which marks it as concealed.
- The image is larger than the limit in Settings › Storage.
- You copied the same content as an existing clip. That clip moved to the
  top instead.

**The shelf opens when I do not want it.**
Increase the delay, or turn off the mouse trigger, in Settings › General ›
Mouse.

**A key does nothing.**
Open Settings › Keys and look at the action. Some keys yield to the search
field while it holds text: `←` `→` `⌫` `Space` and `⌃B` `⌃F` `⌃K`. Clear
the field first, or use `⇥` `⇧⇥` and `⌘⌫`.

**Code shows as plain text, or text shows as code.**
Detection is a guess from the content. The clip still pastes exactly as it
was copied. Save as… always offers the plain text format.

**A rich text clip looks different from the source.**
The shelf shows the formatting the source app put on the clipboard. Some apps
provide only plain text.
