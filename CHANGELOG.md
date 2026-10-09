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

- **One hotkey opens the search.** It finds applications, extension commands, script commands, quicklinks and System Settings panes, and ranks them by how often and how recently you use each. Web apps a browser installed are found too. Two apps with the same name each get their own row. Scattered letters match, and the ones that matched show in a stronger weight.
- **Aliases, hotkeys and favorites.** Give an application or a command an alias or a hotkey. Favorites stay at the top.
- **Scopes narrow a search to one place:** `files invoice`, `clipboard meeting`, `menu wifi`, `tabs invoice`.
- **A web address or a path typed in full leads the results.** `github.com/thaw-app` opens in the browser. `~/Downloads` is the folder itself, with the file actions.
- **`keywords` or `?` lists every word the search answers to**, each with an example and what it does: `remind call mom tomorrow at 5pm`, `timer 10 minutes tea`. Type more to narrow the list. Return puts the keyword in the search for you to finish. What is switched off is left out.

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

### New: checkpoints

- **`pause` and a name saves what you were doing:** the files and folders selected in Finder, the tabs of the browser window in front, and a note after a colon. `pause website redesign: fix the nav next`.
- **Search for the name to resume it.** Text and code files open in the editor you chose in Settings, other files in their own apps, folders in Finder and the tabs in your browser. Floe shows your note.
- **Floe says what is missing** when a file has moved or gone, and lists it. What is still there opens.
- **Pausing again under the same name** replaces the checkpoint with what is open now.

### New: receipts

- **Floe keeps a receipt of what it changed:** commands it ran, files it moved to the Trash, processes it quit and extensions it removed. Type `receipts` to see them.
- **Return puts a file back** from the Trash to where it was. If something newer is there now, Floe leaves both alone and says so.
- **A command or a quit process cannot be undone**, and the receipt says that. Settings > Privacy turns receipts off and forgets them.
- **Notes and checkpoints leave receipts too.** A note written to your folder goes to the Trash from its receipt if you have not changed it, and a checkpoint's receipt deletes it. A line added to the day's note cannot be undone.

### New: reminders and events

- **`remind` and a sentence adds a reminder to Apple Reminders.** `remind call mom tomorrow at 5pm` is due tomorrow at five, and the row shows the date before you press Return. Without a date in it, the reminder has none.
- **Its receipt deletes it again.** macOS asks once whether Floe may use Reminders.
- **End the sentence with a list's name to put it there.** `remind call mom tomorrow at 5pm in Work`, or `list Work`. The row shows the list.
- **`event` and a sentence adds an event to Apple Calendar.** `event lunch with Ana Thursday noon` lasts an hour from Thursday at twelve, and a day with no time makes an all-day event. Its receipt deletes it again.

### New: timers, people and controls

- **`timer 10 minutes` starts a countdown.** `timer 25m`, `timer 1h 30m` and `timer 5 min tea` work too, and a notification with a sound says when it ends. `timers` lists the ones running, and Return stops one. Timers end when Floe quits.
- **`contact ana` finds people in your Contacts** by name, with a phone number or an email address beside each. Return opens the card, and the Actions menu calls, starts FaceTime, writes a message or an email, or copies the number or the address. macOS asks once whether Floe may read Contacts.
- **`mail` and `message` open a draft.** `mail toni@example.com the build is ready` opens a new email to Toni in your mail app, and `message +15551234567 running late` a new message in Messages. Without an address or a number first, the draft has no recipient. Nothing is sent until you send it.
- **Play/Pause, Next Track, Previous Track and Now Playing** control Spotify or Music, whichever is open. Search for `pause`, `skip`, `previous` or `what's playing`. Now Playing shows the track and its artist. macOS asks once whether Floe may control the app.
- **Toggle Focus, `focus 1 hour` and `focus off`** run a Shortcut you name in Settings > General. macOS gives apps no switch for Focus, so the Shortcut sets it: Floe hands it the minutes, or the word `off` or `toggle`. Until you name one, the row says so and Return opens Shortcuts.

### New: processes and ports

- **`kill` and a name lists the running processes that match**, with the memory each one holds. Return asks one to quit. Force Quit asks first.
- **`port` and a number lists what is listening there.**

### New: extensions

- **Raycast extensions run unmodified** inside the app, including the ones Raycast already installed.
- **An Extension Store page** browses, installs and updates extensions.
- **Forms, preferences, arguments, toasts, confirmation dialogs, and background and interval commands work.** Passwords go in the Keychain.
- **You add menu bar commands by hand**, from the search or from Settings. None starts on its own at launch.
- **When a command throws, crashes or hangs**, Floe shows the log and lets you run it again.

### New: extension settings and sign-in

- **Turn off an extension, or one of its commands**, on its page in Settings. Floe leaves what is off out of the search, and a hotkey, the menu bar or Shortcuts will not run it.
- **Each extension's page has one line per command**, with its alias, hotkey and switch. You can give the extension an icon of your own, or remove an extension Floe installed.
- **Each extension's page shows what it has reached:** the hosts it contacted, the folders it read and changed, and the programs it started, as far as Floe's runtime sees them. It is a record, not a limit. Settings > Privacy switches the record off and forgets it.
- **GitHub and GitLab extensions sign in with the GitHub CLI and the GitLab CLI.** If `gh` or `glab` is signed in on your Mac, Floe asks once per extension whether it may use that sign-in. For GitHub it lists what the sign-in may do. The extension's page in Settings takes it back.

### New: built in

- **Clipboard history, snippets with text expansion, and quicklinks** with fallback searches.
- **A calculator with unit conversion.** It converts money with the European Central Bank's daily rates once you turn that on in Settings > Privacy, and shows the day the rates are from.
- **Emoji and symbols.** Hands and people use the skin tone you choose in Settings > General.
- **File search, calendar events and menu bar item search.** Menu bar search lists the menu bar's items and opens their menus from the keyboard. File search asks Spotlight. Switch on Fast file search in Settings > Privacy and Floe keeps the names of the files in your home folder in memory and answers from those: scattered letters match, at each key, and files you opened lately come first. macOS then asks whether Floe may read your Desktop, Documents and Downloads folders.
- **System commands:** sleep, lock, empty Trash, volume up and down, eject all disks, and toggles for Wi-Fi, Bluetooth, mute and keeping the Mac awake. System Settings panes open from the search too.

### New: your own apps

- **Preferred apps:** a terminal, an editor, a browser and a notes app. Files, folders and the Finder selection open in them, and web links open in the browser you choose. Open With sends one link to another browser.
- **A preferred clipboard app.** Choose a clipboard manager and Clipboard History opens it. Floe then saves no copies of its own.
- **SSH hosts.** The hosts in `~/.ssh/config` are in the search, and `ssh` and a space lists them. Return connects in your terminal. Floe reads the names and keeps nothing.
- **Apple Shortcuts**, once turned on in Settings > Privacy. Return runs one in the background. If it fails, Floe shows the reason Shortcuts gave.

### New: notes

- **`note` and some text** goes to Apple Notes, Antinote, any app with a URL scheme, or a folder of Markdown files, which is what Obsidian and Octarine read. With a folder, `append` adds a line to the day's note.
- **In an Obsidian vault, the day's note is the one Obsidian opens.** Floe follows the folder and the date format set under Daily notes, such as `YYYY/MM/DD` or `dddd, MMMM Do YYYY`, with English month and day names. A format it cannot read falls back to `YYYY-MM-DD`.
- **`todo` and `log` write to the day's note.** `todo renew passport` adds a checkbox, `- [ ] renew passport`, and `log shipped the build` adds the line with the time in front, `- 14:05 shipped the build`. `append` alone opens the day's note.

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

- Sign-in (OAuth) for extensions other than GitHub. They use a token preference until then.
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
