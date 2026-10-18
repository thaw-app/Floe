# What Floe does not do yet

The gaps as they stand. The [roadmap](../README.md#roadmap) says which come next, and the [changelog](../CHANGELOG.md) lists each release's known issues.

## Extensions

- **Sign-in uses Raycast's service for now.** It is temporary and may stop working. Floe's own service is planned. GitHub and GitLab extensions use `gh` and `glab`.
- `launchCommand`, deeplinks, AI tools and the grid layout.
- Swift or Rust helpers inside an extension.

## Search and AI

- Searching your notes.
- AI chat.

## Sync

- **Nothing syncs until a release is signed for iCloud.** [Development](DEVELOPMENT.md#settings-sync) has the steps.
- **Sync is off until you switch it on** in Settings > General.
- Script commands do not sync.
- What does sync, in the main: aliases, hotkeys, favorites, hidden results, appearance, snippets and quicklinks. Extension settings sync while "Include extension settings" is on. [Development](DEVELOPMENT.md#settings-sync) has the full list, and what stays on each Mac.
- Passwords go through iCloud Keychain, by a separate switch that is off until you choose it.
