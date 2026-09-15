# ClipKeeper Competitive Analysis

Date: 2026-09-14. Sources are linked at the end.

## The market in one paragraph

Clipboard managers on the Mac split into four groups. Free and open source
(Maccy, Clipy, Flycut). Launcher add-ons (Raycast, Alfred). Paid utilities
with one-time prices from $8 to $20 (CopyClip 2, Klipto, PastePal, iClip).
Subscriptions from $25 to $30 a year with sync (Paste, Pastebot 3). macOS 26
Tahoe added a built-in Spotlight clipboard history, plain text only, off by
default, and gone after 8 hours to 7 days. That built-in raises the bar: a
paid app must do things the system cannot.

## Feature matrix

Legend: ✓ has it, ○ partial, – no. CK is ClipKeeper today.

| Feature | CK | Maccy | Paste | Pastebot 3 | Raycast | Klipto | iClip | Ledge |
|---|---|---|---|---|---|---|---|---|
| Text, images, files, links, colors | ✓ | ○ text+image | ✓ | ✓ | ✓ | ✓ | ○ | ✓ |
| Markdown rendered | ✓ | – | – | – | – | – | – | – |
| Code syntax colors, language named | ✓ | – | – | – | – | ○ | – | – |
| Rich text shown with formatting | ✓ | – | ✓ | ✓ | – | ○ | ○ | – |
| Link title and favicon | ✓ | – | ✓ | – | ✓ | ○ | – | ✓ |
| Keyboard navigation, Emacs keys | ✓ | ○ | ○ | ○ | ○ | ○ | – | – |
| Every key remappable | ✓ | – | – | ○ | ○ | ○ | – | – |
| Slide-out shelf at screen edge, mouse trigger | ✓ | – | ○ bottom bar | – | – | – | ✓ | ✓ |
| Collections / pinboards / sets | ✓ | – | ✓ | ✓ | – | – | ✓ | – |
| Smart collections by rule | – | – | – | ✓ | – | – | – | – |
| Sequential paste / stack | – | – | ✓ | ✓ | – | ✓ | – | – |
| Transforms on paste (case, trim, JSON…) | ○ plain, MD, formats | – | ○ plain | ✓ + shell scripts | ○ | ✓ | – | – |
| OCR: search and copy text in images | – | – | ✓ | – | ✓ | ✓ | – | – |
| Filter by type / app / date | ○ search only | – | ✓ | ✓ | ✓ type | ✓ | ○ | – |
| Edit a clip | ✓ new clip | – | ○ | ✓ | ✓ | ○ | ✓ | – |
| Crop an image | ✓ | – | – | – | – | – | – | – |
| Paste as… and Save as… conversions | ✓ | – | – | – | – | ✓ colors | ○ | – |
| Notes or titles on a clip | – | – | – | ✓ | – | – | ✓ | – |
| Sync between Macs / iOS | – | – | ✓ iCloud | ✓ Mac only | – | – | ○ Dropbox | – |
| Shortcuts actions, CLI, MCP server | – | – | ✓ MCP | ✓ all three | ✓ | – | ○ AppleScript | – |
| Password manager clips skipped | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ? |
| Secret detection (API keys, tokens) | – | – | – | – | – | – | – | – |
| Encryption at rest | – | – | ○ | – | ✓ | – | – | – |
| Unlimited local history | ✓ optional | ✓ | ✓ | – 1,500 | Pro only | Pro only | ✓ | ? |
| Open source | ✓ | ✓ | – | – | – | – | – | ○ |
| Price | free / TBD | free, $9.99 MAS tip | $29.99/yr | $39 + $19/yr | free tier, Pro $8/mo | $19.99 once | $9.99 | free |

## Where ClipKeeper is already ahead

- **Rendering.** No competitor renders Markdown or highlights code with the
  language detected. Most show rich text as plain text.
- **Keyboard model.** Emacs keys, set switching with arrows, slots, a picker
  for every choice, and a remappable table. Maccy and Raycast are keyboard
  first too, but with fixed keys.
- **Never lossy.** Edit and crop make new clips. Paste as… and Save as…
  keep originals and convert on request, including rich text to Markdown.
- **Shelf at the edge with a mouse trigger.** Only iClip and Ledge do this.
- **Open source with a native, sandbox-ready design.**

## What we are missing, ranked by value against cost

### Tier 1: cheap, and each one closes a gap with a leader

1. **Type, app, and date filters in search.** Raycast, Paste, Pastebot,
   and Klipto all have it. Ours is text search only. A filter row above the
   list, and search terms such as `type:code` or `app:Safari`. One or two days.
2. **OCR on images, and QR codes.** Apple's Vision framework does both
   locally. Image clips become searchable, and "Copy text from image" is one
   action. Raycast, Paste, and Klipto have it. One day.
3. **Sequential paste (a stack).** Mark clips in order, then press ⌘V in the
   target app to paste them one after another, with an optional Tab or Return
   after each. Pastebot, Klipto, and Paste have it. Two days.
4. **Transforms on paste.** Built-in: upper, lower, title, camel, snake,
   trim, collapse whitespace, strip smart quotes and em-dashes, JSON pretty
   and minify, Base64, URL encode and decode, sort lines, unique lines. Plus
   user-defined shell filters with hotkeys, like Pastebot. Two to three days.
5. **Secret detection.** Nobody does this. Detect API keys, tokens, private
   keys, and passwords by shape and entropy, then conceal them in the shelf
   and expire them early. Developers copy secrets all day. One day.
6. **Data detector types.** Emails, phone numbers, addresses, dates, and
   tracking numbers as their own kinds with matching actions. Raycast and
   Klipto do part of this. NSDataDetector makes it cheap. One day.
7. **Notes and titles on clips.** Pastebot and iClip let you name a clip.
   Useful for collections. Half a day.
8. **Smart collections.** A collection defined by rules: type, app, regex,
   age. Pastebot 3's headline feature. Two days.
9. **Global hotkeys without the shelf.** Paste the last clip as plain text,
   paste the previous clip, cycle back. Maccy and Raycast users expect
   these. Half a day.
10. **Hold-to-paste.** Hold the hotkey, move, release to paste. Klipto's
    distinctive trick. Half a day.
11. **Date group headers** ("Today", "Yesterday") and a keyboard cheat sheet
    overlay on `?`. Half a day each.

### Tier 2: bigger, and they define the product for developers

12. **CLI, Shortcuts actions, and an MCP server.** Pastebot has all three.
    Paste added MCP in June 2026. An MCP server lets Claude Code and other
    agents read and write the clipboard history. This fits our audience
    best of all the items here. Three to five days.
13. **Export and import of collections**, and sharing a collection as a
    file. iClip and Paste have it. One day.
14. **Drop files onto the shelf** to hold them, like Ledge for Mac and
    Yoink. Adds a "shelf" use beyond the clipboard. One to two days.
15. **Encryption at rest** with the database key in the keychain. Raycast
    advertises it. One to two days, but it changes the storage layer.
16. **Pinned clips get fixed hotkeys**, as in Maccy and Pastebot. Half a day.

### Tier 3: strategic

17. **Sync.** Paste, PasteNow, and Pastebot sell sync. iCloud sync needs the
    Apple Developer Program and CloudKit, plus conflict handling for blobs.
    Two to three weeks. An iOS companion is a separate product.
18. **Windows and Linux.** Raycast and Ledge went cross-platform. Out of
    scope for a native Mac app.

## Pricing observations

- Free open source is the norm for the base. Maccy leads with 21.6k stars and
  about 112,000 Homebrew installs in the last year.
- Paid one-time utilities cluster at $8 to $20. Subscriptions exist only
  with sync.
- A $4.99 to $9.99 one-time App Store price, free direct download, and a
  donation link is the Maccy model. It works because the store copy is a
  convenience and a thank-you, not a paywall.

## Sources

- [Paste: best clipboard manager for Mac 2026](https://pasteapp.io/blog/best-clipboard-manager-for-mac)
- [Klipto: 9 clipboard managers compared](https://klipto.me/compare/best-clipboard-manager-mac/)
- [Klipto features](https://klipto.me/)
- [Maccy on GitHub](https://github.com/p0deje/Maccy)
- [Maccy star history](https://www.star-history.com/p0deje/maccy/)
- [Maccy on the App Store](https://apps.apple.com/us/app/maccy/id1527619437?mt=12)
- [Why Maccy is paid in the App Store](https://github.com/p0deje/Maccy/issues/378)
- [Pastebot 3](https://tapbots.com/pastebot/)
- [Pastebot 3 review, MacStories](https://www.macstories.net/reviews/pastebot-3-doubles-down-on-mac-clipboard-automation-and-introduces-two-new-business-models/)
- [Raycast clipboard history manual](https://manual.raycast.com/clipboard-history)
- [Paste pricing](https://pasteapp.io/pricing)
- [iClip](http://www.irradiatedsoftware.com/iclip/)
- [Shelf and Ledge by Nate B. Jones](https://unlock-ai.natebjones.com/apps/shelf-ledge)
- [Ledge for Mac](https://ledgemac.com/)
- Homebrew analytics for the `maccy` cask, read on 2026-09-14.
