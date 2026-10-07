//
//  index.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Stand-in for @raycast/api. Components render to plain host elements that renderer.ts serializes;
// everything else either runs locally in Bun or is forwarded to the Swift app over the bridge.
import fs from "node:fs";
import path from "node:path";
import React, { createContext, useContext, useEffect, useMemo, useRef, useState } from "react";
import { ctx, request, send, setPopHandler, setPopToRootHandler } from "../bridge";
import { flushCaches } from "../cache";
import { createLocalStorage, storagePersistence } from "../local-storage";
import { render as mount } from "../renderer";

const h = React.createElement;
// The API is promise-based throughout; most calls here finish synchronously.
const done: Promise<void> = Promise.resolve();
type Props = Record<string, any>;

// Element-valued props (actions, detail, metadata…) travel as named child slots.
function slot(name: string, element: unknown) {
  return element ? h("_slot", { name, key: `_slot_${name}` }, element as React.ReactNode) : null;
}
function host(type: string, slots: string[] = []) {
  const component = (props: Props) => {
    const { children, ...rest } = props;
    const slotted = slots.map((name) => {
      const element = rest[name];
      delete rest[name];
      return slot(name, element);
    });
    return h(type, rest, ...slotted, children);
  };
  component.displayName = type;
  return component as any;
}

// Navigation

type Navigation = { push: (element: React.ReactNode, onPop?: () => void) => void; pop: () => void };
const NavigationContext = createContext<Navigation>({ push() {}, pop() {} });
export const useNavigation = () => useContext(NavigationContext);

export function NavigationRoot({ children }: { children: React.ReactNode }) {
  const [stack, setStack] = useState<{ element: React.ReactNode; onPop?: () => void }[]>([]);
  const stackRef = useRef(stack);
  stackRef.current = stack;

  const navigation = useMemo<Navigation>(
    () => ({
      push: (element, onPop) => setStack((current) => [...current, { element, onPop }]),
      pop: () => {
        stackRef.current.at(-1)?.onPop?.();
        setStack((current) => current.slice(0, -1));
      },
    }),
    [],
  );

  useEffect(() => {
    setPopHandler(() => (stackRef.current.length ? navigation.pop() : send({ type: "exit" })));
    setPopToRootHandler(() => setStack([]));
  }, [navigation]);

  // Lower screens stay mounted so their state survives a push; Swift shows the last one.
  const screens = [children, ...stack.map((entry) => entry.element)];
  return h(
    NavigationContext.Provider,
    { value: navigation },
    screens.map((element, index) => h("_screen", { key: index }, element)),
  );
}

// Views

const metadata = (prefix: string) =>
  Object.assign(host(`${prefix}.Metadata`), {
    Label: host("Metadata.Label"),
    Link: host("Metadata.Link"),
    Separator: host("Metadata.Separator"),
    TagList: Object.assign(host("Metadata.TagList"), { Item: host("Metadata.TagList.Item") }),
  });

// Raycast calls a search bar dropdown's onChange once on mount with the initial value; extensions rely on it.
function firstDropdownValue(children: React.ReactNode): string | undefined {
  for (const child of React.Children.toArray(children)) {
    if (!React.isValidElement(child)) continue;
    const props = child.props as Props;
    if (props.value !== undefined && props.title !== undefined) return props.value;
    const nested = firstDropdownValue(props.children);
    if (nested !== undefined) return nested;
  }
  return undefined;
}
const dropdownStore = () => path.join(ctx.supportPath, "dropdown-values.json");
const dropdown = (prefix: string) => {
  const Host = host(`${prefix}.Dropdown`);
  const Dropdown = (props: Props) => {
    const storeKey = `${ctx.commandName}:${props.id ?? "default"}`;
    const [value, setValue] = useState<string | undefined>(
      () =>
        props.value ??
        (props.storeValue ? readJSON(dropdownStore())[storeKey] : undefined) ??
        props.defaultValue ??
        firstDropdownValue(props.children),
    );
    useEffect(() => {
      if (value !== undefined) props.onChange?.(value);
    }, []);
    const onChange = (next: string) => {
      setValue(next);
      if (props.storeValue) storagePersistence.write(dropdownStore(), JSON.stringify({ ...readJSON(dropdownStore()), [storeKey]: next }));
      props.onChange?.(next);
    };
    return h(Host, { ...props, value: props.value ?? value, onChange });
  };
  return Object.assign(Dropdown, { Item: host("Dropdown.Item"), Section: host("Dropdown.Section") });
};

export const List = Object.assign(host("List", ["actions", "searchBarAccessory"]), {
  Item: Object.assign(host("List.Item", ["actions", "detail"]), {
    Detail: Object.assign(host("List.Item.Detail", ["metadata"]), { Metadata: metadata("List.Item.Detail") }),
  }),
  Section: host("List.Section"),
  EmptyView: host("EmptyView", ["actions"]),
  Dropdown: dropdown("List"),
});

export const Grid = Object.assign(host("Grid", ["actions", "searchBarAccessory"]), {
  Item: host("Grid.Item", ["actions"]),
  Section: host("Grid.Section"),
  EmptyView: host("EmptyView", ["actions"]),
  Dropdown: dropdown("Grid"),
  Inset: { Small: "small", Medium: "medium", Large: "large" },
  ItemSize: { Small: "small", Medium: "medium", Large: "large" },
  Fit: { Contain: "contain", Fill: "fill" },
});

export const Detail = Object.assign(host("Detail", ["actions", "metadata"]), { Metadata: metadata("Detail") });

export const Form = Object.assign(host("Form", ["actions", "searchBarAccessory"]), {
  TextField: host("Form.TextField"),
  PasswordField: host("Form.PasswordField"),
  TextArea: host("Form.TextArea"),
  Checkbox: host("Form.Checkbox"),
  DatePicker: Object.assign(host("Form.DatePicker"), { Type: { Date: "date", DateTime: "dateTime" } }),
  Dropdown: Object.assign(host("Form.Dropdown"), { Item: host("Dropdown.Item"), Section: host("Dropdown.Section") }),
  TagPicker: Object.assign(host("Form.TagPicker"), { Item: host("Form.TagPicker.Item") }),
  FilePicker: host("Form.FilePicker"),
  Description: host("Form.Description"),
  Separator: host("Form.Separator"),
  LinkAccessory: host("Form.LinkAccessory"),
});

export const MenuBarExtra = Object.assign(host("MenuBarExtra"), {
  Item: host("MenuBarExtra.Item"),
  Section: host("MenuBarExtra.Section"),
  Separator: host("MenuBarExtra.Separator"),
  Submenu: host("MenuBarExtra.Submenu"),
});

// Actions

const BaseAction = host("Action");
function action(defaultTitle: string, defaultIcon: string, run: (props: Props, navigation: Navigation) => unknown) {
  return (props: Props) => {
    const navigation = useNavigation();
    return h("Action", {
      title: props.title ?? defaultTitle,
      icon: props.icon ?? `icon:${defaultIcon}`,
      shortcut: props.shortcut,
      style: props.style,
      onAction: () => run(props, navigation),
    });
  };
}

export const Action = Object.assign(BaseAction, {
  Style: { Regular: "regular", Destructive: "destructive" },
  OpenInBrowser: action("Open in Browser", "Globe", async (props) => {
    await open(props.url);
    props.onOpen?.(props.url);
    await closeMainWindow();
  }),
  Open: action("Open", "Finder", async (props) => {
    await open(props.target, props.application);
    props.onOpen?.(props.target);
    await closeMainWindow();
  }),
  CopyToClipboard: action("Copy to Clipboard", "Clipboard", async (props) => {
    await Clipboard.copy(props.content);
    props.onCopy?.(props.content);
    await showHUD("Copied to Clipboard");
  }),
  Paste: action("Paste", "Clipboard", async (props) => {
    await Clipboard.paste(props.content);
    props.onPaste?.(props.content);
  }),
  Push: action("Open", "ArrowRight", (props, navigation) => {
    navigation.push(props.target, props.onPop);
    props.onPush?.();
  }),
  ShowInFinder: action("Show in Finder", "Finder", async (props) => {
    await showInFinder(props.path);
    props.onShow?.(props.path);
    await closeMainWindow();
  }),
  Trash: action("Move to Trash", "Trash", async (props) => {
    await trash(props.paths);
    props.onTrash?.(props.paths);
  }),
  SubmitForm: (props: Props) =>
    h("Action", { title: props.title ?? "Submit", icon: props.icon, shortcut: props.shortcut, isSubmit: true, onSubmit: props.onSubmit }),
  OpenWith: action("Open With", "Finder", (props) => open(props.path)),
  ToggleQuickLook: action("Quick Look", "Eye", () => unsupported("Quick Look")),
  CreateSnippet: action("Create Snippet", "Document", () => unsupported("Snippets")),
  CreateQuicklink: action("Create Quicklink", "Link", () => unsupported("Quicklinks")),
  PickDate: Object.assign(action("Pick Date", "Calendar", () => unsupported("Date picker")), {
    Type: { Date: "date", DateTime: "dateTime" },
  }),
});

export const ActionPanel = Object.assign(host("ActionPanel"), {
  Section: host("ActionPanel.Section"),
  Submenu: host("ActionPanel.Submenu"),
});

// Feedback

function unsupported(feature: string) {
  return showToast({ style: Toast.Style.Failure, title: `${feature} isn't supported yet` });
}

let nextToastId = 1;
const liveToasts = new Map<number, Toast>();
export class Toast {
  static readonly Style = { Success: "success", Failure: "failure", Animated: "animated" } as const;
  private readonly id = nextToastId++;
  private readonly options: Props;
  constructor(options: Props) {
    this.options = { ...options };
    liveToasts.set(this.id, this);
  }
  private sync(hidden = false) {
    const { style, title, message, primaryAction, secondaryAction } = this.options;
    send({ type: "toast", id: this.id, style: style ?? "success", title: title ?? "", message, hidden,
      primaryTitle: (primaryAction as Props | undefined)?.title,
      secondaryTitle: (secondaryAction as Props | undefined)?.title });
  }
  get title() { return this.options.title; }
  set title(value: string) { this.options.title = value; this.sync(); }
  get message() { return this.options.message; }
  set message(value: string | undefined) { this.options.message = value; this.sync(); }
  get style() { return this.options.style; }
  set style(value: string) { this.options.style = value; this.sync(); }
  get primaryAction() { return this.options.primaryAction; }
  set primaryAction(value: unknown) { this.options.primaryAction = value; this.sync(); }
  get secondaryAction() { return this.options.secondaryAction; }
  set secondaryAction(value: unknown) { this.options.secondaryAction = value; this.sync(); }
  show(): Promise<void> { this.sync(); return done; }
  hide(): Promise<void> { liveToasts.delete(this.id); this.sync(true); return done; }
}

// Runs a toast action callback when the app reports it was clicked.
export function handleToastAction(id: number, which: "primary" | "secondary") {
  const toast = liveToasts.get(id);
  const action = (which === "primary" ? toast?.options.primaryAction : toast?.options.secondaryAction) as Props | undefined;
  return action?.onAction?.(toast);
}

export async function showToast(optionsOrStyle: Props | string, title?: string, message?: string) {
  const options = typeof optionsOrStyle === "string" ? { style: optionsOrStyle, title, message } : optionsOrStyle;
  const toast = new Toast(options);
  await toast.show();
  return toast;
}

export function showHUD(title: string, _options?: Props): Promise<void> {
  send({ type: "hud", title });
  return done;
}

export const Alert = { ActionStyle: { Default: "default", Cancel: "cancel", Destructive: "destructive" } };
export async function confirmAlert(options: Props) {
  const primaryTitle = options.primaryAction?.title ?? "OK";
  const dismissTitle = options.dismissAction?.title ?? "Cancel";
  const storageKey = `__floe_alert_${options.title}`;
  if (options.rememberUserChoice && (await LocalStorage.getItem(storageKey)) === true) {
    await options.primaryAction?.onAction?.();
    return true;
  }
  const confirmed = await request("alert.confirm", {
    title: options.title, message: options.message,
    primaryTitle, primaryStyle: options.primaryAction?.style ?? "default", dismissTitle,
  });
  const result = confirmed === true;
  if (result) {
    if (options.rememberUserChoice) await LocalStorage.setItem(storageKey, true);
    await options.primaryAction?.onAction?.();
  } else {
    await options.dismissAction?.onAction?.();
  }
  return result;
}

// Window and system

export const PopToRootType = { Default: "default", Immediate: "immediate", Suspended: "suspended" };
export function closeMainWindow(_options?: Props): Promise<void> {
  // A background run is killed as soon as the app reads "close".
  flushCaches();
  send({ type: "close" });
  return done;
}
export function popToRoot(_options?: Props): Promise<void> {
  send({ type: "popToRoot" });
  return done;
}
export function clearSearchBar(_options?: Props): Promise<void> {
  send({ type: "clearSearchBar" });
  return done;
}

export function open(target: string, application?: string | { path?: string; name?: string }): Promise<void> {
  const app = typeof application === "string" ? application : (application?.path ?? application?.name);
  send({ type: "open", target, application: app });
  return done;
}
export function showInFinder(target: string): Promise<void> {
  Bun.spawn(["open", "-R", target]);
  return done;
}
export function trash(paths: string | string[]): Promise<void> {
  for (const file of [paths].flat()) {
    const destination = path.join(process.env.HOME ?? "", ".Trash", `${path.basename(file)}`);
    fs.renameSync(file, fs.existsSync(destination) ? `${destination} ${Date.now()}` : destination);
  }
  return done;
}

type ClipboardContent = string | number | Props;
function clipboardParams(content: ClipboardContent): { text?: string; html?: string; file?: string } {
  if (typeof content === "object" && content !== null) {
    return { text: content.text, html: content.html, file: content.file };
  }
  if (typeof content === "number") return { text: String(content) };
  return { text: typeof content === "string" ? content : "" };
}

export const Clipboard = {
  copy(content: ClipboardContent, _options?: Props): Promise<void> {
    const params = clipboardParams(content);
    send({ type: "copy", text: params.text ?? "", html: params.html, file: params.file });
    return done;
  },
  paste(content: ClipboardContent): Promise<void> {
    const params = clipboardParams(content);
    send({ type: "paste", text: params.text ?? "", html: params.html, file: params.file });
    return done;
  },
  async readText(_options?: Props): Promise<string | undefined> {
    const result = await request<{ text: string; html?: string; file?: string }>("clipboard.read");
    return result.text || undefined;
  },
  async read(_options?: Props): Promise<{ text: string; html?: string; file?: string }> {
    return request("clipboard.read");
  },
  clear(): Promise<void> {
    send({ type: "copy", text: "" });
    return done;
  },
};

export function getSelectedText(): Promise<string> {
  return request("selectedText");
}
export function getSelectedFinderItems(): Promise<{ path: string }[]> {
  return request("selectedFinderItems");
}
type Application = { name: string; path: string; bundleId?: string };
let applications: Application[] | undefined;
export function getApplications(_path?: string): Promise<Application[]> {
  applications ??= Bun.spawnSync(["mdfind", "-attr", "kMDItemCFBundleIdentifier", "kMDItemContentType == 'com.apple.application-bundle'"])
    .stdout.toString()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      // mdfind prints "<path>   kMDItemCFBundleIdentifier = <id>".
      const marker = line.indexOf("kMDItemCFBundleIdentifier = ");
      const appPath = (marker < 0 ? line : line.slice(0, marker)).trim();
      const bundleId = marker < 0 ? "" : line.slice(marker + "kMDItemCFBundleIdentifier = ".length).trim();
      return { name: path.basename(appPath, ".app"), path: appPath, bundleId: bundleId && bundleId !== "(null)" ? bundleId : undefined };
    });
  return Promise.resolve(applications);
}
const finder: Application = { name: "Finder", path: "/System/Library/CoreServices/Finder.app", bundleId: "com.apple.finder" };
export function getDefaultApplication(_path: string): Promise<Application> {
  return Promise.resolve(finder);
}
export function getFrontmostApplication(): Promise<Application> {
  return Promise.resolve(finder);
}

// Storage

function readJSON(file: string): Record<string, any> {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return {};
  }
}
// The implementation lives in local-storage.ts; the file is the extension's, shared by all of its commands.
export const LocalStorage = createLocalStorage(() => path.join(ctx.supportPath, "local-storage.json"));

// The bounded implementation lives in cache.ts; this re-export keeps the API surface stable.
export { Cache } from "../cache";

export function getPreferenceValues<T = Props>(): T {
  // The app resolves defaults, stored values and Keychain secrets and passes the result in.
  if (process.env.FLOE_PREFERENCES) return JSON.parse(process.env.FLOE_PREFERENCES) as T;
  const command = ctx.manifest.commands?.find((candidate) => candidate.name === ctx.commandName);
  const declared = [...(ctx.manifest.preferences ?? []), ...(command?.preferences ?? [])];
  const defaults = Object.fromEntries(declared.filter((pref) => pref.default !== undefined).map((pref) => [pref.name, pref.default]));
  return { ...defaults, ...readJSON(path.join(ctx.supportPath, "preferences.json")) } as T;
}
export function openExtensionPreferences(): Promise<void> {
  send({ type: "openPreferences" });
  return done;
}
export function openCommandPreferences(): Promise<void> {
  send({ type: "openPreferences" });
  return done;
}

// Environment

export const LaunchType = { UserInitiated: "userInitiated", Background: "background" };
export const environment = {
  get extensionName() { return ctx.manifest.name; },
  get commandName() { return ctx.commandName; },
  get commandMode() { return ctx.commandMode; },
  get assetsPath() { return path.join(ctx.extDir, "assets"); },
  get supportPath() { return ctx.supportPath; },
  get ownerOrAuthorName() { return ctx.manifest.owner ?? ctx.manifest.author ?? ""; },
  raycastVersion: "1.100.0",
  isDevelopment: true,
  appearance: "dark",
  theme: "dark",
  textSize: "medium",
  get launchType() { return ctx.launchType; },
  // The app sets FLOE_AI when AI.ask has something to answer it: an installed tool or a filled-in API.
  canAccess: (api: unknown) => api === AI && process.env.FLOE_AI === "1",
};

export function launchCommand(_options: Props): Promise<void> {
  return Promise.reject(new Error("launchCommand isn't supported yet"));
}
// Subtitles set from a command aren't shown anywhere yet, so there is nothing to update.
export function updateCommandMetadata(_metadata: Props): Promise<void> {
  return done;
}
export function captureException(error: unknown) {
  console.error(error);
}

type AskOptions = { model?: string; creativity?: unknown; signal?: AbortSignal };
export const AI = {
  // Creativity is a plain string or number in Raycast, and the tools Floe runs take none.
  Creativity: {},
  // AI.Model.Anthropic_Claude_Sonnet → "Anthropic_Claude_Sonnet"; the app picks the closest model the installed tool has.
  Model: new Proxy({} as Record<string, string>, {
    get: (_target, key) => (typeof key === "string" ? key : undefined),
  }),
  // Answered by the app, with what Settings › General › AI says: an installed tool or an API.
  ask(prompt: string, options: AskOptions = {}) {
    const listeners: ((text: string) => void)[] = [];
    const emit = (text: string) => listeners.forEach((listener) => listener(text));
    let streamed = false;
    const onChunk = (chunk: string) => {
      streamed = true;
      emit(chunk);
    };
    const answer = request<string>("ai.ask", { prompt, model: options.model }, { signal: options.signal, onChunk }).then((text) => {
      // An answer that arrived whole still fires "data", once, with all of it.
      if (!streamed) emit(text);
      return text;
    });
    return Object.assign(answer, {
      on(event: string, listener: (text: string) => void) {
        if (event === "data") listeners.push(listener);
      },
    });
  },
};
export { OAuth } from "./oauth";

// Constants

// Icon.Foo → "icon:Foo", Color.Red → "color:Red"; the Swift side maps names to SF Symbols and system colors.
const named = (prefix: string) =>
  new Proxy({} as Record<string, string>, {
    get: (_target, key) => (typeof key === "string" ? `${prefix}:${key}` : undefined),
  });
export const Icon = named("icon");
export const Color = named("color");
export const Image = { Mask: { Circle: "circle", RoundedRectangle: "roundedRectangle" } };

const shortcut = (modifiers: string[], key: string) => ({ modifiers, key });
export const Keyboard = {
  Shortcut: {
    Common: {
      Copy: shortcut(["cmd", "shift"], "c"),
      CopyDeeplink: shortcut(["cmd", "shift"], "c"),
      CopyName: shortcut(["cmd", "shift"], "."),
      CopyPath: shortcut(["cmd", "shift"], ","),
      Duplicate: shortcut(["cmd"], "d"),
      Edit: shortcut(["cmd"], "e"),
      MoveDown: shortcut(["cmd", "shift"], "arrowDown"),
      MoveUp: shortcut(["cmd", "shift"], "arrowUp"),
      New: shortcut(["cmd"], "n"),
      Open: shortcut(["cmd"], "o"),
      OpenWith: shortcut(["cmd", "shift"], "o"),
      Pin: shortcut(["cmd", "shift"], "p"),
      Refresh: shortcut(["cmd"], "r"),
      Remove: shortcut(["ctrl"], "x"),
      RemoveAll: shortcut(["ctrl", "shift"], "x"),
      ToggleQuickLook: shortcut(["cmd"], "y"),
    },
  },
};

// Deprecated names that older store extensions still import

export const ActionPanelItem = Action;
export const ActionPanelSection = ActionPanel.Section;
export const ActionPanelSubmenu = ActionPanel.Submenu;
export const CopyToClipboardAction = Action.CopyToClipboard;
export const OpenInBrowserAction = Action.OpenInBrowser;
export const OpenAction = Action.Open;
export const OpenWithAction = Action.OpenWith;
export const PasteAction = Action.Paste;
export const PushAction = Action.Push;
export const ShowInFinderAction = Action.ShowInFinder;
export const SubmitFormAction = Action.SubmitForm;
export const TrashAction = Action.Trash;
export const ListItem = List.Item;
export const ListSection = List.Section;
export const FormTextField = Form.TextField;
export const FormTextArea = Form.TextArea;
export const FormCheckbox = Form.Checkbox;
export const FormDatePicker = Form.DatePicker;
export const FormDropdown = Form.Dropdown;
export const FormDropdownItem = Form.Dropdown.Item;
export const FormDropdownSection = Form.Dropdown.Section;
export const FormSeparator = Form.Separator;
export const FormTagPicker = Form.TagPicker;
export const FormTagPickerItem = Form.TagPicker.Item;
export const ImageMask = Image.Mask;
export const AlertActionStyle = Alert.ActionStyle;
export const ToastStyle = Toast.Style;
export const copyTextToClipboard = (text: string) => Clipboard.copy(text);
export const pasteText = (text: string) => Clipboard.paste(text);
export const clearClipboard = () => Clipboard.clear();
export const getLocalStorageItem = LocalStorage.getItem;
export const setLocalStorageItem = LocalStorage.setItem;
export const removeLocalStorageItem = LocalStorage.removeItem;
export const allLocalStorageItems = LocalStorage.allItems;
export const clearLocalStorage = LocalStorage.clear;
export const preferences = new Proxy({} as Record<string, { value: unknown }>, {
  get: (_target, key) => ({ value: getPreferenceValues<Props>()[key as string] }),
});

// Raycast's browser extension and window manager, which Floe has no counterpart for. The names are here because
// a missing export stops a command before it runs; environment.canAccess says no, and a call says why.
const refusing = (name: string) => (): Promise<never> => Promise.reject(new Error(`${name} isn't supported in Floe yet`));
export const BrowserExtension = {
  getTabs: refusing("BrowserExtension.getTabs"),
  getContent: refusing("BrowserExtension.getContent"),
};
export const WindowManagement = {
  DesktopType: { User: "User", FullScreen: "FullScreen" },
  getDesktops: refusing("WindowManagement.getDesktops"),
  getActiveWindow: refusing("WindowManagement.getActiveWindow"),
  getWindowsOnActiveDesktop: refusing("WindowManagement.getWindowsOnActiveDesktop"),
  setWindowBounds: refusing("WindowManagement.setWindowBounds"),
};
// Only types live under Tool; the value exists because Raycast exports one.
export const Tool = {};

// Names Raycast still exports and has deprecated.
export const unstable_AI = AI;
export const useUnstableAI = () => undefined;
export const randomId = () => crypto.randomUUID();
export const useId = React.useId;
export const useActionPanel = () => ({ update: (_actionPanel: React.ReactNode) => {} });
const keyNames = ["return", "delete", "deleteForward", "tab", "arrowUp", "arrowDown", "arrowLeft", "arrowRight", "pageUp", "pageDown", "home", "end", "space", "escape", "enter", "backspace"];
export const specialKeys = Object.fromEntries(keyNames.map((key) => [key, key]));

let drewItself = false;
// How a command drew its view before it could export one: it calls this where a newer one exports a component.
export function render(element: React.ReactElement) {
  drewItself = true;
  mount(h(NavigationRoot, null, element));
}
// For the host: whether the command has already put its view up through render().
export const commandDrewItself = () => drewItself;
