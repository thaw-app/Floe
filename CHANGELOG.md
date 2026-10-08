# Changelog

All notable changes to Floe are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [0.1.0]

**macOS 26 and later · Build 1**

Floe is a launcher for macOS. It runs Raycast extensions unmodified and opens things in the apps you already use. This is the first release, and it is early: the [README](https://github.com/thaw-app/Floe#not-built-yet) lists what is not built yet. Report issues at [github.com/thaw-app/Floe/issues](https://github.com/thaw-app/Floe/issues).

### New: search

- **One hotkey opens the search.** It finds applications, extension commands, script commands, quicklinks and System Settings panes, and ranks them by how often and how recently you use each. Web apps a browser installed are found too. Two apps with the same name each get their own row.
- **Scattered letters match.** The letters that matched show in a stronger weight.
- **Aliases, hotkeys and favorites.** Give an application or a command an alias or a hotkey. Favorites stay at the top.
- **Scopes narrow a search to one place:** `files invoice`, `clipboard meeting`, `menu wifi`, `tabs invoice`.
- **A web address or a path typed in full leads the results.** `github.com/thaw-app` opens in the browser. `~/Downloads` is the folder itself, with the file actions.

### New: results and actions

- **An Actions menu (⌘K)** on applications and files: hide, quit, restart, force quit, show in Finder, open with, copy, move to Trash.
- **Hide from Search** takes an application or a command out of the search. Settings > General lists what is hidden and brings it back.
- **The Up arrow brings back earlier searches:** the last 50 that opened something. Settings > Privacy turns this off and forgets them.
- **Optional search sources.** Files and open browser tabs (Safari, Dia, Helium) add up to three rows to a search. Both are off until you turn them on in Privacy.
- **`Floe --pick` lends the search panel to a script.** It reads lines on standard input and prints the one you choose.

### New: shell commands

- **Type `>` and a command to run it.** Return runs it in the background and shows the first line of output. Your shell aliases work. Settings > General changes the prefix to `$` or `!`, or turns this off.
- **Other ways to run it.** ⌘Return opens it in your terminal, ⌥Return shows everything it printed, and ⇧Return runs it in the Finder folder in front.
- **Suggestions while you type:** earlier commands from your shell history, programs, paths, application names after `open -a` and hosts after `ssh`. Tab finishes the selected one.
- **A command works without the prefix** when it starts with a program on your Mac and has a flag, a path or a pipe in it. It is offered under the other results.
- **Save a command under a name** and the search finds it afterwards. `man` and a program's name opens its manual.

### New: processes and ports

- **`kill` and a name lists the running processes that match**, with the memory each one holds. Return asks one to quit. Force Quit asks first.
- **`port` and a number lists what is listening there.**

### New: extensions

- **Raycast extensions run unmodified** inside the app, including the ones Raycast already installed.
- **An Extension Store page** browses, installs and updates extensions.
- **Forms, preferences, arguments, toasts, confirmation dialogs, and background and interval commands work.** Passwords go in the Keychain.
- **You add menu bar commands by hand**, from the search or from Settings. None starts on its own at launch.
- **When a command throws, crashes or hangs**, Floe shows the log and lets you run it again.

### New: extension settings

- **Turn off an extension, or one of its commands**, on its page in Settings. Floe leaves what is off out of the search, and a hotkey, the menu bar or Shortcuts will not run it.
- **Each extension's page has one line per command**, with its alias, hotkey and switch. You can give the extension an icon of your own, or remove an extension Floe installed.

### New: built in

- **Clipboard history, snippets with text expansion, and quicklinks** with fallback searches.
- **A calculator with unit conversion.** It converts money with the European Central Bank's daily rates once you turn that on in Settings > Privacy, and shows the day the rates are from.
- **Emoji and symbols.** Hands and people use the skin tone you choose in Settings > General.
- **File search, calendar events and menu bar item search.** Menu bar search lists the menu bar's items and opens their menus from the keyboard.
- **System commands:** sleep, lock, empty Trash, volume up and down, eject all disks, and toggles for Wi-Fi, Bluetooth, mute and keeping the Mac awake. System Settings panes open from the search too.

### New: your own apps

- **Preferred apps:** a terminal, an editor, a browser and a notes app. Files, folders and the Finder selection open in them, and web links open in the browser you choose. Open With sends one link to another browser.
- **`note` and some text** goes to Apple Notes, Antinote, or any app with a URL scheme.
- **A preferred clipboard app.** Choose a clipboard manager and Clipboard History opens it. Floe then saves no copies of its own.
- **SSH hosts.** The hosts in `~/.ssh/config` are in the search, and `ssh` and a space lists them. Return connects in your terminal. Floe reads the names and keeps nothing.
- **Apple Shortcuts**, once turned on in Settings > Privacy. Return runs one in the background. If it fails, Floe shows the reason Shortcuts gave.

### New: AI

- **Ask AI.** Type `ask` and a question, or pick the Ask AI row under any search. The answer shows in the launcher, with who answered and whether it stayed on your Mac.
- **Follow-up questions** keep the earlier ones as context. The conversation ends when the view closes, and no history is kept.
- **Three kinds of source:** a command line tool you are already signed in to (`claude`, `codex`, `opencode` or `pi`), Apple Intelligence, or an OpenAI-compatible API (OpenAI, OpenRouter, Z.ai, Ollama, LM Studio).
- **A switch keeps all AI on your Mac.** One extension can have a source of its own. No source falls back to another.

### New: with Thaw

- **Thaw 3's actions are in the search** when Thaw is installed: the hidden sections, swap, Zen Mode, the Thaw Bar, the layout and the application menus.
- **The launcher can follow Thaw's menu bar appearance:** its tint, glass, border and shadow.

### New: appearance and settings

- **Thaw 3's glass styles, a tint, a border and a shadow** for the launcher.
- **A compact layout** shows only the search bar until you type.
- **The search field can float** as its own piece of glass, with the results in a second piece below it.
- **A Privacy page** lists the permissions and their reasons, the search sources, and everything Floe contacts over the network.
- **What's New and detailed logging.** What's New, in About, shows these notes in the app. Detailed logging is off by default and writes to `~/Library/Logs/Floe`. It never logs what you type or ask.

### What's next

- Sign-in (OAuth) for extensions. They use a token preference until then.
- `launchCommand`, deeplinks, AI tools and the grid layout for extensions.
- Searching your notes and searching an app's menus.

### Contributors

- Owen Cope (@OwenCope): the built-in search features, the extension APIs behind them and the Extension Store ([#6](https://github.com/thaw-app/Floe/pull/6)).
- @lylythechosenone: the calculator built on fend ([#7](https://github.com/thaw-app/Floe/pull/7)).
- @unsecretised: the first bug report ([#3](https://github.com/thaw-app/Floe/issues/3)).

### Acknowledgements

- [fend](https://github.com/printfn/fend) by printfn is the calculator's engine.
- Code from [Droppy Code](https://getdroppycode.app) by Jordy Spruit is used with his permission.
- Extensions are written for the [Raycast extensions](https://github.com/raycast/extensions) API. Raycast is a trademark of Raycast Technologies Inc.; Floe is not affiliated with Raycast.
- Exchange rates are the European Central Bank's euro foreign exchange reference rates.
- [Credits](https://github.com/thaw-app/Floe/blob/main/CREDITS.md) lists every package Floe ships with.
