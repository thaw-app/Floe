# Changelog

All notable changes to Floe are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

Each release's sections go in this order:

1. `### New`
2. `### Changed`
3. `### Fixed`
4. `### Known issues`

Leave out a section that would be empty. If one runs long, split it by area
with `####` headings, such as `#### Search`. Do not put the area in the
section's name.

Anything else goes before the first section, or in its own section after
these four.

## [0.2.1] - 2026-10-29

**macOS 26 and later · Build 4**

### Changed
- **Each AI service keeps its own API key.** When you switch service, the key field is empty until you enter that service's key, and switching back brings the earlier one back. The key you already saved stays with the service you use now.
- **Updates come as a full download**, with no smaller update built from an earlier version.
- **A calculation over 1,024 characters, or a shift by anything but a plain number up to 65,536, says it took too long** instead of holding up the calculator.
- **Your file index is built once more** after this update.

### Fixed

#### Security
These come from [CodeRabbit](https://www.coderabbit.ai)'s security scan of 0.2.0 ([#53](https://github.com/thaw-app/Floe/pull/53)).
- **An extension can't take another's sign-in by using its name.** Only one extension of a name runs, and its sign-in tokens are given only to the folder that saved them.
- **Your API key goes only to the AI service it was saved for**, never to one you switch to or import.
- **An AI service can't send your question elsewhere with a redirect.**
- **Codex answers with its image reading, web search and other tools turned off**, and never asks to run a command.
- **Importing settings keeps what you allowed on this Mac**, such as the sign-ins you lend to extensions, whether iCloud sync is on and whether shell commands run.
- **Names completed or opened in Terminal stay text**, inside quotes too and with accented letters.
- **Text you type into a quicklink can't add fields to it**, such as more recipients for an email.
- **A file whose name has a line break is saved in a checkpoint as one file.**
- **Put Back and daily notes don't follow a folder that has been swapped for a link**, and Put Back never writes over a file.
- **Clipboard history leaves out what you copied while recording was off**, and restoring an entry reads only Floe's own files.
- **Undo does only what its receipt says**, so an edited receipt can't delete a reminder.
- **The file index doesn't follow links out of the folders it covers**, and saving it can't write over another file.
- **Long lines in notes, very tall or wide pictures, long searches and long calculations can't stall Floe.**
- **Log lines can't be faked** by text an AI service sends back.

## [0.2.0] - 2026-10-28

**macOS 26 and later · Build 3**

### New
- **Floe runs on Intel Macs, extensions included** ([#46](https://github.com/thaw-app/Floe/issues/46)).
- **Choose the screen the launcher opens on**, in Settings > Appearance > Layout. Until you pick one, and whenever the one you picked is not connected, it opens on the screen with the pointer ([#41](https://github.com/thaw-app/Floe/discussions/41)).

### Changed
- **Ask AI with Codex needs Codex 0.157.1 or later.** Older versions can start their MCP servers even when Floe turns them off.

### Fixed
- **Extensions that use `ws`'s server or streams load again.** A named import such as `WebSocketServer` failed in 0.1.1.
- **Shell path completion keeps going inside a folder whose name has a space or brackets**, such as `~/Photos\ \(2024\)/`.
- **Floe stays open when Settings closes as it starts.** It could quit without a word.

#### Security
- **An extension's encrypted database is refused however its schema is named.** A name with a space or an accent got past the check, and the data was written unencrypted.

### Contributors

- @BYIIHub asked for Intel support ([#46](https://github.com/thaw-app/Floe/issues/46)).
- @Dent13 asked to choose the screen the launcher opens on ([#41](https://github.com/thaw-app/Floe/discussions/41)).

## [0.1.1] - 2026-10-27

**macOS 26 and later · Build 2**

### Changed
- **An AI service on another machine needs an `https://` address.** Your API key is never sent over plain `http://`. A service on this Mac still takes `http://`.
- **Pictures in Ask AI answers show as links.** They open only when you click them, so an answer can't send your conversation to an address of its own.

### Fixed
- **Quit works from the menu bar menu and from the Dock.** Floe could stay open when a notes app didn't answer while Floe was saving a note ([#39](https://github.com/thaw-app/Floe/issues/39)).
- **The beam runs round the search field's border** instead of lighting one half and then the other.
- **The search field's glass stays clear while you type.**
- **A menu item that is turned off stays off** when its menu updates.

#### Security
These come from [CodeRabbit](https://www.coderabbit.ai)'s deep scan of 0.1.0 ([#45](https://github.com/thaw-app/Floe/pull/45)).
- **Names completed into shell commands are text.** An app, file or command whose name holds `$`, a backtick or `;` no longer runs anything when you complete it or open its manual.
- **Settings and the launcher sign the messages they send each other**, so another app on your Mac can't send one, such as Remove from iCloud.
- **An extension can't use a name that reaches outside its own folder or Floe's own secrets**, and its sign-in tokens stay on this Mac.
- **A server on this Mac never gets the key you saved for another AI service.**
- **Codex answers without its shell tools**, in an empty folder of its own.
- **An extension's certificate pinning is kept, and an encrypted database it asks for is refused** rather than written in the clear.
- **A daily note always lands inside its vault.**

### Contributors

- @matthrz reported that Quit stayed greyed out ([#39](https://github.com/thaw-app/Floe/issues/39)).

## [0.1.0] - 2026-10-22

**macOS 26 and later · Build 1**

Floe is a launcher for macOS. It runs Raycast extensions unmodified and opens things in the apps you already use. This is the first release, and it is early.

After you install:

1. Press ⌃⌥Space to open the search. Settings > General changes the hotkey.
2. Open the Extension Store from the search to install extensions.
3. Look at Settings > Privacy. Files, browser tabs, Shortcuts, Fast file search and currency rates are off until you turn them on.
4. If something looks wrong, [open an issue](https://github.com/thaw-app/Floe/issues).

### New

#### Search
- **One hotkey opens the search.** It finds applications, extension commands, script commands, quicklinks and System Settings panes, ranked by how often and how recently you use each.
- **Web apps, Finder and the apps in macOS's CoreServices folder are found too**, such as Archive Utility. Two apps with the same name each get their own row.
- **Scattered letters match**, and the letters that matched show in a stronger weight.
- **Aliases, hotkeys and favorites.** Give an application or a command an alias or a hotkey. Emoji, Clipboard History, File Search, Search Menu Bar Items, Search Menu Items, Floating Note and the system commands take an alias and a hotkey too, in Settings > Commands. Favorites stay at the top.
- **Scopes narrow a search to one place:** `files invoice`, `menu wifi`, `tabs invoice`.
- **A web address or a path typed in full leads the results.** `github.com/thaw-app` opens in the browser. `~/Downloads` is the folder itself, with the file actions. A `file://` address opens its file or folder too.
- **`keywords` or `?` lists every word the search answers to**, each with an example and what it does: `remind call mom tomorrow at 5pm`, `timer 10 minutes tea`. Type more to narrow the list. Return puts the keyword in the search for you to finish. What is switched off is left out.

#### Results and actions
- **An Actions menu (⌘K)** on applications and files: hide, quit, restart, force quit, show in Finder, open with, copy, move to Trash.
- **Hide from Search** takes an application or a command out of the search. Settings > Commands lists what is hidden and brings it back.
- **The Up arrow brings back earlier searches:** the last 50 that opened something. Settings > Privacy turns this off and forgets them.
- **Optional search sources.** Files and open browser tabs (Safari, Dia, Helium) add up to three rows to a search. Both are off until you turn them on in Privacy.
- **`Floe --pick` lends the search panel to a script.** It reads lines on standard input and prints the one you choose. A tab splits a line into a title and what is shown beside it.

#### Shell commands
- **Type `>` and a command to run it.** Return runs it in the background and shows the first line of output. Your shell aliases work. Settings > Commands changes the prefix to `$` or `!`, or turns this off.
- **Other ways to run it.** ⌘Return opens it in your terminal, ⌥Return shows everything it printed, and ⇧Return runs it in the Finder folder in front.
- **Suggestions while you type:** earlier commands from your shell history, programs, paths, application names after `open -a` and hosts after `ssh`. Tab finishes the selected one.
- **A command works without the prefix** when it starts with a program on your Mac and has a flag, a path or a pipe in it. It is offered under the other results.
- **Save a command under a name** and the search finds it afterwards. `man` and a program's name opens its manual.
- **Script commands.** Scripts written for Raycast, put in Floe's Scripts folder, are in the search and take up to three arguments.

#### Checkpoints
- **`pause` and a name saves what you were doing:** the files and folders selected in Finder, the tabs of the browser window in front, and a note after a colon. `pause website redesign: fix the nav next`.
- **Search for the name to resume it.** Text and code files open in the editor you chose in Settings, other files in their own apps, folders in Finder and the tabs in your browser. Floe shows your note.
- **Floe says what is missing** when a file has moved or gone, and lists it. What is still there opens.
- **Pausing again under the same name** replaces the checkpoint with what is open now.

#### Receipts
- **Floe keeps a receipt of what it changed:** commands it ran, files it moved to the Trash, processes it quit and extensions it removed. Type `receipts` to see them.
- **Return puts a file back** from the Trash to where it was. If something newer is there now, Floe leaves both alone and says so.
- **A command or a quit process cannot be undone**, and the receipt says that. Settings > Privacy turns receipts off and forgets them.
- **Notes and checkpoints leave receipts too.** A note written to your folder goes to the Trash from its receipt if you have not changed it, and a checkpoint's receipt deletes it. A line added to the day's note cannot be undone.

#### Reminders and events
- **`remind` and a sentence adds a reminder to Apple Reminders.** `remind call mom tomorrow at 5pm` is due tomorrow at five, and the row shows the date before you press Return. Without a date in it, the reminder has none.
- **Its receipt deletes it again.** macOS asks once whether Floe may use Reminders.
- **End the sentence with a list's name to put it there.** `remind call mom tomorrow at 5pm in Work`, or `list Work`. The row shows the list.
- **`event` and a sentence adds an event to Apple Calendar.** `event lunch with Ana Thursday noon` lasts an hour from Thursday at twelve, and a day with no time makes an all-day event. Its receipt deletes it again.

#### Timers, people and controls
- **`timer 10 minutes` starts a countdown.** `timer 25m`, `timer 1h 30m` and `timer 5 min tea` work too, and a notification with a sound says when it ends. `timers` lists the ones running, and Return stops one. Timers end when Floe quits.
- **`contact ana` finds people in your Contacts** by name, with a phone number or an email address beside each. Return opens the card, and the Actions menu calls, starts FaceTime, writes a message or an email, or copies the number or the address. macOS asks once whether Floe may read Contacts.
- **`mail` and `message` open a draft.** `mail toni@example.com the build is ready` opens a new email to Toni in your mail app, and `message +15551234567 running late` a new message in Messages. Without an address or a number first, the draft has no recipient. Nothing is sent until you send it.
- **Play/Pause, Next Track, Previous Track and Now Playing** control Spotify or Music, whichever is open. Search for `pause`, `skip`, `previous` or `what's playing`. Now Playing shows the track and its artist. macOS asks once whether Floe may control the app.
- **Toggle Focus, `focus 1 hour` and `focus off`** run a Shortcut you name in Settings > Commands. macOS gives apps no switch for Focus, so the Shortcut sets it: Floe hands it the minutes, or the word `off` or `toggle`. Until you name one, the row says so and Return opens Shortcuts.

#### Processes and ports
- **`kill` and a name lists the running processes that match**, with the memory each one holds. Return asks one to quit. Force Quit asks first.
- **`port` and a number lists what is listening there.**

#### Extensions
- **Raycast extensions run unmodified** inside the app, including the ones Raycast already installed.
- **An Extension Store page** browses, installs and updates extensions. By @OwenCope in [#6](https://github.com/thaw-app/Floe/pull/6), with its look reworked by @unsecretised in [#16](https://github.com/thaw-app/Floe/pull/16).
- **An extension's page in the store** shows its screenshots, its categories, how many commands it has and whether it needs setup before it runs. Each command is listed with how it runs and the arguments it takes. Click a screenshot to see it larger.
- **Lists, grids, details, forms, preferences and arguments work**, and so do toasts, confirmation dialogs, and background and interval commands. Grids draw as tiles, and the arrow keys move through them. Passwords go in the Keychain.
- **You add menu bar commands by hand**, from the search or from Settings. None starts on its own at launch. A fresh install offers to add ready menu bar commands that are not already enabled. Commands needing preferences show setup guidance instead.
- **When a command throws, crashes or hangs**, Floe shows the log and lets you run it again.
- **An extension that holds more than 1 GB of memory is stopped.** Floe says so, and how much it held.
- **A command can start another**, with `launchCommand` or with a `raycast://extensions/…` link the extension opens. A link passes its arguments along.
- **Extension actions include Open With, Quick Look, Create Snippet, Create Quicklink and Pick Date.**
- **Extensions read the browser tab in front** in Safari, Dia, Helium, Chrome, Brave, Edge and Vivaldi, with no browser extension to install.
- **An extension with a Swift helper takes a few minutes the first time**, while Floe builds the helper. Extensions with Rust helpers do not run on macOS, as in Raycast.
- **Extensions that read your clipboard history read Floe's.**
- **[Raycast API compatibility](docs/COMPAT.md) lists what works as in Raycast**, what works with a difference and what does not yet. In a test of 1,850 store extensions, 6,035 of their 6,052 commands built.
- **An extension you are writing runs again when you save it.** While one of its commands is open, a save under `src` or `assets`, or of `package.json`, runs the command again with the same arguments. A change that fails to build or load leaves the last working view up, with a toast that says why.

#### Extension settings and sign-in
- **Turn off an extension, or one of its commands**, on its page in Settings. Floe leaves what is off out of the search, and a hotkey, the menu bar or Shortcuts will not run it.
- **Each extension's page has one line per command**, with its alias, hotkey and switch. You can give the extension an icon of your own, or remove an extension, whether Floe or Raycast installed it.
- **Each extension's page shows what it has reached:** the hosts it contacted, the folders it read and changed, and the programs it started, as far as Floe's runtime sees them. It records what the extension did and stops none of it. Settings > Privacy switches the record off and forgets it.
- **GitHub and GitLab extensions sign in with the GitHub CLI and the GitLab CLI.** If `gh` or `glab` is signed in on your Mac, Floe asks once per extension whether it may use that sign-in. For GitHub it lists what the sign-in may do. The extension's page in Settings takes it back.
- **Other extensions sign in in the browser.** If the browser's answer cannot reach Floe, Floe asks for the extension's token instead and runs the command again. Known issues says whose sign-in service this uses for now.

#### Built in
- **Snippets with text expansion, and quicklinks** with fallback searches. By @OwenCope in [#6](https://github.com/thaw-app/Floe/pull/6).
- **Settings > Fallbacks chooses what is offered under every search, and in what order.** Running the text as a shell command, Search Files, Ask AI, any quicklink that searches, and any extension command that takes text can be added, moved and removed. A command gets what you typed in its first argument and as `fallbackText`. Return opens the first fallback when nothing else matches.
- **A calculator with unit conversion.** It converts money with the European Central Bank's daily rates once you turn that on in Settings > Privacy, and shows the day the rates are from. Powers are drawn as real superscripts, and `pi` is π. By @lylythechosenone in [#7](https://github.com/thaw-app/Floe/pull/7).
- **The calculator reads sums the way people type them.** `200 + 10%` is 220, `100 f to c` converts a temperature, `5 ft 10 in to cm` is 177.8 cm and `today + 3 days` is a date. `today` on its own shows the date.
- **`define tide` shows what the dictionary says about a word.** The answer comes from the dictionaries on your Mac, the ones switched on in the Dictionary app, so nothing is sent anywhere. Return opens the word in Dictionary, and the Actions menu copies the definition.
- **`windows` lists your open windows**, and text after it narrows them by title or app. Return switches to one, out of the Dock if it is minimized. The Actions menu minimizes or closes it. It shows titles, not thumbnails, and needs Accessibility.
- **Tab on an application lists the recently used files that open in it**, and so does `recent preview`. Spotlight says which files you used in the last 30 days, and macOS says which app opens each. It is not the app's own Open Recent list, which Floe may not read.
- **`bookmarks invoice` finds a bookmark** of Chrome, Brave, Edge, Arc, Vivaldi, Dia or Helium. Floe reads the browser's own file when you type the word, and nothing leaves your Mac. Safari is not covered.
- **`time in tokyo` shows the time there**, and how far it is from yours. `time 5pm in berlin` takes a time of day here to there.
- **`uuid`, `password 24` and `lorem 3` make something to paste.** A password is copied so that clipboard managers leave it out.
- **`translate hola mundo` translates a text.** It goes to your first language the text is not already in, or to the one you name: `translate to german good morning`. The word alone translates the clipboard. The translation is Apple's, made on this Mac, and the row says so and that it can be rough. A pair of languages macOS has not downloaded says so, and Return opens the settings that download it.
- **Pick Color from Screen** shows the system's eyedropper and copies the color under it as hex, such as `#A1B2C3`.
- **Copy Text from Screen** reads the text in the part of the screen you drag over and copies it. A QR code or a barcode there is read, and what it says is copied. The reading is done on this Mac, and macOS asks for Screen Recording the first time.
- **`qr https://example.com` makes a QR code.** Return copies the picture, and the actions show it in Quick Look or save it to Downloads.
- **`maps coffee in lisbon` finds a place.** The places come from Apple Maps, so the text after `maps` is sent to Apple; Floe asks for no location and sends nothing for any other search. Return shows the place in Maps, and the actions open the way there or copy the address. Settings > Privacy lists it under Network Access.
- **`output airpods` and `input macbook` choose where sound goes.** `output` or `input` alone lists every device, the one in use first, and Return makes the selected one the default. AirPods show the battery of each bud and of the case. The devices are read with Audio Priority Bar's sources, by Camille Guillory and originally by tobi.
- **`battery`, `disk`, `memory` and `ip` show a fact about this Mac.** The battery's charge, time left, cycles and health, with the battery of each connected mouse, keyboard or headphones that reports one, the room on the startup disk, the memory in use and the local address. They sit under the other results, so `disk` and Return still open Disk Utility. The battery, memory and address are read with Barometer's system sources, by mackid1993.
- **`brew ripgrep` finds a Homebrew package.** Return installs it in your terminal, or upgrades one you have, and the actions uninstall it. `brew` alone lists what is installed. The names come from the lists Homebrew keeps on disk, so `brew` is not started until you choose.
- **`base64 hello` changes a text**, and so do `unbase64`, `urlencode`, `urldecode`, `uppercase`, `lowercase`, `titlecase` and `sha256`. With nothing after the word, it works on the clipboard.
- **Command-Y shows a file in Quick Look** from the search, and a file's Actions menu has Quick Look.
- **Emoji and symbols.** Hands and people use the skin tone you choose in Settings > Commands. By @OwenCope in [#6](https://github.com/thaw-app/Floe/pull/6).
- **File search, calendar events and menu bar item search.** File search asks Spotlight. Menu bar search lists the menu bar's items and opens their menus from the keyboard. By @OwenCope in [#6](https://github.com/thaw-app/Floe/pull/6).
- **Fast file search** keeps the names of the files in your home folder on this Mac and answers as you type, with files you opened lately first. Switch it on in Settings > Privacy, and macOS asks whether Floe may read your Desktop, Documents and Downloads folders. Switching it off deletes the names it kept.
- **Search Menu Items lists the commands in the menus of the app in front**, submenus included, with the menus each one is in and its shortcut. Type part of a name to narrow them, and Return runs the command in that app. Commands that are greyed out are left out. `menus export` does the same from the search. It needs Accessibility. The menus are read with CMD-Z's menu scanner, by Toni Förster.
- **System commands:** sleep, lock, empty Trash, volume up and down, eject all disks, and toggles for Wi-Fi, Bluetooth, mute and keeping the Mac awake. System Settings panes open from the search too. By @OwenCope in [#6](https://github.com/thaw-app/Floe/pull/6). Quit Floe is one of them. By @unsecretised in [#19](https://github.com/thaw-app/Floe/pull/19).

#### Your own apps
- **Preferred apps:** a terminal, an editor, a browser and a notes app. Files, folders and the Finder selection open in them, and web links open in the browser you choose. The editor can be one that runs in your terminal: Helix, Neovim, Vim, Emacs and others on your Mac are offered by name. Open With sends one link to another browser.
- **Clipboard history.** Floe keeps the text, links, images and files you copy, up to 300 of them, and text keeps its formatting. Return pastes one, and pinned copies survive Clear. A copy a password manager marks private is left out. Choose Off for Clipboard in Settings > Applications to stop saving copies.
- **Browse Notes lists your notes in the panel**, beside the one you pick: Floe's folder in Apple Notes, or a folder of Markdown notes such as an Obsidian or Octarine vault. It takes a hotkey in Settings > Commands.
- **A note reads as a document**, with the Markdown marks hidden and tasks you tick with a click. A formatting bar shows while you write. Command-B, Command-I, Command-E and Command-K format the selection, and Option-Command-1 to 6 turn a line into a heading or a list.
- **Return starts writing and Escape ends it.** Command-N makes a note named by what you typed, and Command-O opens the note in its app.
- **Floe keeps no copy of your notes.** It reads and writes them where they are and picks up what another app writes. A note changed elsewhere while you wrote is not overwritten: yours is saved beside it.
- **Floating Note keeps one note above other apps**, on every Space and beside full-screen apps, and stays when the launcher closes. It takes an alias and a hotkey in Settings > Commands.
- **It writes where your notes are:** the files of a notes folder, or a folder named Floe in Apple Notes, as plain text. Command-[ and Command-] step through your notes, and Command-N makes one.
- **It saves after a pause in typing**, and when you switch notes or close it. If a save fails, your text stays in the window and Floe says why. With Antinote or another app, it holds one scratch note until Send hands it over.
- **A preferred clipboard app.** Choose a clipboard manager and Clipboard History opens it. Floe then saves no copies.
- **SSH hosts.** The hosts in `~/.ssh/config` are in the search, and `ssh` and a space lists them. Return connects in your terminal. Floe reads the names and keeps nothing.
- **Apple Shortcuts**, once turned on in Settings > Privacy. Return runs one in the background. If it fails, Floe shows the reason Shortcuts gave.

#### Notes
- **`note` and some text** goes to Apple Notes, Antinote, any app with a URL scheme, or a folder of Markdown files, which is what Obsidian and Octarine read. With a folder, `append` adds a line to the day's note.
- **In an Obsidian vault, the day's note is the one Obsidian opens.** Floe follows the folder and the date format set under Daily notes, such as `YYYY/MM/DD` or `dddd, MMMM Do YYYY`, with English month and day names. A format it cannot read falls back to `YYYY-MM-DD`.
- **`todo` and `log` write to the day's note.** `todo renew passport` adds a checkbox, `- [ ] renew passport`, and `log shipped the build` adds the line with the time in front, `- 14:05 shipped the build`. `append` alone opens the day's note.

#### AI
- **Ask AI.** Type `ask` and a question, or pick the Ask AI row under any search. The answer shows in the launcher, with who answered and whether it stayed on your Mac.
- **Follow-up questions** keep the earlier ones as context. The conversation ends when the view closes, and no history is kept.
- **Three kinds of source:** a command line tool you are already signed in to (`claude`, `codex`, `opencode` or `pi`), Apple Intelligence, or an OpenAI-compatible API (OpenAI, OpenRouter, Z.ai, Ollama, LM Studio).
- **A switch keeps all AI on your Mac.** One extension can have a source of its own. No source falls back to another.

#### With Thaw
- **Thaw 3's actions are in the search** when Thaw is installed: the hidden sections, swap, Zen Mode, the Thaw Bar, the layout and the application menus.
- **The launcher can follow Thaw's menu bar appearance:** its tint, glass, border and shadow.

#### Appearance and settings
- **Glass styles, a tint, a border and a shadow** for the launcher, with a preview that changes as you choose.
- **A compact layout** shows only the search bar until you type.
- **The search field is rounded, a capsule or square.** It can also float as its own piece of glass, with the results in a second piece below it.
- **A beam of light runs around the search field**, with a soft glow just inside it. Settings > Appearance picks Colorful, Mono, Ocean or Sunset, or turns it off, and sets its frame rate, from 15 to 120.
- **A Privacy page** lists the permissions and their reasons, the search sources, and everything Floe contacts over the network.
- **A welcome at first launch** gives a short tour, then shows each permission on a card: what it switches on and whether you have granted it.
- **A permission asks only when you press its button**, and all of them can wait: Accessibility, Screen Recording, your Desktop, Documents and Downloads folders, notifications, Calendar, Reminders and Contacts. If a later version needs one you have not answered, that step comes back.
- **The Settings sidebar groups the pages.** General, Appearance and Privacy come first. Search holds Commands, Applications, Quicklinks and Snippets, and Connections holds AI, Sync and the Extension Store. Each extension has a page of its own, and About comes last.
- **Search the settings** from the top of the Settings window's sidebar.
- **Export your settings to one file** and import them on another Mac.
- **Launch at login, and updates.** Floe asks once whether it may check for updates, and whether to install them by itself. Settings chooses between the Stable and the Beta channel.
- **What's New and detailed logging.** What's New, in About, shows these notes in the app. Detailed logging, in Settings > Privacy, is off by default and writes to `~/Library/Logs/Floe`. It never logs what you type or ask.

#### Shortcuts and Siri
- **Three actions in Apple's Shortcuts app:** Open Floe, Run Command and Search Menu Bar Items. Siri runs them too.

#### Sync
- **Settings sync with iCloud**, off until you switch it on in Settings > Sync. Aliases, hotkeys, favorites, hidden results, appearance, snippets, quicklinks and extension settings are the same on your Macs, and the newest change wins.
- **Passwords through iCloud Keychain**, a second switch that is off until you choose it. Extension passwords and API keys become iCloud Keychain items; off copies them back to this Mac and leaves them in iCloud Keychain.
- **Some things stay on each Mac:** folders, permissions, AI settings, an extension's files, folders and chosen apps, sign-ins and receipts. Remove Settings from iCloud deletes iCloud's copy and switches sync off on every Mac.

### Known issues
- **Extension sign-in uses Raycast's sign-in service for now.** The browser returns through raycast.com, and some extensions get their token from Raycast's servers. Floe says so before the first sign-in. It may stop working before Floe's own service replaces it. GitHub and GitLab extensions sign in with their command line tools instead.
- **AI tools and window management for extensions are not built yet.** A `raycast://extensions/…` link opened from a browser or another app goes to Raycast. [Limitations](docs/LIMITATIONS.md) lists the rest.
- **The record of what an extension reaches misses some file access.** It sees hosts and programs more reliably than files.
- **Timers end when Floe quits.** They are held in memory.
- **Fast file search leaves out iCloud Drive**, which macOS keeps inside Library.
- **Floe is in English only.** Its text can be translated on [Crowdin](https://crowdin.com/project/floe).

### Contributors

- @OwenCope wrote the Extension Store page, snippets, quicklinks, emoji, file search, calendar events, menu bar item search and the system commands ([#6](https://github.com/thaw-app/Floe/pull/6)).
- @lylythechosenone wrote the calculator ([#7](https://github.com/thaw-app/Floe/pull/7)) and its superscripts, tested Floe and suggested features.
- HiroMike on Discord tested Floe and sent feedback.
- dor4a on Discord tested Floe and asked whether commands could have a key of their own, such as ⌘E for emoji or ⇧⌘V for the clipboard. Emoji, Clipboard History, File Search and the system commands take a hotkey.
- @unsecretised reported the first bugs, in the Settings window ([#3](https://github.com/thaw-app/Floe/issues/3)), reworked the Extension Store page ([#16](https://github.com/thaw-app/Floe/pull/16)) and added Quit Floe to the search ([#19](https://github.com/thaw-app/Floe/pull/19)).

### Acknowledgements

- [fend](https://github.com/printfn/fend) by printfn is the calculator's engine. Exchange rates are the European Central Bank's euro foreign exchange reference rates.
- Code from [Droppy Code](https://getdroppycode.app) by Jordy Spruit is used with his permission.
- Extensions are written for the [Raycast extensions](https://github.com/raycast/extensions) API. Raycast is a trademark of Raycast Technologies Inc.; Floe is not affiliated with Raycast.
- [Credits](https://github.com/thaw-app/Floe/blob/main/CREDITS.md) lists every package Floe ships with.
