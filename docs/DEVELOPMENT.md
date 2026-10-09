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
`defaults write com.thaw.floe FloeDebugFeedURL http://localhost:8000/appcast.xml`. Release builds
ignore that key, and without it a Debug build refuses to check.

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
