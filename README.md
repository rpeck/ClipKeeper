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
- **Phones and Macs, no cloud.** Send clips to and from Android phones,
  iPhones, and other Macs over your own network, with a PIN per device and
  your OK on every transfer.

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
- ⌘+ (or ⌘=) opens an empty editor: type a clip in, without copying it
  first.
- ⌘E edits text, or crops an image. The result is a new clip; the original
  stays.
- ⌘S saves the clip as a file. The save panel offers the formats for that
  type, original first.
- ⌘O opens a link in the browser, or reveals files in Finder.
- ⌘⇧S shares a clip with any app or device; ⌥⌘S goes straight to AirDrop.
- ⌘⇧K sends a clip to an Android phone, an iPhone, or another Mac on the
  same network. Phones send text back with the free LocalSend app. See
  [Phones and other Macs](#phones-and-other-macs).

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
| ⌘+ ⌘= | New clip: type it in |
| ⌘E ⌘S ⌘O | Edit or crop, save as…, open |
| ⌘⇧S ⌥⌘S | Share…, send with AirDrop |
| ⌘⇧K | Send to a phone or another Mac… |
| ⌘I ⌘⇧I | Import files, import a Files clip's contents |
| ⌘P ⌘M ⌘D ⌘⌫ | Pin, move to collection, duplicate, delete |
| ⌘N ⌘R | New collection, rename collection |
| ⌘⇧A ⌘A ⇧↓ ⇧↑ | Check the clip, check all, check and move |
| ⌘, | Settings |
| ⌘⇧P | Keep the shelf open |
| esc | Close |

Change any of them in Settings › Keys.

## Phones and other Macs

This section is for anyone who wants to move clips between a Mac and an
Android phone, an iPhone, or another Mac. Everything goes over your own
local network. There is no cloud, no account, and no server to run.
Nothing moves until you send it, and every transfer to a Mac needs the
sender's PIN and your OK on the receiving Mac.

What works in this version:

| From | To | Text, links, code | Images | How |
|---|---|---|---|---|
| Phone | Mac | Yes | Not yet | LocalSend app on the phone |
| Mac | Phone | Yes | Yes | ⌘⇧K in the shelf |
| Mac | Mac | Yes | Not yet | ⌘⇧K in the shelf, ClipKeeper on both |
| Mac | Mac, automatic | Not yet | Not yet | Shared collections, planned |

Files clips do not go to another device yet. AirDrop (`⌥⌘S`) still works
for any Apple device, with images and files.

### Choose a path

- **An Android phone or an iPhone.** Install the LocalSend app on the
  phone. Then follow [Set up this Mac](#set-up-this-mac),
  [Add a device](#add-a-device), and the two send procedures.
- **Another Mac with ClipKeeper,** such as a home Mac and a work Mac. Set
  up both Macs, add each Mac as a device on the other, and use
  [Mac to Mac](#mac-to-mac).
- **Another Mac without ClipKeeper.** Install the LocalSend app on that
  Mac. ClipKeeper treats it like a phone.
- **Collections that stay the same on two Macs by themselves.** This is not
  built yet; it is Phase C in the [roadmap](docs/ROADMAP.md). Until then,
  send clips with `⌘⇧K`.

### Before you start

1. Put both devices on the same network. A guest Wi-Fi network usually
   keeps devices apart, so use the main one.
   - Check on the Mac: hold Option and click the Wi-Fi icon in the menu
     bar. Note the IP address.
   - Check on the phone: in the Wi-Fi settings, open the network's
     details. The first three numbers of its IP address must match the
     Mac's, for example `10.0.0.x` on both.
2. Quit the LocalSend app on any Mac that runs ClipKeeper's transfer. Both
   use port 53317, and only one can listen.
   - Check: `lsof -nP -iTCP:53317 -sTCP:LISTEN` prints nothing before you
     turn transfer on.

### Install LocalSend on a phone

Get the official app. Other listings and forks exist; check the
publisher.

- **Android:** [LocalSend on Google Play](https://play.google.com/store/apps/details?id=org.localsend.localsend_app),
  publisher Tien Do Nam. It is also on
  [F-Droid](https://f-droid.org/packages/org.localsend.localsend_app/) and
  on the [GitHub releases page](https://github.com/localsend/localsend/releases/latest).
- **iPhone:** [LocalSend on the App Store](https://apps.apple.com/us/app/localsend/id1661733229).
- **A Mac without ClipKeeper:** [the GitHub releases page](https://github.com/localsend/localsend/releases/latest),
  or `brew install --cask localsend`.

Then:

1. Open LocalSend.
   - Check: the Receive tab shows the device's name.
2. In LocalSend's settings, turn Quick Save off.
3. Turn on the PIN for receiving, and choose a PIN. Nothing reaches the
   phone without it.

### Set up this Mac

Do this on every Mac that runs ClipKeeper and sends or receives.

1. Open the shelf and press `⌘,`. Open the Devices tab.
2. Turn on "Send and receive clips with phones and Macs on this network".
3. If macOS asks to find devices on your local network, click Allow. If
   the firewall asks about incoming connections, click Allow.
   - Check: the status line says "On", with the Mac's address and port
     53317.
4. Optional: change "Name on phones". The default, "ClipKeeper Mac", says
   nothing about you; a name such as "Work Mac" is easier to pick from a
   list.
5. Under Networks, leave on only the networks you trust. VPN, virtual, and
   cellular connections are never used.

### Add a device

Each device that sends to this Mac gets its own PIN.

1. In Settings › Devices, under Phones and Macs, type a name, such as
   "Pixel" or "Work Mac". Click Add Device.
2. Note the 8-character PIN, such as `k7mq x2ra`. Show displays it again
   later.
3. Give the PIN to that device only. It types the PIN when it sends to
   this Mac. The space is optional.

To revoke a device, click New PIN or Remove next to it. Any transfer it
has open stops at once.

### Send from a phone to the Mac

1. On the phone, copy the text. In LocalSend, open Send, choose Text, and
   paste. Or share the text to LocalSend from any app.
2. Tap the Mac's name under nearby devices.
3. Type the PIN that the Mac issued for this phone. LocalSend asks every
   time.
4. On the Mac, the dialog "Accept from Pixel?" appears. Press Return to
   accept, or Escape to refuse. Return works after a short moment, so a
   key you were typing elsewhere cannot accept it.
   - Check: the text is at the top of History, with an orange phone icon
     on the card.

Refuse a dialog that you did not expect. It means that someone else has
that device's PIN; click New PIN for it.

### Send from the Mac to a phone

1. Open LocalSend on the phone. A phone app in the background may not
   answer.
2. In the shelf, select a clip, or check several. Press `⌘⇧K`.
3. Choose the device. A shield marks a verified device; a question mark
   marks one that is not verified yet.
4. The first time, ClipKeeper shows 128 characters in eight rows. On the
   phone, in LocalSend, tap this Mac, then Verify, then Text. Compare all
   of the characters. If they match, press Return. If not, press Escape;
   something on the network pretends to be one of the two devices.
5. Choose the device from "Which device is this?", or a new entry.
6. If the phone has a receive PIN, ClipKeeper asks for it. Type the PIN
   that you chose in LocalSend.
   - Check: the phone shows the text with a Copy button. Images go to its
     gallery or downloads.

The next send to that device needs no comparison. ClipKeeper checks the
device's certificate on every send and stops if it changes.

### Mac to Mac

Two Macs that both run ClipKeeper send clips to each other the same way.
Each Mac issues a PIN to the other, and the receiving Mac shows the accept
dialog. Here, the example Macs are "Home" and "Work".

1. Do [Set up this Mac](#set-up-this-mac) on both Macs.
2. On Home, add a device named "Work" and note its PIN. On Work, add a
   device named "Home" and note its PIN.
3. To send from Home to Work: on Home, select a clip, press `⌘⇧K`, and
   choose Work.
4. The first time, Home shows 128 characters in eight rows. On Work, open
   Settings › Devices and read its fingerprint, in four rows. It must match
   the top four rows or the bottom four rows on Home. Home's own fingerprint
   is the other four. If they match, press Return.
5. Choose Work from "Which device is this?".
6. Home asks for a PIN. Type the PIN that Work issued for Home in step 2.
7. On Work, the dialog "Accept from Home?" appears. Press Return.
   - Check: the clip is at the top of History on Work, with the orange
     icon.
8. To send the other way, repeat steps 3 to 7 from Work.

Home asks for Work's PIN on each send in this version; it does not store
another Mac's PIN.

### How transfer is protected

- It is off until you turn it on, and only on the networks you choose.
- All transfers use TLS. A device must hold the certificate you verified,
  and every transfer to a Mac needs the sender's PIN and your OK.
- After 30 wrong PINs, transfer stops until you press Restart. While the
  screen is locked, the Mac refuses transfers.
- Received clips are plain text only. They never fetch a link title or
  icon, never replace your own clips, and have their own limit of 500
  clips.
- The Mac's key is made in its Secure Enclave and cannot leave it.
- Three AI models reviewed the design and the code for security, each on
  its own. See [docs/SYNC-DESIGN.md](docs/SYNC-DESIGN.md) for the threat
  model and every finding.

The [User Guide](docs/USER-GUIDE.md#phones) has the full reference and the
answers to common problems.

## Privacy and safety

- Clips stay on your Mac, in a folder only your account can read.
- The only internet request fetches the title and icon of a copied link.
  Turn it off in Settings › Privacy.
- Phone transfer is off until you turn it on. It uses the local network
  only, with TLS, a PIN per phone, and your OK on every transfer.
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
