# External interfaces

What a released Floe accepts from other software and what it reaches out to. The reasoning about which of these can be trusted is in the [assurance case](ASSURANCE_CASE.md).

## What other software can send Floe

### Links

| Link | What it does |
| --- | --- |
| `floe://oauth` | Returns from a sign-in in the browser. It must carry the state of a waiting sign-in |
| `floe://thaw-appearance` | Thaw's answer about its menu bar look. It must answer a request Floe made |
| `raycast://oauth`, `com.raycast:/oauth` | The same return, for an OAuth app that names Raycast's addresses. Floe holds these two schemes only while such a sign-in waits |
| Any other `raycast://` or `com.raycast:` link | Passed on to Raycast, if it is installed |

Floe ignores any other link. `IncomingLink.swift` decides, and `fuzz.yml` fuzzes it.

### App Intents

Shortcuts and other apps that run intents can use these:

| Intent | What it does |
| --- | --- |
| Open Floe | Shows the launcher |
| Search Menu Bar Items | Opens the menu bar item search |
| Run Command | Runs an extension command you pick |

### Command line

`Floe --pick` lends the search panel to a script: it reads items on standard input and prints the one you choose. [Picker](DEVELOPMENT.md#picker) has its options and exit codes. The other modes in [Checks](DEVELOPMENT.md#checks) are for development, and `--settings` starts the settings process.

### Notifications

The launcher and the settings process exchange distributed notifications named `org.thaw.floe.link.*`. Each is signed with a key handed over a pipe, so a copied or forged one is dropped. Floe also listens for `com.stonerl.Thaw.appearanceDidChange`, which carries nothing and only makes Floe ask Thaw again.

### Files

Settings can export to and import from a `Floe Settings.json` file you choose.

## Extensions

Each running command is a Bun process that speaks NDJSON with Floe over standard input and output. It runs under your account with no sandbox, so it can use your files and the network directly. `runtime/api/index.ts` stands in for `@raycast/api`.

Through that channel a command can also ask Floe for:

| Request | What it returns or does |
| --- | --- |
| `ai.ask` | An answer from the AI service you set up |
| `oauth.authorize`, `oauth.getTokens`, `oauth.setTokens`, `oauth.removeTokens` | Browser sign-in, and tokens kept in the Keychain for that installation |
| `selectedText`, `selectedFinderItems`, `clipboard.read` | What you have selected or copied |
| `environment.frontmostApplication`, `environment.getDefaultApplication`, `environment.getApplications` | The frontmost app, a file's default app, and the apps that can open a file |
| `browser.tabs`, `browser.script` | Your open tabs, and running a script in one |

Settings shows a record of what each extension reached.

## Script commands

A script command is an executable file in the Scripts folder with Raycast's `@raycast.*` comments. It runs under your account with no sandbox, from its own folder, with your login shell's environment.

### Actions on results

A `@floe.subjects` comment makes a script an action on results. Raycast reads no `@floe.*` line and runs the file as a plain command, where no `FLOE_*` variable is set, so a script like the one below fails there.

```sh
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Copy to Desktop
# @raycast.mode compact
# @floe.subjects file, folder

cp -R "$FLOE_PATH" ~/Desktop/ && echo "Copied $FLOE_FILENAME"
```

The comment names the kinds of result the script acts on: `app`, `file`, `folder`, `url` (or `link`) and `text`, which is a clipboard entry that holds text, or a snippet, separated by commas or spaces; a line that names none is an error. Such a script is not found by searching for its title. It is listed at the end of the Actions menu (⌘K) of each result of those kinds, and in Settings › Commands › Actions, where it can be made what Return does, given keys or left out of the menu. A script that needs confirming asks before it runs, and its output follows `@raycast.mode` as when it is searched for. It cannot have a required argument, since nothing is typed in the Actions menu; an argument with `"optional": true` is fine and is passed nothing. It runs only on a result, so it has no hotkey of its own: one it had before it got the line is taken off it, and a link that names it says where it runs instead.

The result is handed to the script in environment variables, never written into its command, so a name with quotes or `$` in it is just a name. A value Floe doesn't know is left unset, and a `FLOE_*` variable your login shell exports is not passed on. A symbolic link is read through: the path and everything else describe what it points at, and only `FLOE_NAME` is the link's. What is read from the disk waits at most 10 seconds, for a volume that stopped answering; then the script runs with only the result's name and path.

| Variable | On | What it holds |
| --- | --- | --- |
| `FLOE_SUBJECT` | all | `app`, `file`, `folder`, `url` or `text` |
| `FLOE_NAME` | all | The result's name as Floe shows it: the app's or file's name, the link's title or address, or the text's first line |
| `FLOE_URL` | app, file, folder, url | The web address, or the `file://` URL of an app, file or folder |
| `FLOE_QUERY` | all | What was typed in the search on screen, Search Files' own there, which can be empty |
| `FLOE_PATH` | app, file, folder | The full path, with no slash at the end |
| `FLOE_FILENAME` | app, file, folder | The last part of the path, such as `Report.pdf` |
| `FLOE_BASENAME` | app, file, folder | The file name without its extension, such as `Report` |
| `FLOE_EXTENSION` | app, file, folder | The extension without its dot, such as `pdf` |
| `FLOE_PARENT` | app, file, folder | The folder it is in. The startup disk, `/`, has none, nor `FLOE_FILENAME`, `FLOE_BASENAME` or `FLOE_EXTENSION` |
| `FLOE_CONTENT_TYPE` | app, file, folder | Its uniform type identifier, such as `com.adobe.pdf` |
| `FLOE_TYPE_DESCRIPTION` | app, file, folder | Its kind as Finder names it, such as `PDF document` |
| `FLOE_MIME_TYPE` | app, file, folder | Its MIME type, such as `application/pdf`, where the type has one |
| `FLOE_SIZE` | file | Its size in bytes |
| `FLOE_CREATED`, `FLOE_MODIFIED` | app, file, folder | When it was made and last changed, in ISO 8601, such as `2026-11-05T17:30:00Z` |
| `FLOE_BUNDLE_ID` | app | Its bundle identifier, such as `com.apple.Safari` |
| `FLOE_APP_VERSION`, `FLOE_APP_BUILD` | app | Its version and build number |
| `FLOE_APP_RUNNING` | app | `1` while it runs, else `0` |
| `FLOE_APP_PID`, `FLOE_APP_HIDDEN` | app | Its process identifier, and `1` if it is hidden, while it runs |
| `FLOE_HOST`, `FLOE_SCHEME` | url | The address's host, such as `www.youtube.com`, and its scheme, such as `https` |
| `FLOE_TEXT` | text | The text, up to 100,000 bytes of UTF-8 cut between characters: a clipboard entry's, or a snippet's as written, before its placeholders are filled |

An app found by Search Files, or by its path, is an app. The choices made for a script in Settings are kept under its file name, so renaming the file loses them. Keys it had are free again, not kept from another row.

## What Floe reaches out to

### Network

| Address | Why |
| --- | --- |
| `thaw-app.github.io/Floe/appcast.xml`, GitHub Releases | Updates, checked with Sparkle's EdDSA key |
| `raw.githubusercontent.com/thaw-app/Floe` | The changelog in Settings |
| `api.github.com/repos/raycast/extensions`, `raw.githubusercontent.com/raycast/extensions`, `github.com` | The extension store and installs |
| Bun's package registry | An installed extension's dependencies, with install scripts off |
| `www.ecb.europa.eu` | Exchange rates |
| `api.openai.com`, `openrouter.ai`, `api.z.ai`, or an address you type | AI services you choose |
| `localhost:11434`, `localhost:1234` | Ollama and LM Studio on this Mac |
| `raycast.com` | The page a browser sign-in returns through |
| iCloud | Settings sync, in a release signed with the provisioning profile, when you switch it on |
| An image's address | Remote icons named by an extension |

Quicklinks open in your browser. Floe's own code opens no listening socket, and App Transport Security allows plain HTTP only to local addresses.

### macOS permissions

Floe asks for each of these when a feature needs it: Accessibility, Screen Recording, Automation (Apple Events), Contacts, Calendars, Reminders, folders and notifications. Passwords and tokens go in the Keychain.

### Apple Events

Floe scripts Finder, System Events, Notes, Music, terminal apps and browsers. Its usage text in `project.yml` says what for.

### Command line tools

Floe runs `bun`, `git`, `ssh`, `shortcuts` and `screencapture`. If you use them, it also runs `gh` and `glab` to lend a sign-in, and `claude`, `codex` and `opencode` to generate text.

### Other apps

Floe opens `thaw://` links to ask Thaw for its look, only while Thaw is running and you have the option on.
