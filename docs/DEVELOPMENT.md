# Developing Floe


Prototype macOS launcher that runs unmodified Raycast extensions: a SwiftUI panel plus a Bun process per running command.

Contribution requirements, review expectations, and security reporting are in the shared [Thaw/Floe policies](https://github.com/thaw-app/.github).

Requires macOS 26 or later, Bun, Rust/Cargo, and Xcode 27 for the vendored ThawUI Swift 6.4 manifest. Extensions run under your user account without sandboxing; only install extensions you trust.

## Run

    cd runtime && bun install && cd ..
    ./scripts/build-fend.sh
    open Floe.xcodeproj        # ⌘R in Xcode

or install it as `/Applications/Floe.app` with `./scripts/devrun.sh` (`--debug`, `--no-launch`). The script signs
the app with the first valid Apple Development certificate in the keychain (`FLOE_SIGN_IDENTITY` names another), so
Accessibility and the Keychain stay granted from one build to the next. With no certificate the build is ad hoc and
macOS asks again each time, while System Settings goes on showing the old grant as switched on.

⌃⌥Space toggles the panel. ↑↓ select, ↵ runs the primary action, ⌘K opens the action menu, Esc goes back.

`Floe.xcodeproj` is generated from `project.yml` by XcodeGen; edit the spec and run `xcodegen generate`
rather than changing project settings in Xcode. `Package.swift` stays for `swift run` and the CLI checks below.

The Run scheme has two disabled environment variables: `FLOE_AUTORUN` opens a command at launch,
`FLOE_DEBUG` logs focus changes.

## Settings

⌘, in the panel, "Floe Settings" in search, or the menu bar icon. General has the launcher hotkey, launch at login
and whether to include Raycast's installed extensions. Each extension has an on/off switch, its preferences, and
per-command aliases and hotkeys. Password preferences are kept in the Keychain; a build run from Xcode is
signed ad hoc, so macOS asks again after each rebuild, which `devrun.sh` avoids.

Commands with required preferences or arguments ask for them in the panel before they run.

Settings is a process of its own. The launcher starts this same executable again with `--settings`
(`SettingsProcess.swift`), one at a time, and that process ends when its window closes, which gives back the memory
the settings pages took. The launcher builds no settings view. Being the same executable, the settings process
has the app's defaults, Keychain items and permissions. The two keep in step with a few distributed notifications,
all listed in `ProcessLink.swift`: whichever saves the settings, the snippets or the quicklinks says so and the
other reads them again, and the launcher does for Settings what only it can: the updater, the clipboard history,
rescans of scripts and extensions, and quitting. A message is acted on only when it names the other process of the
pair as its sender. The welcome window at first launch is still the launcher's.

## Layout

- `Sources/Floe`: the app: panel, hotkey, app index, and a renderer for the JSON tree the host sends. One folder per
  area, and no Swift file outside a folder:
  - `App`: the entry point and app delegate (`main.swift`), the main menu, the `floe://` link router, the debug
    options, the update rules and the generated credits. Also the launcher's side of Settings: the process handle
    (`SettingsProcess.swift`), the messages (`ProcessLink.swift`) and what the launcher does with them.
  - `Launcher`: the panel's model (`Model.swift`, with one `Model+….swift` per view it drives and one for the keys)
    and its root views (`Views.swift`, `IconView.swift`), its layout and appearance, the Actions menus, the catalog
    of apps and commands with its scans (`Catalog.swift`, which also holds `Paths`), and Markdown.
  - `Search`: ranking and fuzzy matching, the command lookup the App Intents use, and `SearchProviders` (below).
  - `BuiltIn`: what Floe does itself: the calculator, system commands and toggles, System Settings panes, emoji,
    clipboard history, snippets and their expander, quicklinks, the calendar, the file search and its index of file
    names (`FileIndexService.swift`; the index itself is Rust, in `Vendor/FendCore/rust/src/index.rs`), browser tabs,
    menu bar items, script commands and Thaw's actions, with the AppleScript runner and the selection and pasteboard
    helpers.
  - `AI`: Ask AI and the sources that answer a prompt. An answer can be followed up: `AskAIModel` keeps the turns of
    one conversation in memory while the answer view is open and drops them when it closes; none of it is saved or logged.
    A question travels with its earlier turns as an `AIConversation`, and each source is given them its own way
    (`AISources.live`): an API as user and assistant messages, Apple Intelligence as the transcript of a session made
    for that one request, and a command line tool, which starts fresh every time, written out in its prompt
    (`AIConversation.replayedPrompt`). `AIConversation.Limit` caps what is sent again, oldest turns dropped first:
    8 turns and 12,000 UTF-8 bytes, or 6,000 for Apple Intelligence's 4,096 tokens. An extension's `AI.ask` is a
    conversation with no earlier turns.
  - `Extensions`: a running command (`Session.swift` and its extensions), what it asks the app for
    (`HostRequest.swift`), the manifest, the store, menu bar commands, the background scheduler, OAuth, hot reload,
    and the views an extension's forms and errors are drawn with.
  - `Settings`: the settings model (`Settings.swift`), its window, pages and sections, settings search entries,
    import and export, and the Keychain and preference stores. `SettingsMode.swift` is the settings process, and
    `SettingsCatalog.swift` the commands, scripts and apps it lists.
  - `Sync`: settings sync through iCloud, by CloudKit or the key-value store, written to be moved to Thaw as it is.
    It knows records, not Floe's settings (see "Settings sync").
  - `Picker`: `Floe --pick`.
  - `PreferredApps`, `Thaw` and `DroppyCode` are described below. `Tests/FloeTests` has the same folders.
- `runtime/host.ts`: bundles a command, renders it with a custom React reconciler, speaks NDJSON on stdio.
- `runtime/api/index.ts`: the `@raycast/api` stand-in.
- `extensions/`: one folder per extension (`hello` is a sample, `diagnostics` fails on purpose to exercise the error screen).

- `Sources/Floe/Search/SearchProviders`: what the root search is made of. Each provider answers a query with rows to rank,
  to pin on top, to list under a section or to append (`SearchProvider.swift`); `RootSearch.swift` lists the providers
  and merges what they answer. `LauncherModel.refresh()` only builds the context they read.
  - A scope (`SearchScope.swift`) is a search of its own inside the root search: `files invoice`, `clipboard meeting`
    and `menu wifi` show only that scope's rows. It triggers on its keyword, a space and some text; the keyword alone
    is an ordinary search. A scope may deliver rows later through an `AsyncStream`, each batch replacing the last;
    `SearchUpdates` drops batches that arrive for a query that has been replaced.
  - A source (`SearchSource.swift`) is a scope that may also add up to three rows to an ordinary search, in a section
    of its own below the ranked rows and above the appended ones. Each is off until its switch in Settings › Privacy
    is on (`AppSettings.searchSources`), and its keyword works only while it is. `SourceSearch` asks the enabled
    sources after the ranked rows are shown, for queries of three characters or more, and follows each with its own
    `SearchUpdates`. The files source is `FileSearchScope`; the tabs source is `TabSearchSource`.
  - `BuiltIn/BrowserTabs.swift` holds the browsers whose tabs can be listed, one `BrowserApp` entry each, with the scripts that
    list and switch tabs. Add a browser only after reading its scripting definition (`sdef /Applications/<App>.app`).
    The script runner is passed in, so tests never talk to a browser; do not run these scripts from a test.
- `Sources/Floe/PreferredApps`: the apps Floe hands things to instead of doing their work. A role (`AppRole.swift`)
  is a kind of app the user has a preferred one of: what it is handed, the known apps offered by name and what stands
  in when nothing is chosen. `PreferredApps.swift` decides which app a role resolves to and what it is handed, without
  opening anything; it reads the Mac's apps through `AppLookup`, which tests replace. Add a known app only with a
  bundle identifier read from an installed copy's `Info.plist`.
  - The terminal and the editor are handed files and folders, so they share one path: `NSWorkspace` opens the items
    with the app. Notes is handed text, which each app takes its own way, so it has its own adapter (`Notes.swift`):
    a link for Antinote or a custom app, a script for Apple Notes. A new role is a case of `AppRole` plus, when it
    takes text, an adapter like that one.
  - The clipboard role is handed nothing: Clipboard History opens the chosen app, or a link, in place of Floe's own
    history (`ClipboardApp.swift`). `ClipboardApps.destination` decides where the command goes and never falls back
    to Floe's history; `records` is the one place that says whether copies are saved (the role is Floe and the
    switch is on). An app whose history opens from a link goes in `ClipboardApps.links`, with a link confirmed from
    the installed copy.
- `Sources/Floe/Thaw`: code ported from Thaw: hotkeys (key codes, Carbon registry, recorder), the HUD, the About page,
  onboarding and permissions, settings search, the Sparkle updater with its consent sheet, and the App Intents that
  Shortcuts and Spotlight use (`FloeIntents.swift`).
- `Sources/Floe/DroppyCode`: code ported from Droppy Code. Each file keeps Droppy Code's copyright and credit line
  and says what Floe changed; `LICENSES` holds its license and third-party notices.
  - `LoginEnvironment.swift` reads the login shell's environment, which extensions start with, and `Shell.swift` runs
    a tool with a timeout.
  - `AI.ask` is answered by a one-shot run of a command line tool (`TextGeneration.swift`: `claude`, `codex`,
    `opencode` or `pi`, each with no tools of its own) or by a streamed request to an OpenAI-compatible API
    (`ChatCompletionStream.swift`). Settings › General › AI picks between them; the choice and the request an
    extension makes are in `Extensions/HostRequest.swift`, and which tool answers is in `AI/AITool.swift`.
  - `ToolTextStream.swift` reads a tool's JSON lines as they are printed. What a line means is in
    `ClaudeTextStream.swift`, `OpencodeTextStream.swift` and `PiTextStream.swift`, beside each tool's arguments.
  - `HangWatchdog.swift` samples the app when its main thread stops answering for four seconds and writes the stacks
    to `~/Library/Logs/Floe`.
  - `DirectoryWatcher.swift` watches a folder tree with FSEvents. `Extensions/HotReload.swift` uses it to restart an open view
    command when a file under its extension's `src/` or `assets/`, or its `package.json`, is saved. Only local
    extensions with a `src/` folder are watched, never the ones Raycast installed.
- `CREDITS.md` and `Sources/Floe/App/Credits.swift` are written by `scripts/generate-credits.py`; run it after changing a dependency.
- `Vendor/ThawUI`: design system copied from thaw-app/Thaw (commit in `Vendor/ThawUI/UPSTREAM`).
- `Vendor/ThawConcurrency`: Thaw's timeout and one-shot continuation helpers, copied the same way.

## License

AGPL-3.0. ThawUI and the other code from Thaw stay under GPL-3.0, which the AGPL allows combining with. The code from Droppy Code is AGPL-3.0 with the attribution terms in `LICENSES/DroppyCode-LICENSE`. `LICENSES/README.md` says which license covers which folder. Extensions under `extensions/` keep their own licenses.

## Adding an extension

Extensions live in `~/Library/Application Support/Floe/Extensions`; Raycast's installed ones are picked up
from `~/.config/raycast/extensions`. To add a store extension, copy its folder from
https://github.com/raycast/extensions there and run `bun install --ignore-scripts` inside it (a full install:
some extensions import dev dependencies at runtime). Per-extension storage, preferences and cached bundles go to
`…/Floe/Data/<name>`.

The app is self-contained: the build copies `runtime/` and Bun into `Contents/Resources/runtime`. Set
`FLOE_ROOT` to a checkout (or use `swift run`) to work against the checkout's runtime and its `extensions/`
samples instead, including `diagnostics`, which fails on purpose to exercise the error screen.

## Keys

| Key | Where | Does |
|---|---|---|
| ↑↓, Page Up/Down, Home/End | lists, action menu | move |
| ↵ / ⌘↵ | lists | first / second action |
| ⌘K | lists | action menu; type to search it, → and ← in and out of submenus |
| ⌘⇧F | root | add or remove a favorite |
| `files `, `clipboard `, `menu ` then text | root | search only files, the clipboard history or menu bar items |
| ↵ | menu bar search | open the item's menu (needs Accessibility) |
| ↵ / ⌘↵ / ⌘R | Ask AI | ask what is typed, or copy the answer when the field is empty / paste the answer / ask again |
| Esc, ⌘[ | commands | back |
| ⌘, | anywhere | settings |
| ↵, ⌘⇧C | error screen | try again, copy details |

## Tests

    swift test                                   # Swift Testing suites in Tests/FloeTests
    bun --config=runtime/bunfig.toml test ./runtime   # runtime suites in runtime/tests
    ./scripts/coverage.sh --summary              # both, with coverage per measured file

The Swift tests import the app's module directly and never launch it. Logic lives in files that can run
in a test (`Ranking`, `Manifest`, `ViewState`, `MarkdownParser`, `Shortcuts`, `PropFormat`, `Preferences`,
`MenuBarLogic`, `Settings`, `Session`, `CommandLookup`, `ThawHUDPlacement`, `UpdateLogic`, the onboarding sequencer,
permission state and the settings search index); views, the process, the Keychain and Accessibility code are excluded
from coverage in `sonar-project.properties`, which also states the rule. New decision logic belongs in a
measured file with a suite beside it.

## Code style

Floe uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
with Thaw's rules, in `.swiftlint.yml` and `.swiftformat`. CI runs SwiftLint in strict mode. Before a commit:

    swiftformat .
    swiftlint lint --strict

Tests and `Vendor/` are not linted. The size and complexity limits apply to new code only; what predates them is
listed in `.swiftlint.baseline`.

Both targets build in the Swift 6 language mode with the main actor as the default isolation and with approachable
concurrency, which in this mode is two upcoming features, `InferIsolatedConformances` and
`NonisolatedNonsendingByDefault`. `Package.swift` names them; `project.yml` sets `SWIFT_VERSION`,
`SWIFT_STRICT_CONCURRENCY`, `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_DEFAULT_ACTOR_ISOLATION`; keep the two in
step. A type with no annotation is main actor. Values, parsers and scanners that a worker uses are `nonisolated` (an
extension of one needs the word again), and shared state is an actor or a `Mutex`.

Unmarked async code runs where it is called: a `nonisolated` async function called from the main actor runs on the
main thread, and so does a closure of an unmarked async function type. Code that must leave says `@concurrent`: a
function that starts a process, reads or parses a file, waits on another app or decodes a picture, the function type
of a seam the main actor calls for such work, and a `Task` in a main actor type that must not start there. The
compiler does not check this, so a test calls each one it can reach from the main actor and looks at where the work
ran (`WhatLeavesTheMainActorTests`). A helper that only waits for something else stays unmarked.

`@unchecked Sendable`, `nonisolated(unsafe)` and `MainActor.assumeIsolated` each carry a line saying why they are
safe. In a test, what `@Test(arguments:)` reads is `nonisolated`.

## Localization

Every piece of interface text Floe writes is in one String Catalog, `Sources/Floe/Resources/Localizable.xcstrings`.
English is the source and, for now, the only language. The English text is the key, so the app reads the same with
or without the catalog; the catalog only adds to it the plural forms and the numbering of placeholders.

How a string gets there. The compiler finds it (`SWIFT_EMIT_LOC_STRINGS` in `project.yml`), and a build writes what
it found beside the object files. The Xcode app merges that into the catalog after a build; `xcodebuild` does not, so
from the command line run:

    ./scripts/sync-strings.sh          # build, then add new strings and drop the ones no longer in the code
    ./scripts/sync-strings.sh --check  # build, then fail if the catalog would change

Commit the catalog with the change that adds the string. Never write a key into the catalog by hand.

How to write one:

- A SwiftUI label written as a literal (`Text("Favorite")`, `Toggle("Enabled", isOn:)`, `.help("Open Settings")`) is
  already a key. Leave it as it is.
- A plain `String` (a HUD line, a row title, a menu item, an alert, a failure message) is
  `String(localized: "Copied Path", bundle: .floe)`. `Bundle.floe` (`App/Localization.swift`) is the bundle the catalog
  is in: the app in an Xcode build, the module's bundle in a SwiftPM build and in the tests. A bare `String(localized:)`
  reads the main bundle and finds nothing in a `swift build` binary. Use the initializer itself, not a helper around
  it: the compiler only takes the `comment:` from the real one.
- A value goes in by interpolation, so the translator gets the whole sentence with a placeholder:
  `String(localized: "Quitting \(app.name)", bundle: .floe, comment: "The placeholder is an app's name.")`. Never join
  pieces. Where the wording depends on a case, write one whole sentence per case (`AIEndpoint.problem`).
- A count takes its plural forms from the catalog, not from an `if`: `String(localized: "\(total) items", bundle: .floe)`,
  and in the catalog the key `%lld items` varies by plural with `one` and `other` (see that entry; Xcode's catalog
  editor offers "Vary by Plural"). `LocalizationCatalogTests` lists the plural keys, so a new one is added there too.
  An integer in a localized string is written with the locale's grouping: 1,000 items.
- `comment:` is one plain sentence for the translator wherever the English is ambiguous out of context: a single word
  ("Open", "Run", "Copy"), anything with a placeholder, and a sentence that quotes a word the user types.
  A SwiftUI literal has no `comment:` to give, so its comment is written on the entry in the catalog; a sync keeps it.
- One English word with two meanings is two keys, since another language may need two words. The second names its
  use and gives the English apart: `String(localized: "None (tint)", defaultValue: "None", bundle: .floe)`. The System
  Settings panes and the Restart command are written this way.
- Words that only find something in a search are one string, a list separated by commas, which a translator replaces
  with as many terms as the language needs (`String.keywordList`, `String.searchTerms`).
- A label that is not text (`100%`, `0°`) or that only passes text through (`%@`) is marked "Don't translate" in the
  catalog.

What is not localized, and so is a plain `String` or `Text(verbatim:)`: what an extension renders or declares, the
user's own data (app, file, quicklink, snippet and shortcut names, SSH aliases, the query), log lines and the output
of the command line checks, ids, stored settings keys, URLs, key names, the generated credits, release notes, and
prompts sent to an AI tool. Scope keywords (`files`, `clipboard`, `menu`, `tabs`, `ssh`, `shortcuts`, `ask`, `note`)
are commands and stay English; a sentence that mentions one says so in its comment. Text that is not Floe's must
never become a key: no `LocalizedStringKey(someString)`. Where a view only takes a key (ThawUI's `ThawEmptyState`),
pass `.verbatim(text)`, which makes the text an argument of the key.

Search matches a title in the language it is shown in, since the row is built with the localized title, and keywords
are localized lists of extra terms. Nothing is keyed on a title: ids, settings keys and scope keywords are separate
constants.

To try it without a translation, add a second language to the catalog with one string visibly changed, build, and
run with that language: `.build/debug/Floe --search "" -AppleLanguages "(fr)"`, or the same arguments to
`Floe.app/Contents/MacOS/Floe` from an Xcode build. Remove the language afterwards. Text that SwiftUI resolves itself
(the literals in the first point above) is read from the main bundle, so it only changes in the Xcode build; a SwiftPM
binary shows those in English.

Translations come from Crowdin, as Thaw's do: <https://crowdin.com/project/floe>. `crowdin.yml` points Crowdin at the
catalog, and translated languages arrive as pull requests from Crowdin that change that one file. Nobody edits a
translation in the repository: `.github/workflows/block-translation.yml` closes a pull request that only changes the
catalog and is not Crowdin's, with a note that sends its author to the project. The Credits page has a "Help
translate" button that opens it (`translate` in `FloeLinks`). Still to do once languages exist: the translators list
in `CREDITS.md`, which Thaw's `scripts/generate-credits.py` writes from a Crowdin export.

## Releases and updates

Floe updates itself with [Sparkle](https://sparkle-project.org), the same way Thaw does. The pieces:

- `SUFeedURL` and `SUPublicEDKey` in `project.yml` (the Info.plist source). The feed is
  `https://thaw-app.github.io/Floe/appcast.xml`, served from this repository's `gh-pages` branch.
- `Sources/Floe/Thaw/Updates.swift` wraps Sparkle. While `SUPublicEDKey` is empty the app builds no
  updater: "Check for Updates…" is absent from the status menu, the About page has no updates card, and
  General has no "Automatically check for updates" switch. The rules are in `App/UpdateLogic.swift`.
- With a key, the first time Settings opens a sheet asks whether to check automatically. Sparkle does
  nothing before that answer except a check the user starts.
- `.github/workflows/release.yml` builds an existing tag, notarizes it, zips the app, signs an appcast
  item for it with the `SPARKLE_ED25519_PRIVATE_KEY` secret (`prod` environment), attaches the ZIP to the
  GitHub Release beside the DMG, and pushes `appcast.xml` to `gh-pages` after the release is published.
  A tag whose Info.plist has no key skips the Sparkle steps and ships the DMG alone.

Switching updates on, once:

1. `swift build`, then `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account floe`. The private key
   stays in your login Keychain; the command prints the public key.
2. Put the public key in `SUPublicEDKey` in `project.yml` and run `xcodegen generate`.
3. `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account floe -x ~/floe-sparkle.key`, then
   `./scripts/set-secrets.sh` and answer `@~/floe-sparkle.key` for `SPARKLE_ED25519_PRIVATE_KEY`. Delete the file.
4. After the first release has pushed `appcast.xml`, turn on GitHub Pages for thaw-app/Floe: Settings,
   Pages, deploy from the `gh-pages` branch, folder `/`.

Each release:

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml` (and `sonar.projectVersion`),
   run `xcodegen generate`, commit. Sparkle orders builds by `CFBundleVersion`, a whole number that must go
   up every time; the workflow stops if it does not.
2. Tag the commit with the version (`0.2.0`, or `0.2.0-beta.1` for the beta channel) and push the tag.
3. `./scripts/release.sh` picks the tag and dispatches the workflow. Try a dry run first: it builds and
   reports the appcast diff and publishes nothing.

Pushing the appcast needs "Publish release" checked, because the appcast links to the release's ZIP. The
Sparkle tools version in `release.yml` (`sparkle-version` and its checksum) must match `Package.resolved`.

To rehearse an update with a Debug build, serve an appcast locally and point the build at it:
`defaults write org.thaw.floe FloeDebugFeedURL http://localhost:8000/appcast.xml`. Release builds
ignore that key, and without it a Debug build refuses to check.

## Settings sync

Off by default; the switch is in Settings › General. `Sources/Floe/Sync` is the engine and names no type of Floe's:
`SyncRecord.swift` (a record and the merge, with no store or clock in it), `SyncStore.swift` (the store's protocol,
its limits and how a record is written into it), `SyncAvailability.swift` (which store the build is signed for),
`UbiquitousSyncStore.swift` (iCloud's key-value store), the CloudKit store described below, `MemorySyncStore.swift`
(a store and a pretend cloud for tests) and `SyncEngine.swift`.
Floe's part is `Settings/SettingsSync.swift`, the table of what syncs and what stays on one Mac, and
`App/SettingsSyncService.swift`, which runs in the launcher. A stored setting in neither list of the table fails
`SettingsSyncTests` and is not synced.

- One record per item: an alias, a hotkey, a hidden result, a snippet, a quicklink, or a whole setting such as the
  layout. Favorites, snippets and quicklinks have one record per member and one more for their order.
- The newest change wins, by the clock of the Mac that made it; a tie goes to the higher device id. A change made
  after a record was seen is stamped later than that record, so a Mac with a fast clock cannot pin a value. Two Macs
  that change the same record without seeing each other are ordered by their clocks, which may be wrong.
- A removal is a record too, forgotten after 90 days. A Mac away for longer can bring the value back.
- Changes are dated while sync is off as well (`Sync.json` in the support folder), so switching it on merges by age.
  A setting still at its default counts as never changed and is never uploaded. This keeps a fresh Mac's empty
  local cache from overwriting a cloud value before the first download. An explicit edit back to a default still syncs.
- Removing the cloud copy leaves a clear marker. Each Mac remembers markers it has actually seen, not its local
  clock when it enabled sync. A deliberate join accepts an existing marker from the cache or first download;
  a restart with sync already on still obeys an unseen removal.
- The limits are the store's (`SyncLimits`, asked through `SyncStore.limits`). The key-value store takes 1 MB,
  1024 keys and keys of 64 bytes. The engine stops writing at 90% of the first two and says so in the status; a
  longer key is stored under a digest. The number of keys is what runs out first: a test's heavy user (150
  aliases, 60 hotkeys, 60 hidden results, 40 favorites, 200 snippets, 57 quicklinks) is 587 records and 220 KB.
  CloudKit counts no records and limits one to about 1 MB; its record names are ASCII of at most 255 characters,
  so any other key goes under the same digest.
- Extension preferences are one record per extension (`ext/<name>`, `Settings/ExtensionSettingsSync.swift`), because
  the keys run out first: GitHub's 47 preferences are one record of 1.8 KB. The heavy user with 40 extensions of ten
  preferences each is 627 records and 239 KB. A record holds text fields, checkboxes and dropdowns; passwords, files,
  folders and chosen apps are never in one, and a kind added later stays out until it is put on the list.
- An extension's record is merged whole: two Macs that change different preferences of one extension before seeing
  each other both end with the newer record. Merging inside the record would need a time for each preference and an
  engine that sends back what it merged, which it does not do.
- Applying a record writes the values it names to the extension's `preferences.json`, as an edit in Settings does; a
  command reads them when it next starts. A record of an extension that is not installed here, or one that arrives
  while "Include extension settings" is off, is kept (`ExtensionSync.json`) and applied once it can be. Removing an
  extension removes no record. Settings tells the launcher of an edit with `storeChanged(.preferences)`.
- No test touches iCloud. Nothing here has run against either real store, on a signed build or between two Macs.

Which store a build uses is read from its own entitlements (`SyncAvailability.systemBackend`): CloudKit when it has
`com.apple.developer.icloud-container-identifiers` and the `CloudKit` service, the key-value store when it has only
`com.apple.developer.ubiquity-kvstore-identifier`, none otherwise. The container's name comes from the entitlement,
so the folder names none. Nobody has synced with either store, so nothing moves from one to the other.

The CloudKit store is `CKSyncEngine` over the private database: one zone, `Sync`, and one record type, `SyncRecord`,
with one string field, `json`, holding the value as the engine wrote it. The record name is the store key.

- `CloudSyncMirror.swift` is the store without CloudKit. `SyncStore` is asked without waiting, so the store answers
  from a mirror, `SyncMirror.json` in the support folder: what the server is known to hold, each record with the
  server's own fields for its next save, and over them the changes not yet sent. `CKSyncEngine`'s serialized state
  is `SyncState.json` beside it. `CloudSyncCore` takes made-up events (`CloudSyncEvents.swift`) and answers with
  commands for the sync engine and the change to report, which is what the tests drive.
- `CloudSyncRecords.swift` turns an entry into a `CKRecord` and back, and a `CKError` into a failure the core knows.
  `CloudKitSyncStore.swift` owns the `CKSyncEngine` and is its delegate: it translates events, runs the commands
  and writes the two files. It is the only file that needs a signed build and an account, and no test runs it.
- Either file may be lost. Without the state the next fetch starts from nothing and reports no deletions, so what
  the server held is forgotten and read again; without the mirror the state is dropped for the same fetch. Changes
  that waited are kept in the mirror and queued again at every launch and exchange.
- Nothing is sent before a fetch has ended, and the engine is told of fetched changes once per fetch, so it never
  merges with half of what the server holds.
- A save the server rejects because its record changed puts the server's record in the mirror and reports a change.
  The engine then decides by age as for any record and sets its own again if that is the newer; the second save
  carries the server's fields and is taken. A fetched record replaces a waiting change the same way.
- Signing out or switching accounts empties the mirror, deletes the saved state and starts a new `CKSyncEngine`.
  The settings stay, and the engine uploads them to the new account as a first sync does.
- "Remove Settings from iCloud" deletes the zone. The note that switches the other Macs off is saved after the
  server confirms, into a zone made anew, so it is the one record left. A Mac that sees the zone deleted sends
  nothing until its fetch has ended and the note is read. If the removing Mac goes offline between the deletion
  and the note, another Mac can upload its copy again before the note arrives; it still switches off then.
- Data the user deletes in System Settings (iCloud, Manage) arrives as a purged zone: sync switches off on that Mac
  and nothing is uploaded again (`SyncStoreChange.removed`).
- An account without room makes the status say so; the change waits and is sent again at the next exchange. A
  change the server will never take (invalid, not permitted) waits for a new value and is not sent again.
- Push: `CKSyncEngine` makes its own database subscription and registers for remote notifications itself, so the
  app neither calls `registerForRemoteNotifications` nor forwards anything; the build needs the push entitlement.
  Without push, changes arrive at launch and when the panel or Settings opens (`SettingsSyncService.look`, at most
  once a minute for the panel).
- From Apple's documentation and not tried: everything `CloudKitSyncStore.swift` does, the order in which the sync
  engine sends zone and record changes, that it reports the end of every fetch, and whether it reports this Mac's
  own zone deletion back to it. The tests' pretend server behaves as the documentation says the real one does.

Passwords never go through the key-value store. `Settings/Keychain.swift` holds every Keychain call behind
`KeychainAccess` (`SystemKeychain` over the Security framework, `MemoryKeychain` for tests), and `SecretVault` decides
where a secret lives. "Sync passwords with iCloud Keychain" is off by default and its state is a defaults key of its
own (`syncsPasswordsWithKeychain`), outside `AppSettings`, so an import or a sync cannot switch it without the copy.

- Off, every call is the local one it always was. On, extension passwords and the AI key are synchronizable items
  (`kSecAttrSynchronizable` with `kSecUseDataProtectionKeychain`); reads try that item first and the local one second.
  OAuth tokens (`<extension>/oauth/<provider>`) are never synchronizable.
- Switching on copies each local secret, reads the copy back and only then deletes the local item. Where iCloud
  Keychain already holds a different value, the item changed last wins. A write the keychain refuses stays a local
  item and the status row says why; if nothing could be stored the switch goes back off.
- Switching off copies the synchronizable secrets to local items and stops reading them. It deletes none, because
  deleting one deletes it on every device. "Remove Passwords from iCloud Keychain" does that, after a confirmation.
- Clearing a password while on deletes it on every device. A sync write that fails while an older synchronizable
  item can still be read leaves that older value in use, since reads prefer the synchronizable item.
- The switch is offered only when the running process has `com.apple.application-identifier` or
  `keychain-access-groups` (`SecretVault.hasKeychainEntitlement`). No entitlement was added: by Apple's "Sharing
  access to keychain items among a collection of apps", the application identifier is itself an access group and
  the default one when `keychain-access-groups` is absent, and TN3137 says these must come from a provisioning
  profile. Read from the SDK header: a synchronizable item cannot use a "ThisDeviceOnly" accessibility, and updating
  or deleting one affects every device. Not tried: any call to the data protection keychain, on any build.

A build signed ad hoc has no entitlement for iCloud, says "Unavailable" and never opens a store
(`SyncAvailability.systemBackend` asks the running process). Two files hold the entitlements:

- `Resources/Floe.entitlements` is what every build is signed with. It holds what the hardened runtime of a
  release needs to send Apple events and to ask for Calendar, Reminders and Contacts. Without them a release is
  refused with no prompt (tried: an app with the hardened runtime and no Apple events entitlement gets -1743).
- `Resources/Floe-iCloud.entitlements` adds what needs the provisioning profile: iCloud's key-value store,
  CloudKit with the container `iCloud.org.thaw.floe`, push notifications and time-sensitive notifications. An app
  signed with them and without a profile that lists them does not launch, and a release built with this file and
  a profile that lacks the container fails at signing.

To ship sync, in this order. Each step says where it comes from: (code) read in this repository or run here,
(Apple) Apple's documentation or SDK headers, (memory) remembered and not checked.

1. developer.apple.com, Certificates, Identifiers & Profiles, Identifiers: open `org.thaw.floe`. iCloud is on with
   "Include CloudKit support". Click Edit (or Configure) beside iCloud and tick the container
   `iCloud.org.thaw.floe`; if it is not listed, make it first under Identifiers, the "+" button, iCloud
   Containers. Tick Push Notifications in the same list and save. (memory, for where to click; Apple, that
   CloudKit needs the container and the push capability: "Configuring iCloud services", the `CKSyncEngine` header)
2. Profiles: the `Floe Developer ID` profile is a copy of the identifier's capabilities as they were, so it shows
   as invalid after step 1. Open it, click Edit, save, and download the new `.provisionprofile`. (memory)
3. Check the profile before using it: `security cms -D -i Floe_Developer_ID.provisionprofile` prints it, and its
   `Entitlements` must list `com.apple.developer.icloud-container-identifiers` with `iCloud.org.thaw.floe`,
   `com.apple.developer.icloud-services`, `com.apple.developer.aps-environment` and
   `com.apple.developer.ubiquity-kvstore-identifier`. (memory, not run here: there is no profile on this Mac)
4. Replace the secret in the `prod` environment:
   `base64 -i Floe_Developer_ID.provisionprofile | gh secret set APPLE_PROVISIONING_PROFILE --env prod`.
   Do this before a release is built from a commit whose `Floe-iCloud.entitlements` names the container. (code,
   for the secret's name and where the workflows read it)
5. Put the record type in the production schema. CloudKit has two environments for every container. In
   Development a record type and its fields are made the first time a record is saved; Production refuses a save
   of a type or field it does not have. (Apple: `CKContainer`, "Deploying an iCloud container's schema") Which one
   a build uses is its `com.apple.developer.icloud-container-environment` entitlement (Apple: `CKContainer`):
   - A Developer ID release uses Production. The entitlements file does not set the key; the export does:
     `xcodebuild -help` says of `iCloudContainerEnvironment` that it "defaults to Development when development
     signing or Production when distribution signing", and the export action asks for `developer-id`. (code:
     read from this Xcode's help and org-ci's `write-export-options.py`; not tried)
   - A build signed with an Apple Development certificate and a development profile uses Development. This
     repository builds none: it would need `FLOE_PROFILE` set to such a profile and a copy of the entitlements
     with `com.apple.developer.aps-environment` set to `development`. (Apple, for the value; not tried)
   - Since no development build exists to save the first record, make the type by hand. Sign in at
     icloud.developer.apple.com, open CloudKit Database, choose `iCloud.org.thaw.floe` at the top and the
     Development environment. Under Schema, Record Types, click "+", name it `SyncRecord`, add a field named
     `json` of type String, and save. No index is needed: the sync engine fetches changes by zone and runs no
     query. (code, for the names, which are `CloudSyncRecordCoder`'s; memory, for where to click and the index)
   - Then, in the same container, select Deploy Schema Changes on the left, review the pending changes, and
     click Deploy. (Apple: "Deploying an iCloud container's schema") A type or field in production cannot be
     deleted afterwards. (Apple, same page) The zone is the user's data, made by the app, and is not deployed.
     (memory)
6. `project.yml` sets `CODE_SIGN_ENTITLEMENTS: $(FLOE_ENTITLEMENTS)` and
   `PROVISIONING_PROFILE_SPECIFIER: $(FLOE_PROFILE)` on the Floe target, with `Resources/Floe.entitlements` and no
   profile as the defaults. On the target and not on the command line, where they would reach the package
   targets too. org-ci's `configure-signing` installs the profile and outputs its name, `build` takes extra build
   settings, and `export-and-package` names the profile for a bundle identifier. (code)
7. `release.yml` and `build-dmg.yml` pass the secret to `configure-signing`, pass
   `FLOE_ENTITLEMENTS=Resources/Floe-iCloud.entitlements` and `FLOE_PROFILE` to the build when a profile was
   installed, and check the exported app before it is notarized ("Verify iCloud signing"): the profile is inside,
   and the app carries the key-value store, the container and the Production environment. Without the secret
   they sign as before, with no iCloud at all. (code)
8. Before publishing, check the exported app yourself: `codesign -d --entitlements - Floe.app` shows
   `com.apple.developer.ubiquity-kvstore-identifier` with the team id in front,
   `com.apple.developer.icloud-container-identifiers` with `iCloud.org.thaw.floe`,
   `com.apple.developer.icloud-services` with `CloudKit`, `com.apple.developer.aps-environment` with
   `production` and `com.apple.developer.icloud-container-environment` with `Production`; and
   `Floe.app/Contents/embedded.provisionprofile` exists. (code: the output's form was checked here on a scratch
   binary signed ad hoc with these keys) Then install it on two Macs signed in to one iCloud account, switch sync
   on on both, and change an alias on one.

The entitlement keys, and where each comes from: `com.apple.developer.icloud-services` with `CloudKit` and
`com.apple.developer.icloud-container-identifiers` (Apple's entitlement reference, and the entitlements of Apple's
`sample-cloudkit-sync-engine`); `com.apple.developer.aps-environment` (Apple, "Registering your app with APNs": the
Push Notifications capability adds `aps-environment` in iOS and this key in macOS; `production` for a Developer ID
profile is from memory, and step 3 shows what the profile allows).

Read from the code: the build action passes a fixed list of settings (`DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE=Manual`,
the Developer ID identity, the hardened runtime) plus the extra ones a workflow gives it, and the export action
writes `signingStyle manual` with the profile for the bundle identifier. From Apple's documentation or from memory,
and not tried here: that these entitlements need a provisioning profile outside the App Store, that an app signed
with them and without the profile is refused at launch, that the key-value store needs no container, where Xcode
looks for profiles, that an empty `CODE_SIGN_ENTITLEMENTS` means none, that settings given on the command line
reach package targets, that an export with manual signing must be told the profile, and that a Developer ID
profile carries `production` for push and allows the Production environment.

## Checks

    bun runtime/smoke.ts extensions/hello planets          # host only
    .build/debug/Floe --selftest hacker-news frontpage  # Swift ↔ Bun round trip
    .build/debug/Floe --search cal                      # ranked root results
    .build/debug/Floe --icon-check                      # every extension's icon, rendered off screen
    .build/debug/Floe --menubar [query]                 # menu bar items Floe can open
    .build/debug/Floe --panel-snapshot /tmp/p           # root, menu bar and answer views, drawn off screen
    FLOE_BENCH_DUMP=/tmp/s .build/debug/Floe --bench-settings  # settings page timings and snapshots
    bun runtime/survey.ts ~/.config/raycast/extensions      # compatibility across many extensions
    FLOE_SETTINGS_CLOSE_AFTER=3 .build/debug/Floe --settings --page about  # the settings process alone; exits 0 when its window closes
    FLOE_OPEN_SETTINGS=5,20 swift run                   # the launcher opens Settings by itself after 5 and 20 seconds
    printf 'a\nb\n' | FLOE_PICK_AUTO=1 .build/debug/Floe --pick --query b  # the picker, without its panel
    FLOE_AUTORUN=hacker-news/frontpage swift run        # open straight into a command

## Picker

`Floe --pick` lends the search panel to a script, the way dmenu does. It reads one item per line on standard
input (blank lines are dropped), shows them under the search field, and prints the line you choose:

    ls ~/Projects | Floe --pick --prompt "Open project" | xargs -I{} code ~/Projects/{}

`Floe` here is the binary inside the app, `Floe.app/Contents/MacOS/Floe`. `--prompt <text>` sets the search
field's placeholder, `--query <text>` is the text it starts with, and `--index` prints the chosen line's position
in the input, counting from 0 and counting blank lines, instead of its text.

| Exit status | Meaning |
| --- | --- |
| 0 | A line was chosen with Return or a double click, and printed. |
| 1 | Nothing was chosen: Escape, the panel lost focus, or the input had no items. |
| 64 | Standard input is a terminal, or an option is wrong. |

It is its own short process (`Picker/PickerPanel.swift`, with the logic in `Picker/Picker.swift`): it reads the Appearance
settings and starts nothing else of the app. `FLOE_PICK_AUTO=1` prints the first match for `--query` without
showing the panel, and `FLOE_PICK_SNAPSHOT=<file>` saves a picture of the panel drawn off screen.

## Menu bar item search

"Search Menu Bar Items" (root search, or its hotkey in Settings › General) is drawn with the launcher's own
field, rows and bottom bar at the launcher's size, so the panel does not change shape on the way in. It does what
Thaw 3's inspector search panel does. Thaw finds and opens items through MenuBarModel and its own runtime; Floe reads
each app's extras menu bar through the Accessibility API and opens an item by pressing it, so it needs
only the Accessibility permission. It shows no previews of the items, so it never asks for Screen
Recording; items Thaw keeps hidden may not open from here.
