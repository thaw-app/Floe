# Credits

Who translates Floe and what it is built from. This file is written by
`scripts/generate-credits.py`; change the script and run it again instead of editing it.
The people who contribute code and documentation are on the repository's
[contributors page](https://github.com/thaw-app/Floe/graphs/contributors).

## Translators

Floe is translated by volunteers on [Crowdin](https://crowdin.com/project/floe). No language is
finished yet; the people who translate it will be listed here. To help, or to ask for a
language, join the project there.

## Built from

- [Thaw](https://github.com/thaw-app/Thaw): ThawUI, ThawConcurrency, the hotkey code, the HUD, the glass styles, the Privacy pane, the About and acknowledgements pages, the diagnostic logger, the release notes reader and the search panel design. Copyright © 2026 Toni Förster et al. GPL-3.0.
- [Droppy Code](https://gitlab.com/droppyformac1/droppy-code): Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app. Floe uses its login shell environment, its process runner, the tools and the streamed API request that answer AI.ask and Ask AI, its reading of the claude tool's streamed answer, the way it starts pi and hands opencode its configuration, its hang watchdog and the folder watcher behind hot reload, each modified for Floe and used with his permission. AGPL-3.0.
- [CompactSlider](https://github.com/buh/CompactSlider) `2.1.0`: Used by ThawUI. MIT.
- [Sparkle](https://sparkle-project.org) `2.10.0`: Checks for updates and installs them. MIT.
- [swift-subprocess](https://github.com/swiftlang/swift-subprocess) `1.0.0`: Starts and stops the process an extension runs in. Apache-2.0.
- [swift-system](https://github.com/apple/swift-system) `1.8.1`: Used by swift-subprocess. Apache-2.0.
- [swift-markdown](https://github.com/swiftlang/swift-markdown) `0.9.0`: Reads the Markdown in detail views. Apache-2.0.
- [swift-cmark](https://github.com/swiftlang/swift-cmark) `0.9.0`: Used by swift-markdown. BSD-2-Clause.
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) `1.8.2`: Reads the command line options. Apache-2.0.
- [swift-algorithms](https://github.com/apple/swift-algorithms) `1.2.1`: Picks the best matches and drops repeats in lists. Apache-2.0.
- [swift-numerics](https://github.com/apple/swift-numerics) `1.1.1`: Used by swift-algorithms. Apache-2.0.
- [swift-async-algorithms](https://github.com/apple/swift-async-algorithms) `1.1.3`: Waits for typing and folder changes to settle. Apache-2.0.
- [swift-collections](https://github.com/apple/swift-collections) `1.6.0`: Used by swift-async-algorithms. Apache-2.0.
- [fend](https://github.com/printfn/fend) `1.5.8`: Calculates and converts units in the search. MIT.
- [nucleo](https://github.com/helix-editor/nucleo) `0.3.1`: Matches file names in the fast file search. MPL-2.0.
- [ignore](https://github.com/BurntSushi/ripgrep/tree/master/crates/ignore) `0.4.33`: Walks the home folder for the fast file search. MIT.
- [Rayon](https://github.com/rayon-rs/rayon) `1.12.0`: Matches file names on several cores at once. MIT.
- [Bun](https://bun.sh): Runs extensions. MIT.
- [React](https://react.dev) `^19.3.0`: Renders extensions. MIT.
- [react-reconciler](https://react.dev) `^0.34.0`: Turns what an extension renders into Floe's views. MIT.
- [Raycast extensions](https://github.com/raycast/extensions): The API Floe implements; each extension keeps its own license.

Raycast is a trademark of Raycast Technologies Inc. Floe is not affiliated with Raycast.
