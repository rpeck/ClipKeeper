# Phone and Mac Transfer Design

Status: revision 3, 2026-10-04. Phase A is built; see "Phase A as built"
near the end for the four places where the code differs from revision 2,
and why. Revision 1 was reviewed by Claude Fable 5.1,
GPT-6 Astra, and Gemini 3.8 Flash, each independently and limited to
security. Their findings and the changes they forced are in the last
section. Decisions still open for the owner are marked **DECISION**.

## Goal

Send a clip from the Mac to a phone, and from a phone to the Mac, over the
local network, with nothing in the cloud and no server to run. Both
Android and iPhone. Later, the same between two ClipKeeper Macs. Every
transfer starts with an explicit action by the user.

## The honest premise

A network listener is new attack surface. No design removes that. What a
design can do is bound it: default off, reachable only on the networks the
user chose, authenticated before any content is read, every byte treated
as hostile until a narrow validator accepts it, and the dangerous parsers
kept out of the main process. The review was unanimous on this point, and
the owner's requirement is met in that bounded sense, not in the literal
sense of zero new surface. The owner accepted this on 2026-10-04 with
"as strong as SSH" as the bar: between Macs, mutual TLS with pinned
identity keys meets it; for phones, the protocol allows less, as the next
section explains.

## Decisions already made

- Local network only. No relay, no cloud.
- The Mac speaks the LocalSend protocol, version 2.0, so the phones run the
  open-source LocalSend app. No ClipKeeper phone app in this phase.
- Explicit send only. Nothing moves without a keystroke or a tap.
- Automatic acceptance does not exist in this phase, for any device.
- Phase A ships first, text only. SwiftNIO is the HTTP stack.

## The protocol, and the fact that reshapes the design

LocalSend v2: multicast discovery on 224.0.0.167:53317 with a JSON
announcement (alias, fingerprint, port, protocol); an HTTPS server with a
self-signed certificate whose SHA-256 is the device's fingerprint; and five
routes: `register`, `info`, `prepare-upload`, `upload`, `cancel`. The
receiver may require a six-digit PIN on `prepare-upload`. A reverse
"download" mode over plain HTTP exists; ClipKeeper never implements it.

**TLS in this protocol authenticates only the server.** A phone that sends
to the Mac presents no certificate. The fingerprint inside its request is
a string it typed in, and the same string goes out in the clear in every
announcement. So the Mac can never know which phone is talking to it.
Revision 1 built pairing, PIN exemptions, and auto-accept on that
fingerprint, and all three reviewers found it. Revision 2 draws the line
where the protocol allows:

- **Phones are known senders, not trusted ones.** The LocalSend PIN is an
  arbitrary string with no length limit (checked in the app source), so
  the Mac issues each phone its own random PIN at pairing. The user types
  it in LocalSend, which sends it over TLS, so it cannot be sniffed, and
  the budgets below stop guessing. The PIN that arrives tells the Mac
  which phone is talking. (Revision 2 said 24 characters stored by
  LocalSend; see "Phase A as built".) That gives
  identity and per-phone revocation. It is a pre-shared key, one step
  below a public key: a phone that leaks its PIN is a compromised phone,
  and the user revokes that PIN on the Mac.
- **Every transfer from a phone shows the accept dialog.** Return accepts,
  because the sender is known; Escape refuses. The dialog costs one
  keystroke when the phone is next to the laptop, which is the main case,
  and an unexpected dialog is the only signal the user would ever get
  that a phone's PIN leaked. No switch turns it off in this phase.
- **Macs are authenticated.** Two ClipKeepers use a second, ClipKeeper-only
  listener with mutual TLS, where both sides present a certificate and each
  pins the other's. Everything automatic, such as shared collections, lives
  only on that channel.
- **Sending to a phone** needs the user to compare the phone's full
  fingerprint once, on both screens, before the first send. Discovery
  announcements never create trust.

## Phases

1. **Phase A, text to and from phones.** Everything below except images.
   Received images are refused with 403 in this phase. Ships after the
   council reviews the code.
2. **Phase B, images.** Adds the sandboxed decode helper, then accepts PNG,
   JPEG, and GIF.
3. **Phase C, Mac to Mac.** The mutual-TLS listener, whole-clip packs, and
   shared collections. Its own council review.

Decided: Phase A first.

## Components

1. **Interface policy.** The user picks the interfaces in Settings: Wi-Fi
   and wired Ethernet are offered; VPN, tunnel, bridge, virtual, cellular,
   and loopback are never offered. Listeners, multicast, and outbound
   `register` replies all follow the same list. A change in the list
   closes every listener and session.
2. **Discovery.** Announces and listens only while the feature is on and
   only on the chosen interfaces, TTL 1, loopback off. Announcements are
   data: datagram at most 1 KB, JSON depth at most 4, alias at most 32
   graphemes after NFKC and the removal of format and control characters,
   port 1024 to 65535, fingerprint 64 hex characters. The discovered list
   holds at most 64 entries for 60 seconds each. A `register` reply goes
   only to the datagram's source address, only if that address is on the
   link of the receiving interface, at most once per source per 10 seconds
   and 20 per minute in total, with a 3-second connect timeout. An
   announcement that carries this Mac's own fingerprint from another
   address raises a persistent warning: something on this network
   impersonates this Mac.
3. **HTTP server.** SwiftNIO with NIOHTTP1 and NIOSSL, every optional
   feature off: no keep-alive, no pipelining, no chunked bodies, no
   upgrades, no HTTP/2. Two reviewers of three required a vetted parser
   over a hand-written one, and the dependency audit covers it like any
   other package. Decided: SwiftNIO. The application rules apply on top: methods `GET` and `POST`; the five paths matched exactly; query
   parsed with strict percent-decoding, duplicate keys refused; header
   block at most 16 KB and 64 headers; any `Transfer-Encoding`, duplicate
   or malformed `Content-Length`, bare LF, or obsolete folding refused;
   body limits per route; a 10-second deadline for the header block and a
   minimum throughput of 8 KB/s for bodies rather than an idle timeout;
   at most 8 connections and 2 per address; exact `Content-Length` match
   on `upload`; the connection closed after one request with any trailing
   bytes discarded. Nothing from a request is reflected into a response
   header or into a log.
4. **TLS.** Server: TLS 1.2 or later, the app's own P-256 certificate.
   Client: an ephemeral `URLSession` with no cookies, caches, or
   credentials; every redirect refused; the challenge delegate hashes the
   leaf certificate's DER bytes with SHA-256 and compares them in constant
   time with the expected fingerprint; a match uses that credential, and
   anything else cancels the challenge. The default system evaluation is
   never the decision. Plain HTTP peers are refused, and there is no
   setting to allow them.
5. **Keys and secrets.** The identity key is a P-256 key made in the
   Secure Enclave, so the private key never leaves the chip. The
   certificate is built with Apple's swift-certificates. The PINs are
   sealed under a key that only this Mac's Secure Enclave can derive. A
   failure stops the feature; nothing falls back to a weaker store. The
   decode helper never has access to either. (Revision 2 said the Data
   Protection keychain; see "Phase A as built".)
6. **Receive pipeline.** Validation, staging, then a network-only import
   path. The existing `FileImporter` is never called on network data.
7. **Send pipeline.** A keyboard picker, verified devices first, then
   `prepare-upload` and `upload`.
8. **Settings › Devices.** The switch, the interfaces, the Mac's alias and
   full fingerprint, the PIN with a regenerate button, the device list,
   the transfer log, and the limits.

## Receiving from a phone

1. A request from an address that is not on the link of an allowed
   interface is dropped before parsing.
2. `prepare-upload` checks the PIN from the query string before it reads
   the body, in constant time against every phone's PIN. A match names the
   sender. No match → 401. Limits: 3 failures per address, 10 per minute
   across all addresses, 30 in total → the server stops and tells the
   user. Each PIN is 24 characters from a cryptographic generator, is
   never logged, and the user can revoke or reissue it per phone at any
   time. Lockouts answer 429.
3. The body is decoded strictly: at most 50 files; 100 MB per transfer;
   20 MB per file; 1 MB per text; `size` an integer in range, summed with
   overflow checks; `fileId` at most 128 characters from `[A-Za-z0-9_-]`;
   bracket depth at most 32, checked before decoding. The `preview` field
   is never used as content.
4. Allowed MIME types: `text/plain` and `text/markdown` in Phase A; PNG,
   JPEG, and GIF from Phase B. TIFF and HEIC are not accepted from the
   network. Everything else → 403. The "save other files" option from
   revision 1 is gone.
5. One pending dialog at a time; a second `prepare-upload` → 409. The
   dialog names the phone that the PIN identified, and shows the item
   count, total size, and types. `Return` accepts and `Escape` refuses. A
   request with no matching PIN never reaches a dialog. The server pauses
   while the screen is locked.
6. Acceptance creates a session id and one token per file, each 128
   random bits, bound to the session, the file id, the declared size, and
   the source address, with a five-minute idle expiry on monotonic time.
   A token is single-use: it is consumed on completion, failure, or
   cancel, and a second `upload` for the same file → 403. `cancel` needs
   the session id and the same source address.
7. Bytes stream through a file descriptor into a private staging folder
   (mode 700) under the app's data folder, opened with `O_CREAT|O_EXCL|
   O_NOFOLLOW`, mode 600, under a random local name. The upload must end
   at exactly the declared size; more or fewer bytes → 400 and the file is
   discarded. A declared SHA-256 that does not match → 422. A quota holds
   staged bytes at 200 MB in total, and `prepare-upload` is refused when
   the volume has less than 2 GB free. Leftovers in staging are wiped at
   launch.
8. Text: must be valid UTF-8 with no NUL; C0 and C1 controls other than
   tab and newline, and bidirectional controls, are removed. The text
   becomes a clip through a network-only path that builds a snapshot with
   the plain-text type only. A URL in received text stays text unless it
   is `http` or `https`; custom schemes never become link clips.
9. Images, Phase B: the first bytes must match the declared type; the
   bytes go to a sandboxed XPC helper with no network, file, keychain, or
   clipboard access; the helper checks that ImageIO's detected type is in
   the allowlist, reads the dimensions and frame count from the header
   first and refuses more than 40 megapixels or 500 frames, decodes, and
   returns a re-encoded PNG and its dimensions. The parent validates the
   sizes and stores only the re-encoded PNG. The original bytes are
   discarded. A helper that stalls is killed.
10. The clip records the phone's alias as source, "LocalSend" as app, and
    a persistent `origin: network` mark. That mark survives deduplication
    and copies, shows on the card, and switches off the link title fetch
    for that clip for good. Network clips never replace a local clip's
    snapshot in the duplicate check; they get their own record.
11. Received clips count in their own retention domain, capped at 500
    clips and 500 MB, so a flood cannot evict the user's local history.
12. The log records time, device, address, count, bytes, and outcome.
    Never content, never a PIN, never a token.

## Sending to a phone

1. `⌘⇧K` opens the picker. Verified devices first; discovered ones below,
   marked unverified.
2. An unverified device needs a one-time verification: the shelf shows
   the device's full fingerprint in groups of four, the user opens
   LocalSend on the phone, which shows its own, and confirms the match.
   Only then is the fingerprint recorded. The announcement's fingerprint
   is never recorded on its own.
3. The payload: text as `text/plain` with a preview, links as text,
   images in their original format, rich text as RTF. Clips above 100 MB
   are refused.
4. `prepare-upload` over TLS with the pinned fingerprint. A mismatch
   aborts with an alert and the device returns to unverified. The PIN
   prompt, when the phone asks, shows the full fingerprint again and
   forwards the PIN only to a verified device.
5. Uploads carry a 60-second deadline each. `Escape` cancels and sends
   `cancel`.

## Mac to Mac, Phase C

Two ClipKeepers detect each other by a ClipKeeper marker in the
announcement, which is a hint only. Trust comes from a second listener on
a second port with mutual TLS: both sides present their certificate, and
each refuses any peer whose leaf fingerprint is not in its verified list.
The first pairing of two Macs is the same full-fingerprint comparison as
with a phone, on both screens.

**Whole-clip send** uses a versioned pack with an allowlist of
representations: plain text, one `http` or `https` URL, and a canonical
PNG that went through the decode helper on the sender. Nothing else is
accepted: no file URLs or file name lists, no bookmarks, no file promises,
no web archives, no keyed archives, no RTF, RTFD, HTML, PDF, or office
types, no application-private types. The pack is capped before decoding
and counted after. The receiver recomputes kind, hash, counts, and
provenance itself and ignores those fields in the pack.

**Shared collections** are set union plus tombstones, because clips never
change in place. On top of mutual TLS:

- Authorization is per peer, per collection, per sharing generation. A
  manifest for a collection the peer is not authorized on → 403. A
  requested clip must be a current member of that peer's authorized
  collection; a clip id alone exports nothing.
- Each peer keeps a sequence number per collection. A manifest with a
  sequence at or below the last accepted one is ignored. Timestamps from
  the peer are display data, never ordering.
- A tombstone removes the clip from the shared collection only. It never
  deletes the clip from History or from any other collection, and the
  removal goes into a journal the user can undo for 30 days.
- Tombstones are kept until every peer has acknowledged them or has been
  revoked; a revoked peer that returns gets a fresh baseline.
- Per-peer and per-collection caps on manifest entries, clips, bytes,
  tombstones, and sync frequency.
- A peer can only ever add to or remove from the shared set. It cannot
  change a clip, and a different content under an existing id is a
  conflict that is kept as a second clip, never a replacement.

A genuinely paired Mac that turns malicious can still add junk and remove
shared clips. The journal and the caps bound that; nothing eliminates it.

## Threat model, revision 2

| Threat | Mitigation |
|---|---|
| Any LAN host claims a known phone's fingerprint | No privilege is ever tied to an inbound fingerprint; every phone transfer needs the PIN and the dialog |
| Spoofed announcement puts an impostor under the phone's name | Announcements create no trust; a send needs a one-time full-fingerprint comparison on both screens |
| Impostor announces the Mac's own fingerprint to hijack the phone's device entry | ClipKeeper cannot fix the phone, but detects it and warns; the user guide tells phone users to keep LocalSend's PIN on and Quick Save off |
| Brute force of the PIN across many addresses | Per-address, global, and total budgets; hard stop with a new PIN |
| Reads a transfer in flight | TLS only; no plain HTTP, no setting to allow it; redirects refused |
| Floods the server | Connection, body, deadline, throughput, and quota limits; interface policy |
| Malicious image | Phase B only, through a sandboxed helper that re-encodes; TIFF and HEIC never accepted |
| Malicious document | Never parsed; not even saved in this revision |
| Received link used to probe the user's network | Network clips never fetch titles or icons; custom schemes stay text |
| Received text designed to stall the classifier | Detectors run on a bounded sample with a time budget, with tests |
| Path games in a file name | Random local names; the sender's name is display data only |
| Disk exhaustion | Staging quota, free-space floor, own retention domain for received clips |
| Received clip replaces a local one through the duplicate check | Network clips never replace local snapshots |
| Malicious paired Mac on a shared collection | Scope per collection, sequence numbers, undo journal, caps; cannot change a clip or touch History |
| Rogue code already on the Mac, or broken TLS | Out of scope |

## Findings of the review and what changed

The three reviewers agreed on every item marked unanimous.

1. **Inbound fingerprints are unauthenticated.** Unanimous, and the
   headline. Changed: no privilege for phones; mutual TLS for Macs.
2. **Auto-accept must go.** Unanimous. Changed: removed from this phase.
3. **TOFU from announcements lets an impostor receive sends.** Unanimous.
   Changed: full-fingerprint comparison on both screens before a send.
4. **The link title fetch on a received URL is a request forgery path into
   the user's own network.** Unanimous. Changed: a persistent origin mark
   that disables it, and custom schemes stay text.
5. **ImageIO in the main process is the largest real code-execution
   surface.** Unanimous. Changed: images only from Phase B, through a
   sandboxed helper that re-encodes; TIFF and HEIC dropped.
6. **The existing `FileImporter` picks a parser by file extension**, so a
   network file named `x.rtf` would reach the RTF parser. Unanimous.
   Changed: a network-only import path; `FileImporter` is never called on
   network data.
7. **Per-address PIN lockout is bypassed by IPv6 address rotation.**
   Unanimous. Changed: global and total budgets with a hard stop.
8. **A private-address filter is not a trust boundary.** Unanimous.
   Changed: per-interface policy, VPN and virtual interfaces excluded.
9. **Quarantine set after the write leaves a window**, and a check-then-
   write on a user-visible folder invites symlink games. Unanimous.
   Changed: "save other files" removed outright; staging uses exclusive,
   no-follow descriptors.
10. **Tokens need single use, an atomic state machine, and exact length.**
    Unanimous. Changed as described.
11. **A hand-written HTTP parser.** Two of three required a vetted library;
    one accepted a strict hand-written parser. Open as DECISION 3, with
    SwiftNIO recommended.
12. **Received clips can evict local history through retention**, and a
    duplicate can replace a local snapshot. Two of three. Changed: own
    retention domain; no replacement across origins.
13. **Whole-clip packs would carry arbitrary pasteboard types** into AppKit
    decoders and into other apps on paste. One reviewer, on the Mac-to-Mac
    section. Changed: an allowlist of three representations.
14. **Shared-collection manifests need authentication, scope, replay
    protection, and bounded deletion.** One reviewer. Changed as described.
15. **Detector regexes on hostile text.** Confirmed by test before the
    reviews returned: 47 seconds on 200 KB of one character. Fixed in the
    app now, with tests, independent of this feature.
16. **Privacy of announcements.** Two of three. Changed: generic alias and
    model by default; the guide warns that the feature beacons a stable
    identifier on public networks.
17. **Keychain details.** Two of three. Changed: Data Protection keychain,
    non-synchronizable, resident key, fail closed.
18. **Screen lock.** One reviewer. Changed: the server pauses.

## Decisions taken on 2026-10-04

1. The bounded threat model is accepted, with SSH as the bar.
2. Phase A, text only, ships first.
3. SwiftNIO is the HTTP stack.
4. Phones get per-phone PINs and the dialog on every transfer. (The PIN
   length changed in Phase A; see "Phase A as built".)

## Phase A as built

Phase A follows revision 2, with four changes found while building it.
Each one was put to the code reviewers.

1. **PINs are 8 characters, not 24.** Revision 2 assumed that LocalSend
   stores a PIN per device. It does not: its sender asks the user for the
   PIN on every 401 and keeps it only for that transfer
   (`app/lib/provider/network/send_provider.dart`). A 24-character PIN
   typed on a phone for every clip is not usable. The PIN is now 8
   characters from 31 symbols without look-alikes, about 40 bits. With
   the hard stop at 30 wrong PINs, a guess succeeds with a chance below 1
   in 28 billion. A request without a PIN gets 401 and does not count as a
   failure, which is how LocalSend's own server behaves and what makes
   the phone show its PIN prompt.
2. **Discovery replies by multicast.** The protocol allows a multicast
   announcement with `announce` false in place of an HTTPS `register` call
   to the announcer. The Mac uses only that, so it never opens a
   connection to an address that a stranger chose.
3. **Verification uses LocalSend's own Verify page.** LocalSend shows both
   fingerprints, sorted and joined, on the device's Verify page, in text
   mode. ClipKeeper shows the same 128 characters. Before it shows them,
   it fetches `info` over a connection pinned to the announced
   fingerprint, which proves that the device at that address holds that
   certificate. One comparison verifies both directions.
4. **The Secure Enclave replaces the keychain.** The Data Protection
   keychain needs a keychain access group, which needs a paid Apple
   developer certificate. The login keychain ties each item to the exact
   build when the signing certificate has no Team ID, so every rebuild
   asked for keychain access again, and a lookup without the entitlement
   answered "not found", which made a new key at each launch. Now:
   - The identity key is made in the Secure Enclave. Its private part
     never leaves the chip, and no entitlement is needed.
   - The PINs are sealed with ChaCha20-Poly1305 under a key from an ECDH
     agreement of a second Secure Enclave key with its own public key,
     through HKDF. Only this Mac's Secure Enclave can derive it.
   - The certificate is public and is a plain file.
   - The folder is mode 700, the files mode 600. A Mac without a Secure
     Enclave, or an unreadable or altered file, stops the feature.

Also as built:

- The listener binds one socket per IPv4 address of each allowed
  interface, never the wildcard address. IPv6 is not served.
- Plain HTTP, TLS 1.1 and earlier, the loopback address, chunked bodies,
  unknown routes, and wrong methods were each tried against the running
  app and refused.
- The tests drive the real server over TLS on the loopback address: the
  pinned probe, a wrong fingerprint, the PIN flow, refusal, images
  refused, single-use tokens, a busy session, and size limits.

## Code review of Phase A

The same three models reviewed the code, each alone, limited to security:
Claude Fable 5.1, GPT-6 Astra, and Gemini 3.8 Flash. None found a way for
an unauthenticated peer to reach the dialog, the clip store, or the disk.
All three accepted the PIN length, the multicast reply, the Verify page
format, and the network-only import path. GPT-6 Astra rejected the
address-only interface boundary until the sockets were tied to their
interfaces. Every finding below is fixed and, where a test can show it,
tested.

| Finding | Found by | Fix |
|---|---|---|
| A request body that stops after one byte holds a connection | Fable | Body deadline: 10 s plus 8 KB/s; tested on the running app |
| A spoofed announcement un-verifies the real phone | Fable | A mismatch drops the address, not the verification; two addresses with one fingerprint are never shown as verified |
| A cancel, lock, or expiry between the last byte and the store | Fable, Astra | The final check and the store run under one lock |
| Return in another app accepts a dialog that just appeared | Fable | Return arms after 0.7 s |
| `stop()` left accepted connections open | Fable | Accepted connections are tracked and closed |
| One host fills the discovery list | Fable | At most two entries per address |
| Invisible characters in received text | Fable | Zero-width, byte-order, and annotation marks removed; separators become newlines |
| A verification made a PIN that nobody saw | Fable | Send-only devices have no PIN |
| Silent keychain fallback | Fable | Replaced by the Secure Enclave |
| Unbounded reply bodies on a send | Astra | Replies are read with a cap per route; compression refused |
| Binding an address does not bind an interface | Astra | IP_BOUND_IF on every listener and discovery socket; one discovery socket per interface; a failed socket option closes the socket; sends only to an on-link address |
| A netmask change did not restart the listeners | Astra | Masks are part of the interface comparison |
| A discovery flood floods the main thread | Astra | 100 datagrams a second in total; at most two change notices a second; one warning per impersonating address |
| A new PIN or a removal did not end an open session | Astra | Credential generations: a stale PIN ends every authority it gave; tested |
| Shutdown did not stop queued work | Astra | The coordinator closes first, then the sockets; tested |
| A restart while locked unpaused the server | Astra | The lock state lives in the service and is read from the window server at start |
| Discovery read loop without a cap | Gemini | 32 datagrams per wake-up |

## After this phase

- Native ClipKeeper apps for iPhone and Android, speaking the
  ClipKeeper-only authenticated channel, which removes the phone-side
  limits above.
- Automatic clipboard sync per device, opt in, Macs only, behind secret
  detection.
