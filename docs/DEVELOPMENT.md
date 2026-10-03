# Developing Floe


Prototype macOS launcher that runs unmodified Raycast extensions: a SwiftUI panel plus a Bun process per running command.

Contribution requirements, review expectations, and security reporting are in the shared [Thaw/Floe policies](https://github.com/thaw-app/.github).

Requires macOS 26 or later, Bun, and Xcode 27 for the vendored ThawUI Swift 6.4 manifest. Extensions run under your user account without sandboxing; only install extensions you trust.

## Run

    cd runtime && bun install && cd ..
    open Floe.xcodeproj        # ⌘R in Xcode

or install it as `/Applications/Floe.app` with `./scripts/devrun.sh` (`--debug`, `--no-launch`).

⌃⌥Space toggles the panel. ↑↓ select, ↵ runs the primary action, ⌘K opens the action menu, Esc goes back.

`Floe.xcodeproj` is generated from `project.yml` by XcodeGen; edit the spec and run `xcodegen generate`
rather than changing project settings in Xcode. `Package.swift` stays for `swift run` and the CLI checks below.

The Run scheme has two disabled environment variables: `FLOE_AUTORUN` opens a command at launch,
`FLOE_DEBUG` logs focus changes.

## Settings

⌘, in the panel, "Floe Settings" in search, or the menu bar icon. General has the launcher hotkey, launch at login
and whether to include Raycast's installed extensions. Each extension has an on/off switch, its preferences, and
per-command aliases and hotkeys. Password preferences are kept in the Keychain; with the default ad hoc signing,
macOS asks again after each rebuild, so set a signing identity in `project.yml` if that gets old.

Commands with required preferences or arguments ask for them in the panel before they run.

## Layout

- `Sources/Floe`: the app: panel, hotkey, app index, and a renderer for the JSON tree the host sends.
- `runtime/host.ts`: bundles a command, renders it with a custom React reconciler, speaks NDJSON on stdio.
- `runtime/api/index.ts`: the `@raycast/api` stand-in.
- `extensions/`: one folder per extension (`hello` is a sample, `diagnostics` fails on purpose to exercise the error screen).

- `Sources/Floe/Thaw`: hotkey code ported from Thaw (key codes, Carbon registry, recorder).
- `Vendor/ThawUI`: design system copied from thaw-app/Thaw (commit in `Vendor/ThawUI/UPSTREAM`).

## License

GPL-3.0, because it includes ThawUI from Thaw. Extensions under `extensions/` keep their own licenses.

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
| ↵ | menu bar search | open the item's menu (needs Accessibility) |
| Esc, ⌘[ | commands | back |
| ⌘, | anywhere | settings |
| ↵, ⌘⇧C | error screen | try again, copy details |

## Tests

    swift test                                   # Swift Testing suites in Tests/FloeTests
    bun --config=runtime/bunfig.toml test ./runtime   # runtime suites in runtime/tests
    ./scripts/coverage.sh --summary              # both, with coverage per measured file

The Swift tests import the app's module directly and never launch it. Logic lives in files that can run
in a test (`Ranking`, `Manifest`, `ViewState`, `MarkdownParser`, `Shortcuts`, `PropFormat`, `Preferences`,
`MenuBarLogic`, `Settings`, `Session`); views, the process, the Keychain and Accessibility code are excluded
from coverage in `sonar-project.properties`, which also states the rule. New decision logic belongs in a
measured file with a suite beside it.

## Checks

    bun runtime/smoke.ts extensions/hello planets          # host only
    .build/debug/Floe --selftest hacker-news frontpage  # Swift ↔ Bun round trip
    .build/debug/Floe --search cal                      # ranked root results
    .build/debug/Floe --icon-check                      # every extension's icon, rendered off screen
    .build/debug/Floe --menubar [query]                 # menu bar items Floe can open
    .build/debug/Floe --panel-snapshot /tmp/p           # root and menu bar views, drawn off screen
    FLOE_BENCH_DUMP=/tmp/s .build/debug/Floe --bench-settings  # settings page timings and snapshots
    bun runtime/survey.ts ~/.config/raycast/extensions      # compatibility across many extensions
    FLOE_AUTORUN=hacker-news/frontpage swift run        # open straight into a command

## Menu bar item search

"Search Menu Bar Items" (root search, or its hotkey in Settings › General) uses the look of Thaw 3's
inspector search panel, the one Thaw opens from its menu bar icon. Thaw finds and opens items through MenuBarModel and its own runtime; Floe reads
each app's extras menu bar through the Accessibility API and opens an item by pressing it, so it needs
only the Accessibility permission. Previews are captured with ScreenCaptureKit when Screen Recording
is allowed; items Thaw keeps hidden have no preview and may not open from here.
