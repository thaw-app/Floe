# What Floe does not do yet

The gaps as they stand. The [roadmap](https://www.getthaw.app/floe/roadmap) says which come next, and the [changelog](../CHANGELOG.md) lists each release's known issues.

## Extensions

[Raycast API compatibility](COMPAT.md) goes through the API part by part.

- **Sign-in uses Raycast's service for now.** It is temporary and may stop working. Floe's own service is planned. GitHub and GitLab extensions use `gh` and `glab`.
- Deeplinks from outside Floe: a `raycast://extensions/…` link opened in a browser or another app goes to Raycast. The same link opened by an extension runs the command in Floe, when that command is installed and enabled.
- AI tools and window management.
- An extension's Swift helper is built the first time a command calls it, which takes a few minutes and needs Apple's Swift tools (Xcode, or `xcode-select --install`). Rust helpers do not run on macOS, as in Raycast.
- `react-dom/server`, which a few extensions use to draw text.
- Dependencies that only work once their install scripts have run: Floe installs extensions with scripts off.
- Encrypted SQLite databases (`better-sqlite3-multiple-ciphers` with a key).

## Search and AI

- Searching your notes.
- AI chat.

## Sync

- **Nothing syncs until a release is signed for iCloud.** [Development](DEVELOPMENT.md#settings-sync) has the steps.
- **Sync is off until you switch it on** in Settings > Sync.
- Script commands do not sync.
- What does sync, in the main: aliases, hotkeys, favorites, hidden results, appearance, snippets and quicklinks. Extension settings sync while "Include extension settings" is on. [Development](DEVELOPMENT.md#settings-sync) has the full list, and what stays on each Mac.
- Passwords go through iCloud Keychain, by a separate switch that is off until you choose it.
