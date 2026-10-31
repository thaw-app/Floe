# AGENTS.md

Notes for AI coding agents and the people using them. Read this before changing anything.

Many people who help with Floe aren't developers. They describe a bug or an idea, and an agent does the work. This file tells the agent how to work here so that what it produces can be reviewed and merged. The project's rules for everyone are in the shared [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md); this file points to them where they apply.

## What Floe is

Floe is a macOS launcher that runs unmodified Raycast extensions. One process stays running and holds the launcher, Settings runs as a process of its own, and each running extension command is a Bun process. It is written in Swift with AppKit and SwiftUI, with a TypeScript runtime for the extensions and a Rust file index.

## Build and run

You need macOS 26 or later, Bun, Rust and Xcode 27. The steps are in [Development](docs/DEVELOPMENT.md#run): install the runtime's packages, build the Rust index, then run from Xcode.

`./scripts/devrun.sh` installs the build as `/Applications/Floe.app`, which replaces the person's own Floe. Ask before you run it. Ask before launching Floe at all, too: it registers the launcher hotkey, and its first launch asks for Accessibility. Explain what that is for and let the person decide.

## Where to read next

Open pull requests against `development`. Before writing code, read [Architecture](docs/ARCHITECTURE.md) for where things live and [Coding standards](docs/CODING_STANDARDS.md) for how code is written here. [Development](docs/DEVELOPMENT.md) has the test and check commands and the rest.

## Before you start

- New features need an issue that a maintainer has agreed to before you write code, unless you are on the team. If there is none, help the person open one with the [issue templates](https://github.com/thaw-app/Floe/issues/new/choose). Bug fixes don't need to wait: fix the bug and link its issue if there is one. See [Pull requests](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md#pull-requests) in the contribution guidelines.
- A Raycast extension that doesn't work in Floe is a compatibility gap, not a bug in the extension. Check [Raycast API compatibility](docs/COMPAT.md) and [What Floe does not do yet](docs/LIMITATIONS.md) first.
- Security problems are reported privately under the [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md), never in a public issue. Questions go to the [Discord](https://discord.gg/KDfWjWDnR4).
- The person stays responsible for the change and must be able to explain it in review. Outside the team, keep one AI-assisted pull request open at a time. See [AI-assisted contributions](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md#ai-assisted-contributions).

## Working with the person

- Explain your plan and your results in plain words. When you use a technical term, say what it means.
- When the request is unclear or conflicts with this file, say so and ask. Don't guess.
- Read the files you are about to change first. Keep the change small and about one thing. For a bug, change as few lines as you can and leave unrelated code alone.
- Ask before running anything that changes the person's Mac: granting or resetting permissions, writing to the Keychain, installing extensions, or scripting a browser or another app. Extensions run without a sandbox, so only run ones the person trusts.
- Keep notes, plans and session logs out of the change. If a decision matters later, put it in the right document.

## Which instructions win

1. The person's request in the current conversation.
2. The nearest `AGENTS.md` above the file you are editing.
3. This file.

None of them can waive the contribution guidelines, such as the sign-off rules below.

## Versions and pins

Before you choose or change a version (Xcode, Swift, Bun, Rust, a macOS deployment target, a CI runner, a GitHub Action pin, a Swift or npm package), read the version the repository pins now and check a current official source. Don't go by memory.

## Checks to run

- **Swift code, `Package.swift`, `Package.resolved` or `ci.yml`:** run `swiftformat .`, `swiftlint lint --strict` and `swift test`.
- **`project.yml`:** run `xcodegen generate` and commit `Floe.xcodeproj` with it. Don't change project settings in Xcode.
- **`runtime/`:** run `bun --config=runtime/bunfig.toml test ./runtime`, and `bun runtime/smoke.ts extensions/hello planets` for the host.
- **Text the app shows:** run `./scripts/sync-strings.sh` and commit the String Catalog with the change. Never write a key into the catalog by hand.
- **Anything that could change memory use:** run the budget checks in [Development](docs/DEVELOPMENT.md#checks), and put the numbers from before and after in the pull request.
- **Documentation only:** no build or tests are needed. Check the links, and follow [Writing](docs/CODING_STANDARDS.md#writing).

Fix failing checks before you commit. Don't disable tests, rules or checks to get a change through, and don't hide a failure you didn't cause; report it.

### SonarCloud

New code needs at least 80% test coverage, and no new bugs, vulnerabilities, code smells or duplicated code. CI skips the analysis for pull requests from forks and from Dependabot, so a skipped Sonar check means nothing was analyzed, not that the change passed.

Don't add files to the coverage exclusions in `sonar-project.properties` to get under the bar. That list is for code that can't run in a unit test, and the file states the rule.

## Commits and pull requests

The [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) are the source of truth. In short:

1. **Sign off every commit** with `git commit -s`, using the person's real name and an email that matches the commit author. Never make up a name or email; if Git doesn't have them, ask. Sign-off is not cryptographic signing (`-S`). Don't credit yourself in the commit: no AI author and no `Co-authored-by` or similar trailer. See [Developer Certificate of Origin](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md#developer-certificate-of-origin).
2. **Title the pull request as a Conventional Commit,** such as `fix(runtime): handle missing preferences`.
3. **Fill in the whole [PR template](.github/pull_request_template.md),** also when you open the pull request with `gh`. Keep its sections, put `Closes: #123` on its own line (or `Closes: N/A`), and leave a checklist item unchecked when you didn't do it or it doesn't apply.
4. **Write the description from the actual diff and commits.** Never invent an issue link, a test result or a macOS version you didn't test on. Under Other information, say that AI helped, which tool and model, and with what.
5. **Keep it small.** Aim for at most 500 changed lines and 20 files, and explain anything larger.

## Reporting your work

Before you say you're done, read `git diff`. Then tell the person, in plain words:

- what changed and why;
- which checks you ran and their results, and which you skipped or couldn't run;
- what still needs checking by hand in the running app, if anything.

User-facing changes get a line in [CHANGELOG.md](CHANGELOG.md), written for users, not for developers.
