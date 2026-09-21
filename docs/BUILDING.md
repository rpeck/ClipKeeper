# Building ClipKeeper

This guide is for anyone who wants to build ClipKeeper from source: to run
it, to change it, or to package it. It starts with the choice of build method,
then the tools, then the layout of the code. After that come the build
procedures, code signing, what to do before a pull request, dependency
safety, the debug hooks, the steps that build the documentation, and a
troubleshooting FAQ.

## Choose a build method

A build turns the Swift sources into `ClipKeeper.app`. There are two ways to
do that, and they produce the same app. Each method has one script that does
everything: it checks the tools, creates the signing identity on the first
run, builds, signs, and launches. Run the same script again at any time; it
only redoes what is needed.

**SwiftPM method.** The Swift Package Manager compiles the code, and the script
wraps the result into an app bundle. It needs only Apple's free Command Line
Tools, about 2 GB. Choose this method to run the app on your own Mac, to
develop, and to run the tests. It is the method this guide recommends first.

```sh
scripts/build-with-swiftpm.sh run
```

**Xcode method.** Xcode compiles the code from a generated project. It needs
the full Xcode, about 15 GB. Choose this method when you want to work in the
Xcode IDE, or when you build for other people: **a notarized download or an
App Store submission must go through Xcode.**

```sh
scripts/build-with-xcode.sh run
```

Both methods sign the app with the same local identity, so the Accessibility
permission survives rebuilds. See [Code signing](#code-signing).

## Tools

The build script for your method checks these tools before it does anything.
If one is missing, the script stops and prints the command or the link that
installs it. It never installs a tool for you. So run the build script
first; read this list only to know what to expect.

| Tool | Needed by | What it is for | Where to get it |
|---|---|---|---|
| Command Line Tools | both methods | git, the Swift compiler, the macOS SDK. About 2 GB, no Apple account needed. | `xcode-select --install` |
| Xcode 26 | Xcode method | The IDE and the toolchain for notarized and App Store builds. About 15 GB, needs macOS 15. After the install, run `sudo xcodebuild -license accept` once. | Mac App Store, or [developer.apple.com/download](https://developer.apple.com/download/applications/) |
| Homebrew | Xcode method | The package manager that installs XcodeGen. | [brew.sh](https://brew.sh) |
| XcodeGen | Xcode method | Generates the Xcode project from `project.yml`, so the project file stays out of the repository. | `brew install xcodegen` |
| openssl, security | both methods | Used by the signing script. Both ship with macOS. | nothing to install |
| SwiftLint | contributors | Static checks on the Swift sources. CI runs it on every pull request. | `brew install swiftlint` |

## Layout of the code

```
ClipKeeper/
  App/          AppDelegate, main
  Model/        Clip, ClipCollection, PasteboardSnapshot, ClipKind
  Storage/      Database (GRDB + FTS5), BlobStore, ClipStore
  Clipboard/    PasteboardMonitor, ContentClassifier, detectors, Paster, Exporter
  Keys/         KeyCombo, KeyAction, KeyBindingStore
  Shelf/        ShelfPanel, ShelfController, ShelfViewModel, views, EdgeTrigger
  Editors/      TextEditorWindow, CropWindow, CropModel, SaveAsDialog
  Settings/     Settings and onboarding windows
  Support/      Preferences, Accessibility, LoginItem, helpers, DebugSnapshots
ClipKeeperTests/   Swift Testing suites
scripts/
  build-with-swiftpm.sh   the SwiftPM entry point
  build-with-xcode.sh     the Xcode entry point
  bundle-spm.sh           called by build-with-swiftpm.sh: compile and wrap the bundle
  build.sh                called by build-with-xcode.sh: generate the project and run xcodebuild
  make-dev-cert.sh        create the local signing identity
  audit-deps.sh           check the dependency pins and known vulnerabilities
  refresh-screenshots.sh  regenerate docs/images from a demo store
  demo-clips.swift        the sample clips the screenshots show
  make-icon.swift         draw the app icon
docs/           USER-GUIDE.md, BUILDING.md, ROADMAP.md, COMPETITIVE-ANALYSIS.md, PLAN.md
.github/workflows/ci.yml   builds, tests, lints, and audits every pull request
.swiftlint.yml  the lint rules
Package.swift   the SwiftPM manifest; pins every dependency to an exact version
Package.resolved   the exact commit of every dependency, direct and transitive
project.yml     the XcodeGen project definition; pins the same versions
```

The app keeps its data in `~/Library/Application Support/ClipKeeper/`: a
SQLite database and a `blobs` folder with pasteboard snapshots, thumbnails,
and favicons.

## Build with SwiftPM

The script runs the tool checks, creates the signing identity when it is
missing, compiles, writes `build/spm/ClipKeeper.app`, and signs it.

1. Run `scripts/build-with-swiftpm.sh run`. The app launches when the build
   ends.
2. On the first build, macOS asks whether `codesign` may use the new key.
   Click **Always Allow**.

Other modes:

1. `scripts/build-with-swiftpm.sh` builds without a launch.
2. `scripts/build-with-swiftpm.sh test` runs the unit tests. Expect a line
   such as `Test run with 83 tests passed`.
3. `scripts/build-with-swiftpm.sh lint` runs SwiftLint with the repository
   rules.
4. `scripts/build-with-swiftpm.sh check` runs the tests, the lint, and the
   dependency audit. Run it before every pull request. See
   [Before a pull request](#before-a-pull-request).
5. `scripts/build-with-swiftpm.sh install` copies the build to
   `/Applications` and launches it.

The tests run in release mode. One dependency uses the `#Preview` macro,
which only Xcode can expand, and release mode compiles it out. The tests use
Swift Testing, which the Command Line Tools include.

## Build with Xcode

The script checks Xcode, its license, and XcodeGen, creates the signing
identity when it is missing, generates `ClipKeeper.xcodeproj` from
`project.yml`, draws the app icon, and runs `xcodebuild`.

1. Run `scripts/build-with-xcode.sh run`. The app launches when the build
   ends.
2. On the first build, macOS asks whether `codesign` may use the new key.
   Click **Always Allow**.

Other modes:

1. `scripts/build-with-xcode.sh` makes a debug build without a launch.
2. `scripts/build-with-xcode.sh test` runs the unit tests through
   `xcodebuild`. Run them before every pull request, and add tests for the
   code you change. See [Before a pull request](#before-a-pull-request).
3. `scripts/build-with-xcode.sh release` makes a release build.
4. `scripts/build-with-xcode.sh install` makes a release build, copies it to
   `/Applications`, and launches it.

The script sets `DEVELOPER_DIR` to Xcode.app for its own commands, so leave
`xcode-select` as it is. To work in the IDE, open the generated
`ClipKeeper.xcodeproj`.

## Code signing

macOS ties the Accessibility permission to the app's code signature. An
ad-hoc signature changes on every build, and macOS then forgets the
permission after each rebuild. Both build methods therefore sign with a stable
local identity named "ClipKeeper Development". The build scripts create it
on the first run. To create it by hand:

1. Run `scripts/make-dev-cert.sh`. It makes a self-signed certificate,
   imports it into your login keychain, and trusts it for code signing.
2. On the next build, macOS asks whether `codesign` may use the key. Click
   **Always Allow**. If you click Allow, the dialog returns on every build.

macOS records the permission against the signature of the build that asked
for it. A build with a different signature is a different app to macOS, so
the switch in System Settings › Privacy & Security › Accessibility can show
ClipKeeper as on while the running build has no permission. ClipKeeper's
own Settings › General shows the truth for the running build. When the two
disagree, reset the stale entry:

1. Run `tccutil reset Accessibility com.raymondpeck.ClipKeeper`.
2. Launch the app and grant the permission again.

Builds signed with the "ClipKeeper Development" identity never hit this,
because the signature stays the same from build to build.

To sign with an Apple Development certificate instead, for example before an
App Store build:

1. Open Xcode › Settings › Accounts and add your Apple ID.
2. Select the account and click Manage Certificates.
3. Click + and choose Apple Development.
4. In `project.yml`, set `CODE_SIGN_IDENTITY: "Apple Development"` and set
   `DEVELOPMENT_TEAM` to your team ID.
5. Run `scripts/build-with-xcode.sh install`.

## Before a pull request

Every pull request runs the same checks on GitHub Actions, on a macOS
runner: build, tests, lint, and the dependency audit. A red check blocks
the merge. Run the checks on your Mac first, so the review starts from a
green state.

1. Add or extend tests for the code you change. The suites are in
   `ClipKeeperTests`. A bug fix gets a test that fails without the fix.
   New detection logic, conversions, and store behavior get their own
   cases. Pure logic such as `CropModel` and `PasteboardMonitor` is
   designed to be testable without a window; follow that pattern.
2. Run `scripts/build-with-swiftpm.sh check`. It runs the tests, the lint,
   and the dependency audit, and stops at the first failure.
3. Fix every finding. The lint runs in strict mode, so a warning is a
   failure. `swiftlint --fix` corrects the mechanical ones.
4. Update the documentation that describes what you changed: the User
   Guide for behavior, this guide for build or tooling changes.
5. Open the pull request and wait for the CI check.

**What the lint checks.** SwiftLint with the rules in `.swiftlint.yml`. The
set is modest on purpose: it catches force unwraps, force casts, force
tries, and a handful of correctness and consistency rules, and it leaves
line length and file length alone. Deliberate exceptions carry a
`// swiftlint:disable:next` comment with a reason on the line above, and
there are three of them, all in `Accessibility.swift`, where Core
Foundation offers no conditional cast.

## Dependency safety

The app uses four Swift packages, plus two that they pull in. Every one is
built from source on your Mac. None of them runs code at build time, and
none of them ships a binary.

| Package | Use | Size in the app |
|---|---|---|
| MarkdownUI | Markdown rendering | in the binary |
| Highlightr | Syntax colors through highlight.js | 2.1 MB resource bundle |
| KeyboardShortcuts | Global hotkeys and the recorder control | 64 KB |
| GRDB | SQLite with FTS5 | in the binary |
| swift-cmark | Markdown parsing, used by MarkdownUI | in the binary |
| NetworkImage | Image loading, used by MarkdownUI | in the binary |

Expect an app bundle of about 13 MB.

**How the versions are pinned.**
- `Package.swift` and `project.yml` name an exact version for each direct
  dependency, so a build never picks up a newer release by itself.
- `Package.resolved` records the exact git commit of every package, direct
  and transitive, and is committed to the repository. Two builds from the
  same commit of ClipKeeper compile the same dependency source.
- KeyboardShortcuts stays at 1.15.0, because 1.16 adds `#Preview` macros
  that the Command Line Tools cannot expand.

**What the audit checks.** Run `scripts/audit-deps.sh` before you change a
version, and once a month. It:
1. Lists each pinned package with its version and commit.
2. Confirms that `Package.swift`, `project.yml`, and `Package.resolved`
   agree on every version.
3. Confirms that no checked-out package declares a binary target or a build
   plugin.
4. Asks the [OSV](https://osv.dev) vulnerability database about each package
   and version, and prints any known advisory.

**How to update a dependency.**
1. Read the release notes of the new version on GitHub.
2. Change the version in `Package.swift` and in `project.yml`.
3. Run `swift package update <package-name>`, which rewrites
   `Package.resolved`.
4. Run `scripts/audit-deps.sh` and fix anything it reports.
5. Run `scripts/build-with-swiftpm.sh test`.
6. Commit `Package.swift`, `project.yml`, and `Package.resolved` together.

**Where the risk is.** Highlightr runs highlight.js inside JavaScriptCore
to color code. That JavaScript sees the text of every code clip, but the
context has no access to the network, the file system, or the rest of the
app. The other packages parse or store data and make no network requests.
The only network request in ClipKeeper is the link title fetch in the app's
own code, and Settings › Privacy turns it off.

## Debug hooks

The app reads these environment variables at launch. Set them on the command
line in front of the executable.

- `CLIPKEEPER_DATA_DIR=<dir>` uses that folder for the database and blobs
  instead of Application Support. Use it for demos and for tests against a
  clean store.
- `CLIPKEEPER_DEBUG=1` logs every capture with its duration, and every
  pasteboard read slower than 50 ms.
- `CLIPKEEPER_SNAPSHOT_DIR=<dir>` renders the shelf, its overlays, Settings,
  onboarding, the editor, and the crop window to PNG files in that directory
  about fifteen seconds after launch. Add `CLIPKEEPER_SNAPSHOT_QUIT=1` to
  quit afterwards.
- `CLIPKEEPER_ONBOARDING_STEP=<0-3>` opens the welcome window on that page.

Example:

```sh
CLIPKEEPER_SNAPSHOT_DIR=/tmp/snaps CLIPKEEPER_SNAPSHOT_QUIT=1 build/spm/ClipKeeper.app/Contents/MacOS/ClipKeeper
```

## Building the documentation

The documents are Markdown files in `docs/`. GitHub renders them as they
are. The screenshots in `docs/images` come from the snapshot hook above.

To make or refresh the screenshots:

1. Build the app with `scripts/build-with-swiftpm.sh`.
2. Run `scripts/refresh-screenshots.sh`.
3. Review the new files in `docs/images` and commit them.

The script quits ClipKeeper, fills a temporary demo store with the sample
clips in `scripts/demo-clips.swift` so no personal clips appear, renders
every view at a 440 point shelf width, scales each capture, and then
restores your shelf width and relaunches the app. Expect it to take about
half a minute. The captures are 2x Retina, and the script scales each file
to three eighths of its pixel width, so a 440 point shelf becomes a 330
pixel image. Markdown has no size syntax that works on GitHub, so the file
itself carries the size.

## Notes on capture

These notes explain design choices in the capture code, for anyone who
changes it.

- macOS has no clipboard change event. The monitor polls the change count
  every 150 ms.
- Apps write the pasteboard in steps: the change count moves when the types
  are declared, and the data for each type lands afterwards. The monitor
  accepts a change only after two consecutive reads return the same complete
  snapshot, and drops a change that stays incomplete for two seconds.
- The capture reads every type the source app wrote, but skips types the
  pasteboard server translates on demand. Reading a translated type can
  block until the owning app services the request.
- A hidden shelf does not reload or render, so captures never wait on the
  interface.
- highlight.js loads on a background thread at launch, because the load
  takes about a second.

## Troubleshooting FAQ

**The build script says a tool is missing.**
Install it with the command or link the script prints, then run the script
again. The [Tools](#tools) table lists every tool with its source.

**`swift` prints "You have not agreed to the Xcode license agreements".**
Xcode is the selected developer directory but its license is not accepted.
Run `sudo xcodebuild -license accept`. Or leave Xcode aside and use the
SwiftPM method, which sets the Command Line Tools as its own developer
directory.

**The build stops at `codesign` and nothing happens.**
A keychain dialog is waiting, possibly behind other windows. It asks whether
`codesign` may use the "ClipKeeper Development" key. Click **Always
Allow**. If you clicked Allow, the dialog returns on every build; click
Always Allow next time.

**`security find-identity` shows no "ClipKeeper Development" identity.**
Run `scripts/make-dev-cert.sh`. If it reports "MAC verification failed",
your `openssl` is a version that needs the legacy PKCS#12 format; the
script tries both forms, so run it again and report the output if it still
fails.

**Return copies the clip but does not paste it into the app.**
The running build has no Accessibility permission. Open ClipKeeper's
Settings › General and click Request Permission, then turn ClipKeeper on in
System Settings.

**System Settings shows Accessibility on, but ClipKeeper says it is off.**
The entry belongs to a build with a different signature. Run
`tccutil reset Accessibility com.raymondpeck.ClipKeeper`, launch the app,
and grant the permission again. See [Code signing](#code-signing).

**SwiftLint crashes with "Loading sourcekitdInProc.framework failed".**
SwiftLint looked for SourceKit in a toolchain that does not have it. Set
`TOOLCHAIN_DIR` to the Command Line Tools:
`TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint lint`. The
build script's `lint` and `check` modes set it for you.

**`swift test` fails with "external macro implementation type
'PreviewsMacros.SwiftUIView' could not be found".**
A dependency uses `#Preview`, which only Xcode can expand. Run the tests in
release mode, as the build script does:
`swift test -c release -Xswiftc -enable-testing`.

**`scripts/audit-deps.sh` reports a version mismatch.**
`Package.swift`, `project.yml`, and `Package.resolved` must pin the same
version. Follow the update procedure in
[Dependency safety](#dependency-safety), and commit all three files together.

**`scripts/audit-deps.sh` says "OSV: query failed".**
The vulnerability query needs network access to api.osv.dev. Run it again
when you are online. The pin checks still ran.

**A copy from a browser did not show up in the shelf.**
Browsers and Electron apps write the pasteboard in steps. ClipKeeper waits
until two reads agree, then stores the clip, which takes up to a second for
a large image. Launch the app with `CLIPKEEPER_DEBUG=1` to log every
capture with its timing. See [Notes on capture](#notes-on-capture).

**The screenshots came out at the wrong width.**
`scripts/refresh-screenshots.sh` sets the shelf width itself and restores
yours afterwards. If it was interrupted, your width may be left at 440
points; set it again in Settings › General.

**The screenshot script left ClipKeeper stopped, or with a demo store.**
The script relaunches your normal ClipKeeper on exit, and the demo store
lives in a temporary folder that the script removes. If the script was
killed, run `open build/spm/ClipKeeper.app`. Your real data in
`~/Library/Application Support/ClipKeeper` is never touched.

**XcodeGen says `project.yml` is invalid.**
Check the indentation of the last change; YAML is space-sensitive. Run
`xcodegen generate` alone to see the full message.

**Xcode opens the project but the packages do not resolve.**
Open File › Packages › Reset Package Caches, then Resolve Package Versions.
The pinned versions in `project.yml` must exist on GitHub; run
`scripts/audit-deps.sh` to check them.
