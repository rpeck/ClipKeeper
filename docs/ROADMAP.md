# ClipKeeper Roadmap

The order of work after the first release. Phase 0 comes first. The later
phases come from [COMPETITIVE-ANALYSIS.md](COMPETITIVE-ANALYSIS.md), which
lists the source for each item. Each item names the competitor that has it,
the estimate, and the acceptance test.

## Phase 0: Solidify

Goal: the current feature set is stable, documented, and shippable.

- [ ] User Guide and README reviewed and final.
- [ ] Xcode license accepted; `scripts/build.sh` verified end to end.
- [ ] Apple Developer Program joined. Developer ID certificate created.
- [ ] Sparkle updates behind a compile flag, with signed appcast.
- [ ] Two targets: direct download (Sparkle, hardened runtime) and App Store (sandbox, privacy manifest, IAP tip jar).
- [ ] Release workflow on GitHub Actions: archive, sign, notarize, staple, package, appcast, release, cask.
- [ ] Homebrew tap with the cask.
- [ ] Choose the license and the donation service.
- [ ] Two weeks of daily use with no capture misses and no crashes.

## Phase 1: Close the gaps with the leaders

Each is one to three days. Order by value.

1. **Filters in search.** Filter by type, source app, and date. Search terms
   such as `type:code` and `app:Safari`. (Raycast, Paste, Pastebot, Klipto.)
   Test: `type:image` shows only images; `app:Safari link` shows Safari links.
2. **OCR and QR codes.** Vision framework, local only. Image text becomes
   searchable. "Copy text from image" and "Copy QR code contents" actions.
   (Raycast, Paste, Klipto.) Test: a screenshot of a terminal is found by a
   word in it.
3. **Sequential paste.** Mark clips in order, then ⌘V in the target app
   pastes them one after another. Optional Tab or Return after each.
   (Pastebot Stacks, Klipto, Paste.) Test: three marked clips fill three
   form fields with three ⌘V presses.
4. **Transforms on paste.** Built in: upper, lower, title, camel, snake,
   trim, collapse whitespace, strip smart quotes and em-dashes, JSON pretty
   and minify, Base64 encode and decode, URL encode and decode, sort lines,
   unique lines. User-defined shell filters with hotkeys. (Pastebot filters,
   Klipto transforms.) Test: Paste as… lists transforms; a shell filter runs.
5. **Secret and PII detection.** Detect API keys, tokens, private keys, and
   password-shaped strings by pattern and entropy. Detect personal data:
   credit card numbers (Luhn check), Social Security numbers, bank account
   and IBAN numbers, and one-time codes. Per category the user chooses:
   record as usual, record concealed (blurred until revealed, expires after
   N minutes), or never record. Default: secrets concealed with a 10 minute
   expiry, card and account numbers never recorded. (No competitor.) Test: a
   copied AWS key shows concealed and is gone after the configured time; a
   copied card number never appears.
6. **Data detector types.** Email, phone, address, date, tracking number as
   kinds with matching actions. (Raycast, Klipto.) Test: a copied email shows
   an envelope and "Compose" action.
7. **Notes and titles on clips.** Rename a clip; add a searchable note.
   (Pastebot, iClip.) Test: search finds a clip by its note.
8. **Smart collections.** A collection defined by rules: type, app, regex,
   age. (Pastebot 3.) Test: a "Links from Safari" collection fills itself.
9. **Global hotkeys without the shelf.** Paste last as plain text; paste
   previous; cycle back through recent clips. (Maccy, Raycast.)
10. **Hold-to-paste.** Hold the hotkey, move, release to paste. (Klipto.)
11. **Date group headers** and a keyboard cheat sheet overlay on `?`.
12. **Pinned clips get fixed hotkeys.** (Maccy, Pastebot.)

## Phase 2: The developer's clipboard

1. **CLI.** `clipkeeper list`, `clipkeeper get 3`, `clipkeeper paste 3`,
   `clipkeeper add`. (Pastebot.)
2. **Shortcuts actions.** Get, add, paste, and search. (Pastebot, Paste.)
3. **MCP server.** Agents such as Claude Code read and write the history
   and collections. (Pastebot, Paste.)
4. **Export and import collections** as files. (iClip, Paste.)
5. **Drop files onto the shelf** as a holding area. (Ledge for Mac, Yoink.)
6. **Encryption at rest** with the key in the keychain. (Raycast.)

## Phase 3: Strategic

1. **iCloud sync** between Macs. Needs CloudKit and blob conflict handling.
   (Paste, PasteNow, Pastebot.) Two to three weeks.
2. **Shelf on the left or top edge.** The panel geometry, the slide
   direction, the edge trigger, and the resize handle all assume the right
   edge. Left is a mirror and costs about a day. Top changes the layout to
   a horizontal strip and costs about a week.
3. **iOS companion.** A separate product.

## Not planned

- Windows and Linux.
- Cloud accounts or telemetry.
