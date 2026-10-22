# Raycast API compatibility

What Floe's runtime does with each part of Raycast's API. [What Floe does not do yet](LIMITATIONS.md) lists the gaps, and the [README](../README.md#features) has the test against real extensions.

Supported works as in Raycast. Partial works, with the difference in Notes. Not yet does nothing, or fails with a message.

## Views

| API | Status | Notes |
| --- | --- | --- |
| `List` | Partial | A controlled `searchText` and `throttle` are ignored. The list's own filtering matches each typed word as text in the title, subtitle or keywords. Section subtitles are not shown. |
| `List.Item`, `List.Item.Detail`, `List.Section` | Supported | |
| `List.EmptyView` | Partial | Its icon is not shown. |
| `List.Dropdown`, `Grid.Dropdown` | Supported | |
| `Grid` | Partial | As `List`. |
| `Detail` | Supported | |
| `Form` | Partial | `enableDrafts`, `storeValue` on fields, `onFocus`, `onBlur` and a field ref's `focus()` do nothing. `Form.LinkAccessory` is not shown. |
| Form fields | Partial | `Form.DatePicker` ignores `min` and `max`. `Form.Dropdown` shows no section titles or item icons. `info` shows only on `Form.TextField`. |
| `MenuBarExtra` | Partial | An item's `shortcut` and `alternate` are not shown. |
| `ActionPanel`, sections and submenus | Supported | |
| `Action`, `Action.Style` | Supported | |
| `Action.OpenInBrowser`, `Open`, `OpenWith`, `CopyToClipboard`, `Paste`, `Push`, `ShowInFinder`, `SubmitForm`, `ToggleQuickLook`, `PickDate`, `CreateSnippet`, `CreateQuicklink` | Supported | |
| `Action.Trash` | Partial | As `trash`. |
| `Action.InstallMCPServer` | Not yet | Shows a toast that Floe can't install MCP servers. |
| `useNavigation` | Supported | |

## Feedback and the window

| API | Status | Notes |
| --- | --- | --- |
| `showToast`, `Toast` | Supported | |
| `showHUD` | Partial | `clearRootSearch` and `popToRootType` are ignored. |
| `confirmAlert` | Partial | `icon` is not shown. |
| `closeMainWindow` | Partial | `clearRootSearch` and `popToRootType` are ignored. |
| `popToRoot` | Partial | `clearSearchBar` is ignored. |
| `clearSearchBar` | Partial | `forceScrollToTop` is ignored. |

## System

| API | Status | Notes |
| --- | --- | --- |
| `open`, `showInFinder` | Supported | |
| `trash` | Partial | Floe moves items into `~/.Trash` itself, so Finder's Put Back does not work for them. |
| `getApplications`, `getDefaultApplication`, `getFrontmostApplication` | Supported | |
| `getSelectedText`, `getSelectedFinderItems` | Supported | |
| `Clipboard.copy`, `Clipboard.clear` | Supported | |
| `Clipboard.paste` | Partial | From a menu bar or background command it only copies, and a HUD says to press ⌘V. |
| `Clipboard.read`, `Clipboard.readText` | Partial | `offset` reads Floe's clipboard history, so it finds nothing while that history is off. |
| `captureException` | Partial | The error goes to the command's log. Nothing is reported. |

## Storage, preferences and arguments

| API | Status | Notes |
| --- | --- | --- |
| `LocalStorage` | Supported | |
| `Cache` | Supported | |
| `getPreferenceValues`, every preference type | Supported | |
| `openExtensionPreferences` | Supported | |
| `openCommandPreferences` | Partial | Opens the extension's page in Settings, as `openExtensionPreferences` does. |
| Arguments | Partial | Asked for in a form before the command runs, not in the search bar. |
| `launchType`, `launchContext`, `fallbackText` | Supported | |

## Environment and commands

| API | Status | Notes |
| --- | --- | --- |
| `environment` | Partial | `textSize` is always `medium` and `raycastVersion` always `1.100.0`. `appearance` is read once, when the command starts. |
| `launchCommand` | Supported | |
| `updateCommandMetadata` | Supported | |
| Deeplinks | Partial | A `raycast://extensions/…` link that an extension opens runs the command in Floe, with its `arguments`, when that command is installed and enabled (and its owner matches, when the extension names one). A menu bar command already in the menu bar is left as it is. `launchContext` and `fallbackText` in the link are ignored. Any other link, and the same link opened from a browser or another app, goes to the system. |

## AI, sign-in, browser and windows

| API | Status | Notes |
| --- | --- | --- |
| `AI.ask` | Partial | Needs an AI source in Settings. `creativity` is ignored, and `model` only guides which model the source uses. |
| AI tools (`tools` in the manifest) | Not yet | |
| `OAuth.PKCEClient` | Partial | Sign-in goes through Raycast's redirect service for now. GitHub and GitLab use `gh` and `glab`. `providerIcon` and `description` are not shown. |
| `BrowserExtension` | Partial | Read through AppleScript from Safari, Dia, Helium, Chrome, Brave, Edge and Vivaldi. Other browsers are not read. Tabs have no favicon. |
| `WindowManagement` | Not yet | Every call fails, and `environment.canAccess` says no. |

## Icons, images, colors and keyboard

| API | Status | Notes |
| --- | --- | --- |
| `Icon` | Partial | Drawn as SF Symbols. An icon with no close symbol shows a dashed square. |
| `Image` | Partial | `fallback` is ignored, and the only mask drawn is the circle. |
| `Color` | Partial | Raycast's named colors and hex values work. Dynamic colors (`{ light, dark }`) are ignored. |
| `Keyboard.Shortcut`, `Keyboard.Shortcut.Common` | Supported | |
| API 1.x names and `render()` | Supported | |

## `@raycast/utils`

Floe runs the copy the extension installed, against the API above. A helper works as far as the API it calls does.

| API | Status | Notes |
| --- | --- | --- |
| `usePromise`, `useCachedPromise`, `useFetch`, `useCachedState`, `useLocalStorage`, `useFrecencySorting`, `useStreamJSON` | Supported | |
| `useExec`, `runAppleScript`, `useSQL`, `executeSQL` | Supported | |
| `showFailureToast`, `getFavicon`, `getAvatarIcon` | Supported | |
| `useForm` | Partial | Errors show, but the first invalid field is not focused. |
| `useAI` | Partial | As `AI.ask`. |
| `withAccessToken`, `OAuthService` | Partial | As `OAuth.PKCEClient`. |
| `createDeeplink` | Partial | As deeplinks. |

## Command modes

| API | Status | Notes |
| --- | --- | --- |
| `view` | Supported | |
| `no-view` | Supported | |
| `menu-bar` | Partial | You add each one by hand. None starts at launch. |
| `interval` | Supported | |

## Node and npm

| API | Status | Notes |
| --- | --- | --- |
| `node-fetch`, `undici`, `ws` | Supported | |
| `.wasm` imports | Supported | |
| `react-dom` | Partial | Only `unstable_batchedUpdates` and `flushSync` do anything. `createPortal` throws. |
| `react-dom/server` | Not yet | |
| `better-sqlite3` | Partial | Runs on Bun's SQLite. Encrypted databases do not open. |
| Other V8 native addons | Not yet | Bun cannot load them. |
| Install scripts | Not yet | Floe installs extensions with scripts off. |
| `swift:` helpers | Partial | Built on the first call, which takes a few minutes and needs Apple's Swift tools. |
| `rust:` helpers | Not yet | Every call fails, as in Raycast on macOS. |
