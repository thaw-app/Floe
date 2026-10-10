//
//  system.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, beforeEach, describe, expect, mock, spyOn, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import * as api from "../api/index";
import { isLent } from "../api/oauth";
import { ctx, handleReply, handleReplyChunk } from "../bridge";
import { installRuntime, sent } from "./support";

const runtime = installRuntime("system-tests");

// Stands in for the macOS tools the shim shells out to, so no dialog, clipboard read or Spotlight query happens.
function stubSpawnSync(stdout: string) {
  const spy = spyOn(Bun, "spawnSync").mockImplementation((() => ({ stdout: Buffer.from(stdout) })) as never);
  return { commands: () => spy.mock.calls.map(([command]) => command as unknown as string[]) };
}

let savedPreferences: string | undefined;
beforeEach(() => {
  savedPreferences = process.env.FLOE_PREFERENCES;
  delete process.env.FLOE_PREFERENCES;
});
afterEach(() => {
  mock.restore();
  if (savedPreferences !== undefined) process.env.FLOE_PREFERENCES = savedPreferences;
});

describe("toasts and HUD", () => {
  test("showToast sends the toast and returns a handle that updates it", async () => {
    const toast = await api.showToast({ style: api.Toast.Style.Animated, title: "Loading", message: "one moment" });
    toast.title = "Done";
    toast.message = undefined;
    toast.style = api.Toast.Style.Success;
    await toast.hide();

    const [shown, retitled, cleared, restyled, hidden] = sent("toast");
    expect(shown).toEqual({ type: "toast", id: shown.id, style: "animated", title: "Loading", message: "one moment", hidden: false });
    expect(retitled).toMatchObject({ id: shown.id, title: "Done", style: "animated" });
    expect(cleared).not.toHaveProperty("message");
    expect(restyled).toMatchObject({ id: shown.id, style: "success", hidden: false });
    expect(hidden).toMatchObject({ id: shown.id, title: "Done", hidden: true });
    expect([toast.title, toast.message, toast.style]).toEqual(["Done", undefined, "success"]);
  });

  test("showToast still accepts the old (style, title, message) form", async () => {
    await api.showToast(api.Toast.Style.Failure, "Could not load", "offline");
    expect(sent("toast")).toEqual([expect.objectContaining({ style: "failure", title: "Could not load", message: "offline" })]);
  });

  test("a toast defaults to a success style and gets its own id", async () => {
    const first = new api.Toast({});
    const second = new api.Toast({ title: "Second" });
    await first.show();
    await second.show();
    const [one, two] = sent("toast");
    expect(one).toMatchObject({ style: "success", title: "", hidden: false });
    expect(two.id).not.toBe(one.id);
  });

  test("toast actions sync their titles and run when the app reports a click", async () => {
    const calls: string[] = [];
    const toast = new api.Toast({
      title: "Saved",
      primaryAction: { title: "Undo", onAction: () => calls.push("primary") },
      secondaryAction: { title: "Dismiss", onAction: () => calls.push("secondary") },
    });
    await toast.show();
    const shown = sent("toast")[0];
    expect(shown).toMatchObject({ primaryTitle: "Undo", secondaryTitle: "Dismiss" });

    api.handleToastAction(shown.id, "primary");
    api.handleToastAction(shown.id, "secondary");
    api.handleToastAction(-1, "primary");
    expect(calls).toEqual(["primary", "secondary"]);

    toast.primaryAction = { title: "Redo", onAction: () => calls.push("redo") };
    expect(sent("toast").at(-1)).toMatchObject({ id: shown.id, primaryTitle: "Redo" });
    api.handleToastAction(shown.id, "primary");
    expect(calls).toEqual(["primary", "secondary", "redo"]);
  });

  test("changing the options object after creating the toast does not change the toast", async () => {
    const options = { title: "Original" };
    const toast = new api.Toast(options);
    options.title = "Mutated";
    await toast.show();
    expect(sent("toast")[0].title).toBe("Original");
  });

  test("showHUD sends the title", async () => {
    await api.showHUD("Copied", { clearRootSearch: true });
    expect(sent()).toEqual([{ type: "hud", title: "Copied" }]);
  });

  // What a command without a view does to report on itself, as the NetBird extension's connect does.
  test("progress, then the window closed, then the result all reach the app in that order", async () => {
    const progress = await api.showToast({ style: api.Toast.Style.Animated, title: "Connecting", message: "Please wait..." });
    await progress.hide();
    await api.closeMainWindow({ clearRootSearch: true });
    await api.showToast({ style: api.Toast.Style.Success, title: "Connected", message: "" });
    const id = sent("toast")[0].id;
    expect(sent()).toEqual([
      { type: "toast", id, style: "animated", title: "Connecting", message: "Please wait...", hidden: false },
      expect.objectContaining({ type: "toast", id, hidden: true }),
      { type: "close" },
      expect.objectContaining({ type: "toast", style: "success", title: "Connected", message: "", hidden: false }),
    ]);
    expect(sent("toast").at(-1)?.id).not.toBe(id);
  });

  // The shape @raycast/utils' showFailureToast gives showToast: the error as the message, and an action to copy it.
  test("a failure toast carries its reason and its action's title", async () => {
    const error = new Error("daemon is not running");
    await api.showToast({
      style: api.Toast.Style.Failure,
      title: "Failed to connect",
      message: error.message,
      primaryAction: { title: "Copy Logs", onAction: () => {} },
    });
    expect(sent()).toEqual([
      expect.objectContaining({ type: "toast", style: "failure", title: "Failed to connect", message: "daemon is not running", primaryTitle: "Copy Logs", hidden: false }),
    ]);
  });
});

describe("confirmAlert", () => {
  const options = (calls: string[]) => ({
    title: "Delete notes?",
    message: "This cannot be undone.",
    primaryAction: { title: "Delete", style: api.Alert.ActionStyle.Destructive, onAction: () => calls.push("confirmed") },
    dismissAction: { title: "Keep", onAction: () => calls.push("dismissed") },
  });

  test("asks the app and resolves true with the primary action when confirmed", async () => {
    const calls: string[] = [];
    const asked = api.confirmAlert(options(calls));
    const [ask] = sent("request");
    expect(ask).toMatchObject({
      method: "alert.confirm",
      params: {
        title: "Delete notes?",
        message: "This cannot be undone.",
        primaryTitle: "Delete",
        primaryStyle: "destructive",
        dismissTitle: "Keep",
      },
    });
    handleReply({ id: ask.id, result: true });
    expect(await asked).toBe(true);
    expect(calls).toEqual(["confirmed"]);
  });

  test("resolves false with the dismiss action when dismissed", async () => {
    const calls: string[] = [];
    const asked = api.confirmAlert(options(calls));
    handleReply({ id: sent("request")[0].id, result: false });
    expect(await asked).toBe(false);
    expect(calls).toEqual(["dismissed"]);
  });

  test("uses OK and Cancel when no actions are given", async () => {
    const asked = api.confirmAlert({ title: "Sure?" });
    expect(sent("request")[0].params).toMatchObject({ primaryTitle: "OK", primaryStyle: "default", dismissTitle: "Cancel" });
    handleReply({ id: sent("request")[0].id, result: true });
    expect(await asked).toBe(true);
  });

  test("rememberUserChoice skips the dialog once confirmed, remembered per title", async () => {
    await api.LocalStorage.clear();
    const first: string[] = [];
    const one = api.confirmAlert({ ...options(first), rememberUserChoice: true });
    await Bun.sleep(0);
    handleReply({ id: sent("request")[0].id, result: true });
    expect(await one).toBe(true);
    expect(first).toEqual(["confirmed"]);

    const second: string[] = [];
    expect(await api.confirmAlert({ ...options(second), rememberUserChoice: true })).toBe(true);
    expect(sent("request")).toHaveLength(1);
    expect(second).toEqual(["confirmed"]);

    const other: string[] = [];
    const third = api.confirmAlert({ ...options(other), title: "Delete other?", rememberUserChoice: true });
    await Bun.sleep(0);
    expect(sent("request")).toHaveLength(2);
    handleReply({ id: sent("request")[1].id, result: false });
    expect(await third).toBe(false);
    expect(other).toEqual(["dismissed"]);
  });
});

describe("window and system", () => {
  test("window calls each send their message", async () => {
    await api.closeMainWindow({ clearRootSearch: true });
    await api.popToRoot();
    await api.clearSearchBar();
    await api.openExtensionPreferences();
    await api.openCommandPreferences();
    expect(sent().map((message) => message.type)).toEqual(["close", "popToRoot", "clearSearchBar", "openPreferences", "openPreferences"]);
  });

  test("open sends the target with the application as a name, a path, or nothing", async () => {
    await api.open("https://example.com");
    await api.open("/tmp/a.txt", "com.apple.TextEdit");
    await api.open("/tmp/a.txt", { name: "TextEdit" });
    await api.open("/tmp/a.txt", { name: "TextEdit", path: "/Applications/TextEdit.app" });
    expect(sent("open")).toEqual([
      { type: "open", target: "https://example.com" },
      { type: "open", target: "/tmp/a.txt", application: "com.apple.TextEdit" },
      { type: "open", target: "/tmp/a.txt", application: "TextEdit" },
      { type: "open", target: "/tmp/a.txt", application: "/Applications/TextEdit.app" },
    ]);
  });

  test("getApplications parses the Spotlight listing once and reuses it", async () => {
    const tool = stubSpawnSync(
      [
        "/Applications/Safari.app   kMDItemCFBundleIdentifier = com.apple.Safari",
        "/Applications/Odd Tool.app   kMDItemCFBundleIdentifier = (null)",
        "/Applications/Bare.app",
        "",
      ].join("\n"),
    );
    const applications = await api.getApplications();
    expect(applications).toEqual([
      { name: "Safari", path: "/Applications/Safari.app", bundleId: "com.apple.Safari" },
      { name: "Odd Tool", path: "/Applications/Odd Tool.app", bundleId: undefined },
      { name: "Bare", path: "/Applications/Bare.app", bundleId: undefined },
    ]);
    expect(await api.getApplications("/tmp/file.txt")).toBe(applications);
    expect(tool.commands()).toHaveLength(1);
    expect(tool.commands()[0][0]).toBe("mdfind");
  });

  test("the default and frontmost application come from the app, Finder when it names none", async () => {
    const frontmost = api.getFrontmostApplication();
    expect(sent("request")[0]).toMatchObject({ method: "environment.frontmostApplication" });
    handleReply({ id: sent("request")[0].id, result: { name: "Ghostty", path: "/Applications/Ghostty.app", bundleId: "com.mitchellh.ghostty" } });
    await expect(frontmost).resolves.toMatchObject({ name: "Ghostty", bundleId: "com.mitchellh.ghostty" });

    const nothing = api.getFrontmostApplication();
    handleReply({ id: sent("request")[1].id, result: null });
    await expect(nothing).resolves.toMatchObject({ name: "Finder" });

    const opener = api.getDefaultApplication("/tmp/file.txt");
    expect(sent("request")[2]).toMatchObject({ method: "environment.getDefaultApplication", params: { path: "/tmp/file.txt" } });
    handleReply({ id: sent("request")[2].id, result: null });
    await expect(opener).resolves.toMatchObject({ name: "Finder", bundleId: "com.apple.finder" });
  });

  test("the selected text and Finder selection come from the app", async () => {
    const text = api.getSelectedText();
    expect(sent("request")[0]).toMatchObject({ method: "selectedText" });
    handleReply({ id: sent("request")[0].id, result: "highlighted" });
    expect(await text).toBe("highlighted");
    const items = api.getSelectedFinderItems();
    handleReply({ id: sent("request")[1].id, error: "No files are selected in the Finder." });
    await expect(items).rejects.toThrow("No files are selected in the Finder.");
  });

  test("calls that are not supported yet reject with a message saying so", async () => {
    await expect(api.launchCommand({ name: "other" })).rejects.toThrow("launchCommand isn't supported yet");
    expect(await api.updateCommandMetadata({ subtitle: "3 unread" })).toBeUndefined();
  });

  test("captureException logs the error", () => {
    const consoleError = spyOn(console, "error").mockImplementation(() => {});
    const error = new Error("captured");
    api.captureException(error);
    expect(consoleError.mock.calls).toEqual([[error]]);
  });
});

describe("Clipboard", () => {
  test("copy sends text from a string, a number, or a content object", async () => {
    await api.Clipboard.copy("plain");
    await api.Clipboard.copy(7);
    await api.Clipboard.copy({ text: "from text" });
    await api.Clipboard.copy({ file: "/tmp/a.png" });
    await api.Clipboard.copy({ html: "<b>bold</b>" });
    await api.Clipboard.copy({});
    expect(sent("copy").map((message) => message.text)).toEqual(["plain", "7", "from text", "", "", ""]);
    expect(sent("copy")[3].file).toBe("/tmp/a.png");
    expect(sent("copy")[4].html).toBe("<b>bold</b>");
  });

  test("paste sends the text to paste", async () => {
    await api.Clipboard.paste("typed");
    await api.Clipboard.paste({ text: "from object" });
    await api.Clipboard.paste({});
    expect(sent().map((message) => message.text)).toEqual(["typed", "from object", ""]);
    expect(sent().every((message) => message.type === "paste")).toBe(true);
  });

  test("clear copies an empty string", async () => {
    await api.Clipboard.clear();
    expect(sent()).toEqual([{ type: "copy", text: "" }]);
  });

  test("read asks the app for text, HTML and file", async () => {
    const read = api.Clipboard.read();
    expect(sent("request")[0]).toMatchObject({ method: "clipboard.read" });
    handleReply({ id: sent("request")[0].id, result: { text: "on the clipboard", html: "<p>on</p>" } });
    expect(await read).toEqual({ text: "on the clipboard", html: "<p>on</p>" });
  });

  test("an empty clipboard reads as undefined text", async () => {
    const text = api.Clipboard.readText();
    handleReply({ id: sent("request")[0].id, result: { text: "" } });
    expect(await text).toBeUndefined();
  });
});

describe("LocalStorage", () => {
  test("stores, lists, removes and clears values, keeping their types", async () => {
    await api.LocalStorage.clear();
    expect(await api.LocalStorage.getItem("missing")).toBeUndefined();

    await api.LocalStorage.setItem("name", "Ada");
    await api.LocalStorage.setItem("count", 3);
    await api.LocalStorage.setItem("enabled", true);
    expect(await api.LocalStorage.getItem("name")).toBe("Ada");
    expect(await api.LocalStorage.getItem<number>("count")).toBe(3);
    expect(await api.LocalStorage.allItems()).toEqual({ name: "Ada", count: 3, enabled: true });

    await api.LocalStorage.removeItem("count");
    expect(await api.LocalStorage.allItems()).toEqual({ name: "Ada", enabled: true });

    await api.LocalStorage.clear();
    expect(await api.LocalStorage.allItems()).toEqual({});
  });

  test("keeps its values in the extension's support folder", async () => {
    await api.LocalStorage.setItem("kept", "yes");
    expect(JSON.parse(fs.readFileSync(path.join(runtime.supportPath, "local-storage.json"), "utf8")).kept).toBe("yes");
  });

  test("treats a missing or damaged file as empty", async () => {
    fs.writeFileSync(path.join(runtime.supportPath, "local-storage.json"), "{not json");
    expect(await api.LocalStorage.allItems()).toEqual({});
    await api.LocalStorage.setItem("fresh", "start");
    expect(await api.LocalStorage.allItems()).toEqual({ fresh: "start" });
  });
});

describe("Cache", () => {
  test("stores strings and reports what it holds", () => {
    const cache = new api.Cache({ namespace: "basic" });
    expect(cache.isEmpty).toBe(true);
    cache.set("token", "abc");
    expect(cache.isEmpty).toBe(false);
    expect(cache.has("token")).toBe(true);
    expect(cache.get("token")).toBe("abc");
    expect(cache.has("other")).toBe(false);
    expect(cache.get("other")).toBeUndefined();

    expect(cache.remove("token")).toBe(true);
    expect(cache.remove("token")).toBe(false);
    cache.set("a", "1");
    cache.clear();
    expect(cache.isEmpty).toBe(true);
  });

  test("persists per namespace across instances", () => {
    new api.Cache({ namespace: "persisted" }).set("key", "value");
    expect(new api.Cache({ namespace: "persisted" }).get("key")).toBe("value");
    expect(new api.Cache({ namespace: "elsewhere" }).has("key")).toBe(false);
    expect(new api.Cache().has("key")).toBe(false);
    expect(fs.existsSync(path.join(runtime.supportPath, "cache-persisted.json"))).toBe(true);
  });

  test("its methods work when passed around unbound", () => {
    const { set, get, has, remove, clear, subscribe } = new api.Cache({ namespace: "unbound" });
    const seen: unknown[][] = [];
    subscribe((key, data) => seen.push([key, data]));
    set("key", "value");
    expect(get("key")).toBe("value");
    expect(has("key")).toBe(true);
    expect(remove("key")).toBe(true);
    clear();
    expect(seen).toEqual([
      ["key", "value"],
      ["key", undefined],
      [undefined, undefined],
    ]);
  });

  test("tells subscribers about changes until they unsubscribe", () => {
    const cache = new api.Cache({ namespace: "subscribers" });
    const first: unknown[] = [];
    const second: unknown[] = [];
    const unsubscribe = cache.subscribe((key) => first.push(key));
    cache.subscribe((key) => second.push(key));
    cache.set("a", "1");
    unsubscribe();
    cache.set("b", "2");
    expect(first).toEqual(["a"]);
    expect(second).toEqual(["a", "b"]);
  });
});

describe("getPreferenceValues", () => {
  const manifest = {
    name: "system-tests",
    preferences: [{ name: "greeting", default: "Hello" }, { name: "token" }, { name: "shout", default: false }],
    commands: [{ name: "main", preferences: [{ name: "limit", default: 10 }] }, { name: "other", preferences: [{ name: "unrelated", default: 1 }] }],
  };
  const preferencesFile = () => path.join(runtime.supportPath, "preferences.json");
  beforeEach(() => {
    ctx.manifest = manifest;
    fs.rmSync(preferencesFile(), { force: true });
  });

  test("uses what the app passes in the environment, ignoring the manifest", () => {
    process.env.FLOE_PREFERENCES = JSON.stringify({ greeting: "Hi", token: "secret" });
    expect(api.getPreferenceValues()).toEqual({ greeting: "Hi", token: "secret" });
  });

  test("without the app, falls back to the defaults of the extension and the running command", () => {
    expect(api.getPreferenceValues()).toEqual({ greeting: "Hello", shout: false, limit: 10 });
  });

  test("values in preferences.json override the defaults", () => {
    fs.writeFileSync(preferencesFile(), JSON.stringify({ greeting: "Hola", token: "from file" }));
    expect(api.getPreferenceValues()).toEqual({ greeting: "Hola", shout: false, limit: 10, token: "from file" });
  });

  test("a manifest without preferences gives an empty object", () => {
    ctx.manifest = { name: "bare" };
    expect(api.getPreferenceValues()).toEqual({});
  });

  test("the deprecated preferences object reads the same values lazily", () => {
    expect(api.preferences.greeting).toEqual({ value: "Hello" });
    process.env.FLOE_PREFERENCES = JSON.stringify({ greeting: "Hi" });
    expect(api.preferences.greeting.value).toBe("Hi");
    expect(api.preferences.missing).toEqual({ value: undefined });
  });
});

describe("AI", () => {
  let savedAI: string | undefined;
  beforeEach(() => {
    savedAI = process.env.FLOE_AI;
  });
  afterEach(() => {
    if (savedAI === undefined) delete process.env.FLOE_AI;
    else process.env.FLOE_AI = savedAI;
  });

  test("ask sends the prompt to the app and resolves with its reply", async () => {
    const answer = api.AI.ask("why?", { model: api.AI.Model.Anthropic_Claude_Sonnet });
    const chunks: string[] = [];
    answer.on("data", (text) => chunks.push(text));
    answer.on("end", () => chunks.push("never"));
    const [request] = sent("request");
    expect(request).toMatchObject({ method: "ai.ask", params: { prompt: "why?", model: "Anthropic_Claude_Sonnet" } });
    handleReply({ id: request.id, result: "because" });
    expect(await answer).toBe("because");
    expect(chunks).toEqual(["because"]);
  });

  test("an answer that streams fires data per piece, and not again when it is whole", async () => {
    const answer = api.AI.ask("why?");
    const chunks: string[] = [];
    answer.on("data", (text) => chunks.push(text));
    const { id } = sent("request")[0];
    handleReplyChunk({ id, chunk: "be" });
    handleReplyChunk({ id, chunk: "cause" });
    handleReplyChunk({ id: -1, chunk: "stray" });
    handleReply({ id, result: "because" });
    expect(await answer).toBe("because");
    expect(chunks).toEqual(["be", "cause"]);
  });

  test("ask rejects with what the app said went wrong", async () => {
    const answer = api.AI.ask("why?");
    handleReply({ id: sent("request")[0].id, error: "not signed in" });
    await expect(answer).rejects.toThrow("not signed in");
  });

  test("aborting an ask tells the app to stop and rejects", async () => {
    const controller = new AbortController();
    const answer = api.AI.ask("why?", { signal: controller.signal });
    const { id } = sent("request")[0];
    controller.abort();
    await expect(answer).rejects.toThrow("aborted");
    expect(sent("cancelRequest")).toEqual([{ type: "cancelRequest", id }]);
    // A reply that was already on its way finds nobody waiting.
    handleReply({ id, result: "too late" });
  });

  test("an ask whose signal is already aborted is never sent", async () => {
    await expect(api.AI.ask("why?", { signal: AbortSignal.abort() })).rejects.toThrow("aborted");
    expect(sent("request")).toEqual([]);
  });

  test("model names are their own keys", () => {
    expect(api.AI.Model.OpenAI_GPT4o).toBe("OpenAI_GPT4o");
    expect((api.AI.Model as Record<symbol, unknown>)[Symbol.iterator]).toBeUndefined();
  });

  test("an installed extension is not in development, so it does not show its sample data", () => {
    delete process.env.FLOE_DEVELOPMENT;
    expect(api.environment.isDevelopment).toBe(false);
    process.env.FLOE_DEVELOPMENT = "1";
    expect(api.environment.isDevelopment).toBe(true);
    delete process.env.FLOE_DEVELOPMENT;
  });

  test("extensions can use AI when the app found a tool for it", () => {
    delete process.env.FLOE_AI;
    expect(api.environment.canAccess(api.AI)).toBe(false);
    process.env.FLOE_AI = "1";
    expect(api.environment.canAccess(api.AI)).toBe(true);
    expect(api.environment.canAccess(api.OAuth)).toBe(false);
  });
});

describe("what Raycast exports", () => {
  // Every value @raycast/api 1.103.10 exports, read from its type declarations. A command that imports a name
  // missing here stops before it runs, as Proton Pass did on BrowserExtension.
  const exported = [
    "AI", "Action", "ActionPanel", "ActionPanelItem", "ActionPanelSection", "ActionPanelSubmenu", "Alert",
    "AlertActionStyle", "BrowserExtension", "Cache", "Clipboard", "Color", "CopyToClipboardAction", "Detail", "Form",
    "FormCheckbox", "FormDatePicker", "FormDropdown", "FormDropdownItem", "FormDropdownSection", "FormSeparator",
    "FormTagPicker", "FormTagPickerItem", "FormTextArea", "FormTextField", "Grid", "Icon", "Image", "ImageMask",
    "Keyboard", "LaunchType", "List", "ListItem", "ListSection", "LocalStorage", "MenuBarExtra", "OAuth",
    "OpenAction", "OpenInBrowserAction", "OpenWithAction", "PasteAction", "PopToRootType", "PushAction",
    "ShowInFinderAction", "SubmitFormAction", "Toast", "ToastStyle", "Tool", "TrashAction", "WindowManagement",
    "allLocalStorageItems", "captureException", "clearClipboard", "clearLocalStorage", "clearSearchBar",
    "closeMainWindow", "confirmAlert", "copyTextToClipboard", "environment", "getApplications",
    "getDefaultApplication", "getFrontmostApplication", "getLocalStorageItem", "getPreferenceValues",
    "getSelectedFinderItems", "getSelectedText", "launchCommand", "open", "openCommandPreferences",
    "openExtensionPreferences", "pasteText", "popToRoot", "preferences", "randomId", "removeLocalStorageItem",
    "render", "setLocalStorageItem", "showHUD", "showInFinder", "showToast", "specialKeys", "trash", "unstable_AI",
    "updateCommandMetadata", "useActionPanel", "useId", "useNavigation", "useUnstableAI",
  ];

  test("every name can be imported", () => {
    expect(exported.filter((name) => !(name in api))).toEqual([]);
  });

  test("the browser and the windows are refused, with the reason", async () => {
    expect(api.environment.canAccess(api.BrowserExtension)).toBe(false);
    expect(api.environment.canAccess(api.WindowManagement)).toBe(false);
    await expect(api.BrowserExtension.getTabs()).rejects.toThrow("BrowserExtension.getTabs isn't supported in Floe yet");
    await expect(api.BrowserExtension.getContent()).rejects.toThrow("isn't supported in Floe yet");
    await expect(api.WindowManagement.getActiveWindow()).rejects.toThrow("WindowManagement.getActiveWindow isn't supported in Floe yet");
    expect(api.WindowManagement.DesktopType.FullScreen).toBe("FullScreen");
  });

  test("the deprecated names still answer", () => {
    expect(api.unstable_AI).toBe(api.AI);
    expect(api.useUnstableAI()).toBeUndefined();
    expect(api.randomId()).not.toBe(api.randomId());
    expect(api.specialKeys.arrowUp).toBe("arrowUp");
    expect(Object.keys(api.specialKeys)).toHaveLength(16);
    expect(typeof api.useActionPanel().update).toBe("function");
  });
});

describe("environment", () => {
  test("reflects the running extension and command", () => {
    ctx.manifest = { name: "weather", author: "ada", owner: "team" };
    expect(api.environment.extensionName).toBe("weather");
    expect(api.environment.commandName).toBe("main");
    expect(api.environment.commandMode).toBe("view");
    expect(api.environment.supportPath).toBe(runtime.supportPath);
    expect(api.environment.assetsPath).toBe(path.join(ctx.extDir, "assets"));
    expect(api.environment.ownerOrAuthorName).toBe("team");
    expect(api.environment.launchType).toBe(api.LaunchType.UserInitiated);
  });

  test("falls back from owner to author to an empty name", () => {
    ctx.manifest = { name: "weather", author: "ada" };
    expect(api.environment.ownerOrAuthorName).toBe("ada");
    ctx.manifest = { name: "weather" };
    expect(api.environment.ownerOrAuthorName).toBe("");
  });
});

describe("constants", () => {
  test("Icon and Color turn any name into a tagged string", () => {
    expect(api.Icon.MagnifyingGlass).toBe("icon:MagnifyingGlass");
    expect(api.Icon.SomethingRaycastAddsLater).toBe("icon:SomethingRaycastAddsLater");
    expect(api.Color.Red).toBe("color:Red");
    expect(api.Color.SecondaryText).toBe("color:SecondaryText");
    expect((api.Icon as Record<symbol, unknown>)[Symbol.iterator]).toBeUndefined();
    expect(JSON.stringify({ icon: api.Icon.Star })).toBe('{"icon":"icon:Star"}');
  });

  test("the enums extensions compare against have Raycast's values", () => {
    expect(api.Image.Mask).toEqual({ Circle: "circle", RoundedRectangle: "roundedRectangle" });
    expect(api.Alert.ActionStyle.Destructive).toBe("destructive");
    expect(api.PopToRootType.Immediate).toBe("immediate");
    expect(api.LaunchType.Background).toBe("background");
    expect(api.OAuth.RedirectMethod.Web).toBe("web");
    expect(api.Keyboard.Shortcut.Common.Copy).toEqual({ modifiers: ["cmd", "shift"], key: "c" });
    expect(api.Keyboard.Shortcut.Common.Refresh).toEqual({ modifiers: ["cmd"], key: "r" });
  });
});

describe("OAuth while sign-in is parked", () => {
  const password = (name: string, title?: string) => ({ name, title, type: "password" });

  test("creating a client works, so an extension that also takes a token can load", async () => {
    const client = new api.OAuth.PKCEClient({ providerName: "Google" });
    expect(await client.getTokens()).toBeUndefined();
    expect(await client.removeTokens()).toBeUndefined();
    expect(sent("request")).toEqual([]);
  });

  test("GitHub's tokens are asked of the app, which may lend the GitHub CLI's sign-in", async () => {
    const client = new api.OAuth.PKCEClient({ providerName: "GitHub", providerId: "github" });
    const lent = client.getTokens();
    handleReply({ id: sent("request")[0].id, result: { accessToken: "gho_lent", scope: "repo", updatedAt: "2026-10-08T00:00:00.000Z" } });
    const tokens = await lent;
    expect(tokens?.accessToken).toBe("gho_lent");
    expect(tokens?.isExpired()).toBe(false);

    const declined = client.getTokens();
    handleReply({ id: sent("request")[1].id, result: null });
    expect(await declined).toBeUndefined();

    const removed = client.removeTokens();
    handleReply({ id: sent("request")[2].id, result: null });
    await removed;
    expect(sent("request").map((message) => [message.method, message.params.providerId])).toEqual([
      ["oauth.getTokens", "github"],
      ["oauth.getTokens", "github"],
      ["oauth.removeTokens", "github"],
    ]);
  });

  test("GitLab's tokens are asked of the app too, which may lend the GitLab CLI's sign-in", async () => {
    const client = new api.OAuth.PKCEClient({ providerName: "GitLab", providerId: "gitlab" });
    const lent = client.getTokens();
    handleReply({ id: sent("request")[0].id, result: { accessToken: "glpat-lent", updatedAt: "2026-10-08T00:00:00.000Z" } });
    expect((await lent)?.accessToken).toBe("glpat-lent");
    const removed = client.removeTokens();
    handleReply({ id: sent("request")[1].id, result: null });
    await removed;
    expect(sent("request").map((message) => [message.method, message.params.providerId])).toEqual([
      ["oauth.getTokens", "gitlab"],
      ["oauth.removeTokens", "gitlab"],
    ]);
  });

  test("only GitHub and GitLab are lent, by their id or their name", () => {
    expect(["github", "GitHub", " GITHUB ", "gitlab", "GitLab", " GITLAB "].map((name) => isLent(name))).toEqual([true, true, true, true, true, true]);
    const others = ["github-enterprise", "gitlab-self-hosted", "Google", "toString", "constructor", "", undefined];
    expect(others.map((name) => isLent(name))).toEqual(others.map(() => false));
  });

  test("starting a sign-in fails and names the token preference to use instead", async () => {
    ctx.manifest = { name: "github", preferences: [password("personalAccessToken", "Personal Access Token")] };
    const client = new api.OAuth.PKCEClient({ providerName: "GitHub" });
    const message = `Floe signs in to GitHub with the GitHub CLI. Install it, run "gh auth login", and allow it when Floe asks. Or add "Personal Access Token" in this extension's preferences.`;
    await expect(client.authorizationRequest({ endpoint: "https://example.com", clientId: "cid", scope: "repo" })).rejects.toThrow(message);
    await expect(client.authorize({ url: "https://example.com" })).rejects.toThrow(message);
    await expect(client.setTokens({ accessToken: "abc" })).rejects.toThrow(message);
    expect(sent("request")).toEqual([]);
  });

  test("the message names the tool of the provider that is lent", async () => {
    ctx.manifest = { name: "gitlab", preferences: [password("token", "API Token")] };
    const gitlab = new api.OAuth.PKCEClient({ providerName: "GitLab" });
    const message = `Floe signs in to GitLab with the GitLab CLI. Install it, run "glab auth login", and allow it when Floe asks. Or add "API Token" in this extension's preferences.`;
    await expect(gitlab.authorize({ url: "https://example.com" })).rejects.toThrow(message);
    await expect(gitlab.setTokens({ accessToken: "abc" })).rejects.toThrow(message);
    ctx.manifest = { name: "gitlab", preferences: [] };
    const bare = `Floe signs in to GitLab with the GitLab CLI. Install it, run "glab auth login", and allow it when Floe asks.`;
    await expect(gitlab.authorize({ url: "https://example.com" })).rejects.toThrow(new Error(bare));
    expect(sent("request")).toEqual([]);
  });

  test("the token preference is the secret one whose name says so, wherever it is declared", async () => {
    const client = new api.OAuth.PKCEClient();
    ctx.manifest = {
      name: "notes",
      preferences: [password("passphrase"), { name: "workspace", type: "textfield" }],
      commands: [{ name: "main", preferences: [password("apiKey")] }],
    };
    await expect(client.authorize({ url: "https://example.com" })).rejects.toThrow(`Floe can't sign in yet. Add "apiKey" in`);
    ctx.manifest = { name: "notes", preferences: [password("passphrase")] };
    await expect(client.authorize({ url: "https://example.com" })).rejects.toThrow(`Add "passphrase" in`);
    ctx.manifest = { name: "notes", preferences: [{ name: "apiToken", title: "API Token", type: "textfield" }] };
    await expect(client.authorize({ url: "https://example.com" })).rejects.toThrow(`Add "API Token" in`);
  });

  test("without a token preference the message says there is none", async () => {
    ctx.manifest = { name: "calendar", preferences: [{ name: "weekStart", type: "dropdown" }] };
    const client = new api.OAuth.PKCEClient({ providerName: "Google" });
    await expect(client.authorize({ url: "https://example.com" })).rejects.toThrow("Floe can't sign in to Google yet. This extension has no token preference to use instead.");
  });
});

describe("OAuth with sign-in on", () => {
  const clientOptions = { redirectMethod: api.OAuth.RedirectMethod.App, providerName: "GitHub", providerId: "github" };

  beforeEach(() => {
    process.env.FLOE_OAUTH = "1";
  });
  afterEach(() => {
    delete process.env.FLOE_OAUTH;
  });

  test("authorizationRequest redirects at floe://oauth with an S256 challenge", async () => {
    ctx.manifest = { name: "github" };
    const request = await new api.OAuth.PKCEClient(clientOptions).authorizationRequest({
      endpoint: "https://github.com/login/oauth/authorize",
      clientId: "cid",
      scope: "repo",
    });
    expect(request.redirectURI).toBe("floe://oauth?package_name=github");
    const url = new URL(request.toURL());
    expect(url.searchParams.get("code_challenge")).toBe(request.codeChallenge);
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.searchParams.get("state")).toBe(request.state);
  });

  test("authorize resolves the code from the app's callback", async () => {
    ctx.manifest = { name: "github" };
    const client = new api.OAuth.PKCEClient(clientOptions);
    const request = await client.authorizationRequest({ endpoint: "https://example.com/auth", clientId: "c", scope: "s" });
    const authorized = client.authorize(request);
    const [sentRequest] = sent("request");
    expect(sentRequest).toMatchObject({ method: "oauth.authorize", params: { providerName: "GitHub", state: request.state } });
    handleReply({ id: sentRequest.id, result: { url: `floe://oauth?package_name=github&code=abc&state=${request.state}` } });
    await expect(authorized).resolves.toEqual({ authorizationCode: "abc" });
  });

  test("getTokens answers undefined without stored tokens and a TokenSet with them", async () => {
    const client = new api.OAuth.PKCEClient(clientOptions);
    const missing = client.getTokens();
    handleReply({ id: sent("request")[0].id, result: null });
    await expect(missing).resolves.toBeUndefined();
    const stored = client.getTokens();
    handleReply({ id: sent("request")[1].id, result: { accessToken: "a", expiresIn: 3600, updatedAt: new Date().toISOString() } });
    const tokens = await stored;
    expect(tokens).toBeInstanceOf(api.OAuth.TokenSet);
    expect(tokens?.accessToken).toBe("a");
    expect(sent("request").map((message) => message.method)).toEqual(["oauth.getTokens", "oauth.getTokens"]);
  });

  test("setTokens and removeTokens forward to the app", async () => {
    const client = new api.OAuth.PKCEClient(clientOptions);
    const saved = client.setTokens({ accessToken: "a" });
    const removed = client.removeTokens();
    expect(sent("request").map((message) => message.method)).toEqual(["oauth.setTokens", "oauth.removeTokens"]);
    expect(sent("request")[0].params).toMatchObject({ providerId: "github" });
    for (const message of sent("request")) handleReply({ id: message.id, result: null });
    await saved;
    await removed;
  });
});

describe("deprecated aliases", () => {
  test("point at the current components", () => {
    expect(api.ActionPanelItem).toBe(api.Action);
    expect(api.ActionPanelSection).toBe(api.ActionPanel.Section);
    expect(api.ActionPanelSubmenu).toBe(api.ActionPanel.Submenu);
    expect(api.CopyToClipboardAction).toBe(api.Action.CopyToClipboard);
    expect(api.OpenInBrowserAction).toBe(api.Action.OpenInBrowser);
    expect(api.OpenAction).toBe(api.Action.Open);
    expect(api.OpenWithAction).toBe(api.Action.OpenWith);
    expect(api.PasteAction).toBe(api.Action.Paste);
    expect(api.PushAction).toBe(api.Action.Push);
    expect(api.ShowInFinderAction).toBe(api.Action.ShowInFinder);
    expect(api.SubmitFormAction).toBe(api.Action.SubmitForm);
    expect(api.TrashAction).toBe(api.Action.Trash);
    expect(api.ListItem).toBe(api.List.Item);
    expect(api.ListSection).toBe(api.List.Section);
    expect(api.FormTextField).toBe(api.Form.TextField);
    expect(api.FormTextArea).toBe(api.Form.TextArea);
    expect(api.FormCheckbox).toBe(api.Form.Checkbox);
    expect(api.FormDatePicker).toBe(api.Form.DatePicker);
    expect(api.FormDropdown).toBe(api.Form.Dropdown);
    expect(api.FormDropdownItem).toBe(api.Form.Dropdown.Item);
    expect(api.FormDropdownSection).toBe(api.Form.Dropdown.Section);
    expect(api.FormSeparator).toBe(api.Form.Separator);
    expect(api.FormTagPicker).toBe(api.Form.TagPicker);
    expect(api.FormTagPickerItem).toBe(api.Form.TagPicker.Item);
    expect(api.ImageMask).toBe(api.Image.Mask);
    expect(api.AlertActionStyle).toBe(api.Alert.ActionStyle);
    expect(api.ToastStyle).toBe(api.Toast.Style);
  });

  test("the old clipboard functions send the same messages", async () => {
    await api.copyTextToClipboard("old copy");
    await api.pasteText("old paste");
    await api.clearClipboard();
    expect(sent()).toEqual([
      { type: "copy", text: "old copy" },
      { type: "paste", text: "old paste" },
      { type: "copy", text: "" },
    ]);
  });

  test("the old storage functions read and write LocalStorage", async () => {
    await api.clearLocalStorage();
    await api.setLocalStorageItem("legacy", "value");
    expect(await api.getLocalStorageItem("legacy")).toBe("value");
    expect(await api.LocalStorage.getItem("legacy")).toBe("value");
    expect(await api.allLocalStorageItems()).toEqual({ legacy: "value" });
    await api.removeLocalStorageItem("legacy");
    expect(await api.allLocalStorageItems()).toEqual({});
  });
});
