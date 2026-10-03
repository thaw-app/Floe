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
  <a href="#features">Features</a> ·
  <a href="docs/DEVELOPMENT.md">Building</a> ·
  <a href="https://discord.gg/KDfWjWDnR4">Discord</a> ·
  <a href="#todo">TODO</a> ·
  <a href="#acknowledgments">Acknowledgments</a>
</p>

<p align="center">
  <img alt="Floe's launcher with suggestions and commands under the search field" src="docs/images/floe.jpg" width="800" />
</p>

## Features

- One hotkey opens apps and commands, ranked by how often and how recently you use them.
- Runs Raycast extensions unmodified, including the ones Raycast has already installed, on a Bun runtime that ships inside the app.
- Searches the menu bar's items and opens their menus from the keyboard. Recently opened items come first, items in view get a preview, and you can give any item your own name.
- Extension forms, preferences and arguments work. Passwords go in the Keychain.
- Apps, commands and the menu bar search can each have an alias and a hotkey. Favorites stay at the top.
- When a command throws, crashes or hangs, Floe shows the log and lets you run it again.
- Built on ThawUI, the design system from [Thaw](https://github.com/thaw-app/Thaw), for macOS 26 and later.

Floe is early. There are no releases yet, so build it from source, and the list below is what doesn't work.

## TODO

### Extensions

- [ ] OAuth sign-in (GitHub, Notion, Linear, Spotify, Todoist)
- [ ] Menu bar commands
- [ ] Background and interval commands
- [ ] Selected text and the Finder selection
- [ ] Pasting into the frontmost app
- [ ] Confirmation dialogs inside the panel
- [ ] `launchCommand` and deeplinks
- [ ] AI and AI tools
- [ ] Grid layout and full detail metadata
- [ ] App picker for preferences
- [ ] Toast actions
- [ ] Swift and Rust helpers in extensions built from source

### Built in

- [ ] Clipboard history
- [ ] Snippets with text expansion
- [ ] Quicklinks and fallback commands
- [ ] Calculator, with unit and currency conversion
- [ ] Emoji and symbols
- [ ] File search
- [ ] System commands (sleep, lock, empty Trash)
- [ ] Calendar
- [ ] Floating notes
- [ ] Search an app's menus
- [ ] Script commands
- [ ] AI chat

### App

- [ ] Browse, install and update extensions
- [ ] Hot reload for extension development
- [ ] Settings sync, import and export
- [ ] App icon
- [ ] Signed and notarized releases with updates
- [x] Automated tests

## Contributing

Read the shared [Thaw/Floe contribution policy](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md), [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md), and [Code of Conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md). Build commands and tests are in [Development](docs/DEVELOPMENT.md).

## Acknowledgments

- [Thaw](https://github.com/thaw-app/Thaw): the ThawUI design system, the hotkey code, and the designs for the search panel, the settings sidebar and the About page. GPL-3.0.
- [CompactSlider](https://github.com/buh/CompactSlider), used by ThawUI. MIT.
- [Bun](https://bun.sh), which runs extensions. MIT.
- [React](https://react.dev) and react-reconciler, which render them. MIT.
- [Raycast extensions](https://github.com/raycast/extensions), whose API Floe implements. Each extension keeps its own license. Raycast is a trademark of Raycast Technologies Inc.; Floe is not affiliated with Raycast.
