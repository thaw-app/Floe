# Floe architecture

A map of Floe's processes and code, not an API reference. [Development](DEVELOPMENT.md) has the build steps and the
details of each part, and [Coding standards](CODING_STANDARDS.md) says how code is written here.

Floe is a macOS launcher that runs unmodified Raycast extensions. It is written in Swift with AppKit and SwiftUI, with
a TypeScript runtime that Bun runs for extensions and a Rust file index.

## Processes

```text
┌────────────────────────────────────────────┐
│ Floe (stays running)                       │
│  hotkeys, status item, launcher window,    │
│  sync, background extensions, clipboard    │
│      │ spawns                 │ spawns     │
│      ▼                        ▼            │
│  Settings process         Bun, one per     │
│  (while Settings          running command  │
│   is open)                (runtime/host.ts)│
└────────────────────────────────────────────┘
```

- Floe's own process stays running and holds everything that has to answer at once: the hotkeys, the status item,
  the launcher window, the updater, sync, background extensions and the clipboard recorder. It gives memory back
  when the launcher has been closed a while. See [One process, and Settings](DEVELOPMENT.md#one-process-and-settings).
- Settings is a process of its own, started when Settings opens and gone when it closes. The two processes talk
  through `ProcessLink`, and each store has one process that writes it.
- Each running extension command is a Bun process. `runtime/host.ts` bundles the command, renders it with a custom
  React reconciler and speaks NDJSON over stdin and stdout; `runtime/api/index.ts` stands in for `@raycast/api`.
  Extensions run under the user's account without a sandbox.
- The file index is Rust (`Vendor/FloeRust`), built by `scripts/build-rust.sh` and called from Swift.

Floe stores its data on the Mac: extensions and their data under `~/Library/Application Support/Floe`, the file
index under `~/Library/Caches/Floe`, passwords in the Keychain, and hang reports under `~/Library/Logs/Floe`. Settings
can sync through iCloud; see [Settings sync](DEVELOPMENT.md#settings-sync).

## Where the code lives

- `Sources/Floe`: the app: panel, hotkey, app index, and a renderer for the JSON tree the host sends. One folder per
  area, and no Swift file outside a folder:
  - `App`: the entry point and app delegate (`main.swift`), the main menu, the `floe://` link router and what decides
    what a link is (`IncomingLink.swift`, which `Fuzzing` compiles on its own), the debug
    options, the update rules and the generated credits. Also the launcher's side of Settings: the process handle
    (`SettingsProcess.swift`), the messages (`ProcessLink.swift`) and what the launcher does with them.
  - `Launcher`: the panel's model (`Model.swift`, with one `Model+….swift` per view it drives and one for the keys)
    and its root views (`Views.swift`, `IconView.swift`), its layout and appearance, the Actions menus, the catalog
    of apps and commands with its scans (`Catalog.swift`, which also holds `Paths`), and Markdown.
  - `Search`: ranking and fuzzy matching, the command lookup the App Intents use, and `SearchProviders` (below).
  - `BuiltIn`: what Floe does itself: the calculator, system commands and toggles, System Settings panes, emoji,
    clipboard history, snippets and their expander, quicklinks, the calendar, the file search and its index of file
    names (`FileIndexService.swift`; the index itself is Rust, in `Vendor/FloeRust/rust/src/index.rs`, and is saved
    to `~/Library/Caches/Floe` so a later launch reads it back and asks FSEvents only for what changed since; iCloud
    Drive sits inside `~/Library`, which the walk of the home folder skips, so it has a second index of its own), browser tabs,
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
    import and export, and the Keychain and preference stores. `SettingsMode.swift` is the settings process. It lists
    commands, scripts and apps from a `CatalogStore` (in `Launcher`) of its own, as the launcher does.
  - `Sync`: settings sync through iCloud, by CloudKit or the key-value store, written to be moved to Thaw as it is.
    It knows records, not Floe's settings (see [Settings sync](DEVELOPMENT.md#settings-sync)).
  - `Picker`: `Floe --pick`.
  - `PreferredApps`, `Thaw` and `DroppyCode` are described below. `Tests/FloeTests` has the same folders.
- `runtime/host.ts`: bundles a command, renders it with a custom React reconciler, speaks NDJSON on stdio.
- `runtime/api/index.ts`: the `@raycast/api` stand-in.
- `extensions/`: one folder per extension (`hello` is a sample, `diagnostics` fails on purpose to exercise the error screen).

- `Sources/Floe/Search/SearchProviders`: what the root search is made of. Each provider answers a query with rows to rank,
  to pin on top, to list under a section or to append (`SearchProvider.swift`); `RootSearch.swift` lists the providers
  and merges what they answer. `LauncherModel.refresh()` only builds the context they read.
  - Dictionary answers are read by `BuiltIn/DefinitionSearch.swift` off the main thread. It keeps only the current
    query's answer, drops late results, and hands the entry to `DefinitionSearchProvider` through `SearchContext`.
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
    history (`ClipboardApp.swift`). Floe's own history is parked by `ClipboardApps.ownHistoryIsParked`: nothing is
    saved, the pasteboard is not watched, and the command asks for an app until one is chosen. `ClipboardApps.destination` decides where the command goes and never falls back
    to Floe's history; `records` is the one place that says whether copies are saved (the role is Floe and the
    switch is on). An app whose history opens from a link goes in `ClipboardApps.links`, with a link confirmed from
    the installed copy.
- `Sources/Floe/Thaw`: code ported from Thaw that stays Floe's: the Carbon hotkey registry, onboarding's steps and the
  permission model, settings search's index and ranking, the Sparkle updater, and the App Intents that Shortcuts and
  Spotlight use (`FloeIntents.swift`). The views they draw through are in the ThawUI package.
- `Sources/Floe/DroppyCode`: code ported from Droppy Code. Each file keeps Droppy Code's copyright and credit line
  and says what Floe changed; `LICENSES` holds its license and third-party notices.
  - `LoginEnvironment.swift` reads the login shell's environment, which extensions start with, and `Shell.swift` runs
    a tool with a timeout.
  - `AI.ask` is answered by a one-shot run of a command line tool (`TextGeneration.swift`: `claude`, `codex`,
    `opencode` or `pi`, each with no tools of its own) or by a streamed request to an OpenAI-compatible API
    (`ChatCompletionStream.swift`). Settings › AI picks between them; the choice and the request an
    extension makes are in `Extensions/HostRequest.swift`, and which tool answers is in `AI/AITool.swift`.
  - `ToolTextStream.swift` reads a tool's JSON lines as they are printed. What a line means is in
    `ClaudeTextStream.swift`, `OpencodeTextStream.swift` and `PiTextStream.swift`, beside each tool's arguments.
  - `HangWatchdog.swift` samples the app when its main thread stops answering for four seconds and writes the stacks
    to `~/Library/Logs/Floe`.
  - `DirectoryWatcher.swift` watches a folder tree with FSEvents. `Extensions/HotReload.swift` uses it to restart an open view
    command when a file under its extension's `src/` or `assets/`, or its `package.json`, is saved. Only local
    extensions with a `src/` folder are watched, never the ones Raycast installed.
- `CREDITS.md` and `Sources/Floe/App/Credits.swift` are written by `scripts/generate-credits.py`; run it after changing a dependency.
- [ThawUI](https://github.com/thaw-app/ThawUI), a dependency: the controls, styles and shared pages Thaw and Floe both use. ThawUI holds no text of its own; `Thaw/ThawUIWords*.swift` gives it Floe's.
- `Fuzzing`: the fuzzing harness and its corpus, a package of its own. `.github/workflows/fuzz.yml` runs it nightly and on any change to it.

The security reasoning is in the [assurance case](ASSURANCE_CASE.md), and what Floe exposes to or asks of the outside is in [External interfaces](INTERFACES.md).

## Licenses

Floe is AGPL-3.0. Code from Thaw and the ThawUI package stay GPL-3.0, and code from Droppy Code keeps its
attribution terms. `LICENSES/README.md` says which license covers which folder, and extensions under `extensions/`
keep their own.
