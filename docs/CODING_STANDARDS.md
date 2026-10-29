# Coding standards

How code in Floe is written. The [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md)
cover issues, pull requests and sign-off, [Architecture](ARCHITECTURE.md) maps where things live, and
[Development](DEVELOPMENT.md) has the build and test commands.

## Where new code goes

The aim is code where no feature reaches into another. Each part knows only what it was handed.

- **Decisions are plain code.** What to show, what to run and what to do next is worked out by values and functions
  that touch nothing outside themselves, and return what should happen. `PanelLifetime` returns effects and never acts;
  `Ranking`, `CommandLookup` and `UpdateLogic` work the same way. These carry the tests.
- **A feature is handed what it uses.** A feature model takes its stores and an environment, a struct of closures for
  the system, the disk and the other processes, through `init`. `ShellEnvironment`, `AppLookup`, `ModeHost` and
  `ActionHost` are environments; `ClipboardHistoryModel` is given its store. A settings page is handed its stores from
  the process's `SettingsStores`. A feature does not read `.shared`, and a test hands it fakes.
- **Each state has one owner.** One process writes a store; the others keep a copy and read it again when told. The
  stores every process saves announce and reload through `SharedStores`, not through hooks set in each process.
- **Each process is wired in one place.** `main.swift` and `LauncherWindow` for Floe's own process and `SettingsMode`
  for settings make the concrete stores and connect features, stores and messages. They are the only code that names
  the shared instances.
- **`LauncherModel` routes.** It keeps the query, the results and which mode is on screen, and hands work to the
  feature that owns it. New work goes in a feature of its own, not in the model. A feature that owns rows is a
  `RowOwner`: it says what Return, its Actions menu and its keys do on them. `LauncherFeatures` holds the features
  and is the one place that connects them to the model.

## Reuse before writing

- If you'd copy a block, pull it into a shared function.
- Before writing your own ordered set, debounce, timeout or lock, check what Swift and Apple already provide, such as
  `Synchronization.Mutex`, `Observation` and `ContinuousClock`.
- Adding a package changes `Package.resolved` or `runtime/bun.lock` and the dependency scan. Propose it in the issue
  or pull request and say what it replaces.
- Code ported from Droppy Code keeps its copyright and credit line in each file, which also says what Floe changed.

## Comments

Write comments as plain sentences. No headings, bold, bullet lists or tables inside code comments. Say why the code
does something when the code can't show it, such as a macOS quirk or an ordering that matters. Don't narrate what the
next line does.

## Writing

This covers documentation, the changelog, pull request descriptions and the text the app shows.

- Write for the person reading, in plain words. Say what they can do and what happens, and leave out how the code
  does it unless they need that.
- Use sentence case for headings.
- Don't use em dashes or en dashes. Use a period, a comma, a colon or parentheses.
- Refer to a person you don't know as they.
- Link to other files in the repository with relative links.
- Interface text goes in the String Catalog. See [Localization](DEVELOPMENT.md#localization).

## Tests

- Use Swift Testing for Swift and `bun test` for the runtime. Don't add XCTest.
- Where the logic can be isolated, write the failing test first, and add a regression test for each bug fix.
- New decision logic goes in a measured file with a suite beside it. `sonar-project.properties` lists what is
  excluded from coverage and why.
- New code needs at least 80% test coverage on SonarCloud. Don't add files to the coverage exclusions to get there.
- Tests never talk to a real browser, the Keychain or another app. Hand the code a fake through its environment.

## Formatting and lint

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
