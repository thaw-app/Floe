# Changelog

All notable changes to Floe are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [Unreleased]

**macOS 26 and later · First release**

Please report issues at [github.com/thaw-app/Floe/issues](https://github.com/thaw-app/Floe/issues).

Floe is a launcher for macOS that runs Raycast extensions unmodified and hands work to the apps you already use. This is the first release. It is early: the list of what is not built yet is in the [README](https://github.com/thaw-app/Floe#not-built-yet).

### What's next

- Sign-in (OAuth) for extensions. They use a token preference until then.
- `launchCommand`, deeplinks, AI tools and the grid layout for extensions.
- Currency conversion, searching your notes and searching an app's menus.

---

### Features

#### Search

- One hotkey opens a search over applications, extension commands, script commands, quicklinks and System Settings panes, ranked by how often and how recently each is used.
- Scattered letters match, graded by word starts and runs, and the matched letters are drawn in a stronger weight.
- Aliases and hotkeys for applications, commands and the menu bar search. Favorites stay at the top.
- Hide from Search, in a result's actions, takes an application or a command out of the search. Settings, General lists what is hidden and brings it back.
- A running application can be hidden, quit, restarted or forced to quit from its actions.
- The Up arrow in an empty search brings back the search before, and the ones before that: the last 50 that ended in something being opened, calculations among them. Settings, Privacy switches this off and forgets them.
- Scopes narrow a search to one place: `files invoice`, `clipboard meeting`, `menu wifi`, `tabs invoice`.
- Optional search sources, off until turned on in Privacy: files and open browser tabs (Safari, Dia, Helium) add up to three rows to an ordinary search.
- An Actions menu (⌘K) on applications and files: quit, force quit, show in Finder, open with, copy, move to Trash.
- A web address or a path typed in full leads the results: `github.com/thaw-app` opens in the browser, and `~/Downloads` or `/Applications` is the folder or file itself, with the file actions.
- `Floe --pick` lends the search panel to any script: it reads lines on standard input and prints the one chosen.

#### Extensions

- Raycast extensions run unmodified on a Bun runtime inside the app, including the ones Raycast has already installed.
- Forms, preferences, arguments, toasts, confirmation dialogs, and background and interval commands work. Passwords go in the Keychain.
- An Extension Store page browses, installs and updates extensions.
- An extension can be switched off as a whole, and each of its commands by itself, on its page in Settings. What is off is left out of the search and is not run by a hotkey, the menu bar or Shortcuts. The page has one line for each command, with its alias, hotkey and switch, says how many commands are on, takes a picture of your own as the extension's icon, and removes an extension Floe installed.
- Menu bar commands are added to the menu bar by hand, from the search or from Settings. None starts on its own at launch.
- When a command throws, crashes or hangs, Floe shows the log and lets you run it again.

#### Built in

- Clipboard history, snippets with text expansion, quicklinks with fallback searches, emoji and symbols, file search, calendar events, and a calculator with unit conversion.
- Hands and people among the emoji are shown and pasted in the skin tone chosen in Settings, General.
- Menu bar item search lists the menu bar's items and opens their menus from the keyboard.
- System commands (sleep, lock, empty Trash, volume up and down, eject all disks) and toggles for Wi-Fi, Bluetooth, mute and keeping the Mac awake.
- System Settings panes open from the search, with the icons System Settings shows.

#### Your own apps

- Preferred apps: a terminal, an editor, a browser and a notes app. Files, folders and the Finder selection open in the ones already in use, web links open in the browser you choose (Open With in the Actions menu sends one link to another), and `note` followed by text goes to Apple Notes, Antinote, or any app with a URL scheme.
- A preferred clipboard app: with a clipboard manager chosen, Clipboard History opens it (Raycast by name, any other app, or a link), and Floe saves no copies of its own.
- SSH hosts: the hosts named in `~/.ssh/config` and the files it includes are found in the search, and `ssh` followed by a space lists them. Return opens the connection in the preferred terminal. Floe reads the names and keeps nothing.
- Apple Shortcuts: once switched on in Settings, Privacy, the shortcuts you made in the Shortcuts app are found in the search by name, and `shortcuts` followed by a space lists them. Return runs one in the background; if it fails, Floe shows the reason Shortcuts gave. Making and editing them stays in Shortcuts.

#### AI

- Ask AI: `ask` and a question, or the Ask AI row under any search, shows the answer in the launcher, with a line that says who answered and whether it stayed on the Mac. A follow-up typed above the answer is asked with the earlier questions and answers as context. The conversation lasts until the view closes: no history is kept.
- AI sources: a command line tool you are already signed in to (`claude`, `codex`, `opencode` or `pi`), so accounts and keys set up there are not entered again; Apple Intelligence on the Mac; or an OpenAI-compatible API (OpenAI, OpenRouter, Z.ai, Ollama, LM Studio).
- A switch keeps all AI on the Mac, and one extension can be pinned to a source of its own. No source ever falls back to another.

#### With Thaw

- Thaw 3's actions are in the search when Thaw is installed: the hidden sections, swap, Zen Mode, the Thaw Bar, the layout and the application menus.
- The launcher can follow Thaw's menu bar appearance: its tint, glass, border and shadow.

#### Appearance and settings

- Thaw 3's glass styles, a tint, a border and a shadow for the launcher, and a compact layout that is only the search bar until you type.
- The search field can float as its own piece of glass, with the results in a second piece below it.
- A Privacy page with the permissions and their reasons, the search sources, and everything Floe contacts over the network.
- What’s New, in the About page’s menu, shows these release notes in the app.
- Detailed logging, off by default, writes a log to `~/Library/Logs/Floe` for troubleshooting. What is typed or asked is never logged.

### Contributors

- Floe is built by René Jiménez (@diazdesandi).
- Owen Cope (@OwenCope) wrote the built-in search features, the extension APIs behind them and the Extension Store ([#6](https://github.com/thaw-app/Floe/pull/6)).
- Floe shares ThawUI and much of its design with Thaw, which René builds with Toni Förster (@stonerl), Amir Zarrinkafsh (@nightah) and the Thaw contributors.
- Jordy Spruit, for letting Floe use code from Droppy Code.
- @unsecretised, for the first bug report ([#3](https://github.com/thaw-app/Floe/issues/3)).
- Everyone who starred the repository and offered to help before there was anything to download.

Thank you. This release would not exist without you.
