# Floe

<!-- Badges: shieldcn, as in Thaw's README (light/dark) -->
<p align="center">
  <a href="https://discord.gg/KDfWjWDnR4"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/Discord-join.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=discord&amp;" /><img alt="Discord" src="https://www.shieldcn.dev/badge/Discord-join.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=discord&amp;" /></picture></a>
  <a href="https://sonarcloud.io/summary/overall?id=thaw-app_Floe"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/sonar/quality-gate/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=sonarqubecloud" /><img alt="Sonar quality gate" src="https://www.shieldcn.dev/sonar/quality-gate/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=sonarqubecloud" /></picture></a>
  <a href="https://sonarcloud.io/component_measures?id=thaw-app_Floe&amp;metric=reliability_rating"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/sonar/reliability/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=sonarqubecloud" /><img alt="Sonar reliability rating" src="https://www.shieldcn.dev/sonar/reliability/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=sonarqubecloud" /></picture></a>
  <a href="https://sonarcloud.io/component_measures?id=thaw-app_Floe&amp;metric=security_rating"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/sonar/security/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=sonarqubecloud" /><img alt="Sonar security rating" src="https://www.shieldcn.dev/sonar/security/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=sonarqubecloud" /></picture></a>
  <a href="https://sonarcloud.io/component_measures?id=thaw-app_Floe&amp;metric=sqale_rating"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/sonar/maintainability/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=sonarqubecloud" /><img alt="Sonar maintainability rating" src="https://www.shieldcn.dev/sonar/maintainability/thaw-app_Floe.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=sonarqubecloud" /></picture></a>
</p>

<p align="center">
  <b>The open source launcher for macOS.</b>
</p>

<p align="center">
  <a href="https://github.com/thaw-app/Floe/releases/latest">Download</a> ·
  <a href="#features">Features</a> ·
  <a href="#build">Build</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://discord.gg/KDfWjWDnR4">Discord</a>
</p>

<p align="center">
  <img alt="Floe's launcher with suggestions and commands under the search field" src="docs/images/floe.jpg" width="800" />
</p>

## Features

- **One hotkey, one search.** Applications, commands, quicklinks and System Settings panes, ranked by how often and how recently you use them. Aliases, hotkeys and favorites for the ones you use most.
- **Raycast extensions, unmodified.** Including the ones Raycast has already installed, on a Bun runtime inside the app, with an Extension Store page to install and update them.
- **The basics, built in.** Clipboard history, snippets, emoji, file search, calendar, a calculator with unit conversion, system commands, the menu bar's items from the keyboard, and, once you switch it on, the shortcuts you made in Apple's Shortcuts app, run by name.
- **Your own apps, not replacements for them.** Pick the terminal, editor, browser, notes app and clipboard manager you already use, and Floe hands work to them, down to a host from your SSH configuration, which opens in your terminal.
- **Ask AI.** `ask` and a question shows the answer in the launcher, and you can follow it up there. You choose who answers: a command line tool you are already signed in to (`claude`, `codex`, `opencode` or `pi`), Apple Intelligence on your Mac, or an OpenAI-compatible API. A switch keeps all AI on your Mac.
- **Works with [Thaw](https://github.com/thaw-app/Thaw).** Thaw 3's actions are in the search, and the launcher can follow Thaw's menu bar appearance.
- **Private.** No analytics, no telemetry, no account. The Privacy page in Settings lists every permission and everything Floe contacts.

The [changelog](CHANGELOG.md) has the full list.

## Install

Download Floe from the [releases page](https://github.com/thaw-app/Floe/releases/latest), open the disk image and move Floe to Applications. It is signed and notarized, updates itself, and needs macOS 26 or later.

Floe is early. Extensions run under your user account without a sandbox, so install only the ones you trust.

## Build

Building from source needs Xcode 27 and [Bun](https://bun.sh).

```sh
cd runtime && bun install && cd ..
./scripts/devrun.sh
```

[Development](docs/DEVELOPMENT.md) covers the layout of the tree, the tests and the diagnostics.

## Not built yet

- OAuth sign-in for extensions, other than GitHub and GitLab through their command line tools. They use a token preference for now.
- `launchCommand`, deeplinks, AI tools, the grid layout, and Swift or Rust helpers in extensions.
- Searching your notes, searching an app's menus, and AI chat.
- iCloud integration, the same as Thaw's.

## Roadmap

What we plan to work on next, in this order. The order can change.

1. Documentation, and Floe's section on the Thaw website. It starts with a guide for extension authors: how to run a local extension in Floe, what works and what does not.
2. OAuth sign-in for extensions beyond GitHub and GitLab.
3. The grid layout, `launchCommand` and deeplinks.
4. Searching the front app's menus, built on the menu scanner in [CMD-Z](https://github.com/stonerl/CMD-Z) and shared with Thaw.
5. A fuzzy file finder with its own index.
6. iCloud integration, the same as Thaw's.

Later: a small `@floe/api` package for what Raycast's API cannot express, searching your notes, and calculator history.

Window management is not under consideration unless it becomes a requested feature. There are many window managers already, and Floe can work with them instead of recreating one.

We are open to considering every request during our early releases. [Open an issue](https://github.com/thaw-app/Floe/issues) to ask for something.

## Contributing

Read the shared [contribution policy](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md), [security policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md) and [code of conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md).

<p align="center">
  <a href="https://github.com/thaw-app/Floe/graphs/contributors"><img alt="contributors" src="https://shieldcn.dev/contributors/thaw-app/Floe.svg?title=false&amp;size=40&amp;names=true&amp;titleAlign=center&amp;limit=100" /></a>
</p>

## Acknowledgments

Floe shares its design system and much of its design with [Thaw](https://github.com/thaw-app/Thaw), its sibling in the same organization. It also uses code from [Droppy Code](https://getdroppycode.app) by Jordy Spruit, with his permission, and implements the [Raycast extensions](https://github.com/raycast/extensions) API. [Credits](CREDITS.md) lists what Floe takes from each, and every package it is built from.

Raycast is a trademark of Raycast Technologies Inc. Floe is not affiliated with Raycast.

## License

[AGPL-3.0](LICENSE). Code ported from other projects keeps its own terms; [LICENSES](LICENSES/README.md) says which license covers which folder.
