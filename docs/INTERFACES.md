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
| An image's address | Remote icons an extension names |

Quicklinks open in your browser. Floe's own code opens no listening socket, and App Transport Security allows plain HTTP only to local addresses.

### macOS permissions

Floe asks for each of these when a feature needs it: Accessibility, Screen Recording, Automation (Apple Events), Contacts, Calendars, Reminders, folders and notifications. Passwords and tokens go in the Keychain.

### Apple Events

Floe scripts Finder, System Events, Notes, Music, terminal apps and browsers. Its usage text in `project.yml` says what for.

### Command line tools

Floe runs `bun`, `git`, `ssh`, `shortcuts` and `screencapture`. If you use them, it also runs `gh` and `glab` to lend a sign-in, and `claude`, `codex` and `opencode` to generate text.

### Other apps

Floe opens `thaw://` links to ask Thaw for its look, only while Thaw is running and you have the option on.
