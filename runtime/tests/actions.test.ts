//
//  actions.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, describe, expect, mock, spyOn, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import React from "react";
import { handlePop, handleReply } from "../bridge";
import { Action, ActionPanel, Detail, Icon } from "../api/index";
import { find, findAll, fire, installRuntime, makeTempDir, renderCount, sent, settle, showScreen, type TreeNode } from "./support";

const h = React.createElement;
installRuntime("actions-tests");

// Shows one action in a panel and returns its node.
async function showAction(element: React.ReactNode): Promise<TreeNode> {
  return find(await showScreen(h(Detail, { markdown: "host", actions: h(ActionPanel, null, element) })), "Action");
}

afterEach(() => {
  mock.restore();
});

describe("built-in actions", () => {
  test("have a default title and icon that props can replace", async () => {
    const plain = await showAction(h(Action.CopyToClipboard, { content: "x" }));
    expect(plain.props).toEqual({ title: "Copy to Clipboard", icon: "icon:Clipboard" });
    expect(plain.handlers).toEqual(["onAction"]);

    const custom = await showAction(
      h(Action.CopyToClipboard, { content: "x", title: "Copy Name", icon: Icon.Person, shortcut: { modifiers: ["cmd"], key: "." }, style: Action.Style.Regular }),
    );
    expect(custom.props).toEqual({ title: "Copy Name", icon: "icon:Person", shortcut: { modifiers: ["cmd"], key: "." }, style: "regular" });
  });

  test("OpenInBrowser opens the URL, tells the extension, and closes the window", async () => {
    const opened: string[] = [];
    const action = await showAction(h(Action.OpenInBrowser, { url: "https://example.com", onOpen: (url: string) => opened.push(url) }));
    expect(action.props.title).toBe("Open in Browser");
    await fire(action, "onAction");
    expect(sent()).toEqual([{ type: "open", target: "https://example.com" }, { type: "close" }]);
    expect(opened).toEqual(["https://example.com"]);
  });

  test("Open passes the target and the chosen application", async () => {
    const opened: string[] = [];
    const action = await showAction(
      h(Action.Open, { target: "/tmp/notes.txt", application: { name: "TextEdit", path: "/Applications/TextEdit.app" }, onOpen: (target: string) => opened.push(target) }),
    );
    await fire(action, "onAction");
    expect(sent()).toEqual([{ type: "open", target: "/tmp/notes.txt", application: "/Applications/TextEdit.app" }, { type: "close" }]);
    expect(opened).toEqual(["/tmp/notes.txt"]);
  });

  test("OpenWith asks for the file's apps when it opens, and opens the file in the one chosen", async () => {
    const opened: string[] = [];
    const openWith = h(Action.OpenWith, { path: "/tmp/notes.txt", onOpen: (target: string) => opened.push(target) });
    const submenu = find(await showScreen(h(Detail, { markdown: "host", actions: h(ActionPanel, null, openWith) })), "ActionPanel.Submenu");
    expect(submenu.props).toMatchObject({ title: "Open With", icon: "icon:Finder" });
    expect(findAll(submenu, "Action")).toEqual([]);

    await fire(submenu, "onOpen");
    const [request] = sent("request");
    expect(request).toMatchObject({ method: "environment.getApplications", params: { path: "/tmp/notes.txt" } });
    const before = renderCount();
    handleReply({ id: request.id, result: [{ name: "TextEdit", path: "/Applications/TextEdit.app" }, { name: "Xcode", path: "/Applications/Xcode.app" }] });
    const apps = findAll(find(await settle(before), "ActionPanel.Submenu"), "Action");
    expect(apps.map((app) => app.props.title)).toEqual(["TextEdit", "Xcode"]);
    expect(apps[1].props.icon).toEqual({ fileIcon: "/Applications/Xcode.app" });

    await fire(apps[1], "onAction");
    expect(sent().filter((message) => message.type !== "request")).toEqual([
      { type: "open", target: "/tmp/notes.txt", application: "/Applications/Xcode.app" },
      { type: "close" },
    ]);
    expect(opened).toEqual(["/tmp/notes.txt"]);
  });

  test("ToggleQuickLook asks the app to preview the selected item's file", async () => {
    const action = await showAction(h(Action.ToggleQuickLook));
    expect(action.props.title).toBe("Quick Look");
    await fire(action, "onAction");
    expect(sent()).toEqual([{ type: "toggleQuickLook" }]);
  });

  test("CopyToClipboard copies, tells the extension, and confirms with a HUD", async () => {
    const copied: unknown[] = [];
    const action = await showAction(h(Action.CopyToClipboard, { content: 42, onCopy: (content: unknown) => copied.push(content) }));
    await fire(action, "onAction");
    expect(sent()).toEqual([
      { type: "copy", text: "42" },
      { type: "hud", title: "Copied to Clipboard" },
    ]);
    expect(copied).toEqual([42]);
  });

  // A password manager's copy says it is one, and the app is told, so no clipboard history keeps it.
  test("a concealed copy tells the app it is one", async () => {
    await fire(await showAction(h(Action.CopyToClipboard, { content: "hunter2", concealed: true })), "onAction");
    expect(sent("copy")).toEqual([{ type: "copy", text: "hunter2", concealed: true }]);
  });

  test("Paste sends the text to paste and tells the extension", async () => {
    const pasted: unknown[] = [];
    const action = await showAction(h(Action.Paste, { content: "snippet", onPaste: (content: unknown) => pasted.push(content) }));
    expect(action.props.title).toBe("Paste");
    await fire(action, "onAction");
    expect(sent()).toEqual([{ type: "paste", text: "snippet" }]);
    expect(pasted).toEqual(["snippet"]);
  });

  test("Push shows the target as a new screen and runs onPop when it leaves", async () => {
    const events: string[] = [];
    const action = await showAction(
      h(Action.Push, { title: "Details", target: h(Detail, { markdown: "pushed" }), onPush: () => events.push("push"), onPop: () => events.push("pop") }),
    );
    expect(action.props).toEqual({ title: "Details", icon: "icon:ArrowRight" });

    const pushed = await fire(action, "onAction");
    expect(pushed.children).toHaveLength(1);
    expect(find(pushed, "Detail").props.markdown).toBe("pushed");
    expect(events).toEqual(["push"]);

    handlePop();
    expect((await settle()).children).toHaveLength(1);
    expect(events).toEqual(["push", "pop"]);
  });

  test("ShowInFinder reveals the path and closes the window", async () => {
    const spawn = spyOn(Bun, "spawn").mockImplementation((() => ({})) as never);
    const shown: string[] = [];
    const action = await showAction(h(Action.ShowInFinder, { path: "/tmp/report.pdf", onShow: (file: string) => shown.push(file) }));
    await fire(action, "onAction");
    expect(spawn.mock.calls).toEqual([[["open", "-R", "/tmp/report.pdf"]]] as never);
    expect(shown).toEqual(["/tmp/report.pdf"]);
    expect(sent()).toEqual([{ type: "close" }]);
  });

  test("Trash moves the files into the user's Trash folder", async () => {
    // HOME points at a temp folder for this test, so the real Trash is never touched.
    const home = makeTempDir("home");
    const realHome = process.env.HOME;
    process.env.HOME = home;
    try {
      fs.mkdirSync(path.join(home, ".Trash"));
      const first = path.join(home, "a", "note.txt");
      const second = path.join(home, "b", "note.txt");
      for (const file of [first, second]) {
        fs.mkdirSync(path.dirname(file));
        fs.writeFileSync(file, path.dirname(file));
      }
      const trashed: unknown[] = [];
      const action = await showAction(h(Action.Trash, { paths: [first, second], onTrash: (paths: unknown) => trashed.push(paths) }));
      expect(action.props).toEqual({ title: "Move to Trash", icon: "icon:Trash" });
      await fire(action, "onAction");

      expect(fs.existsSync(first)).toBe(false);
      expect(fs.existsSync(second)).toBe(false);
      // The second file has the same name, so it gets a suffix instead of replacing the first.
      const inTrash = fs.readdirSync(path.join(home, ".Trash")).sort((left, right) => left.length - right.length);
      expect(inTrash[0]).toBe("note.txt");
      expect(inTrash[1]).toMatch(/^note\.txt \d+$/);
      expect(trashed).toEqual([[first, second]]);
    } finally {
      process.env.HOME = realHome;
      fs.rmSync(home, { recursive: true, force: true });
    }
  });

  // The submit action of the form a built-in action pushed.
  function submitOf(screen: TreeNode): TreeNode {
    return findAll(screen, "Action").find((action) => action.props.isSubmit) as TreeNode;
  }

  test("CreateSnippet asks with a filled-in form and keeps the snippet once the user confirms", async () => {
    const action = await showAction(h(Action.CreateSnippet, { snippet: { name: "Greeting", text: "Hello" } }));
    expect(action.props).toEqual({ title: "Create Snippet", icon: "icon:Document" });
    const form = await fire(action, "onAction");
    expect(findAll(form, "Form.TextField").map((field) => [field.props.id, field.props.defaultValue])).toEqual([
      ["name", "Greeting"],
      ["keyword", ""],
    ]);
    expect(find(form, "Form.TextArea").props.defaultValue).toBe("Hello");

    await fire(submitOf(form), "onSubmit", { name: "Greeting", text: "Hello", keyword: "hi" });
    const [request] = sent("request");
    expect(request).toMatchObject({ method: "snippet.create", params: { name: "Greeting", text: "Hello", keyword: "hi" } });
    handleReply({ id: request.id, result: null });
    const back = await settle();
    expect(sent("toast")).toEqual([expect.objectContaining({ style: "success", title: "Snippet saved" })]);
    expect(find(back, "Detail").props.markdown).toBe("host");
  });

  test("CreateQuicklink stays on its form and says why when Floe refuses the link", async () => {
    const action = await showAction(h(Action.CreateQuicklink, { quicklink: { name: "Search", link: "https://example.com?q={argument}" } }));
    const form = await fire(action, "onAction");
    expect(findAll(form, "Form.TextField").map((field) => field.props.defaultValue)).toEqual(["Search", "https://example.com?q={argument}", ""]);

    await fire(submitOf(form), "onSubmit", { name: "Search", link: "https://example.com?q={argument}", keyword: "" });
    const [request] = sent("request");
    expect(request.method).toBe("quicklink.create");
    handleReply({ id: request.id, error: "Enter a keyword." });
    const still = await settle();
    expect(sent("toast")).toEqual([expect.objectContaining({ style: "failure", title: "Enter a keyword." })]);
    expect(find(still, "Form").props.navigationTitle).toBe("Create Quicklink");
  });

  test("PickDate hands the picked date to onChange and goes back", async () => {
    const picked: unknown[] = [];
    const action = await showAction(h(Action.PickDate, { title: "Set Due Date", type: Action.PickDate.Type.Date, onChange: (date: unknown) => picked.push(date) }));
    const form = await fire(action, "onAction");
    expect(find(form, "Form.DatePicker").props).toMatchObject({ id: "date", type: "date" });

    const back = await fire(submitOf(form), "onSubmit", { date: { $date: "2026-10-20T00:00:00.000Z" } });
    expect(picked).toEqual([new Date("2026-10-20T00:00:00.000Z")]);
    expect(find(back, "Detail").props.markdown).toBe("host");
  });

  test("a plain Action runs the extension's own handler", async () => {
    const runs: string[] = [];
    const tree = await showScreen(
      h(Detail, { markdown: "", actions: h(ActionPanel, null, h(Action, { title: "First", onAction: () => runs.push("first") }), h(Action, { title: "Second", onAction: () => runs.push("second") })) }),
    );
    await fire(findAll(tree, "Action")[1], "onAction");
    expect(runs).toEqual(["second"]);
    expect(Action.PickDate.Type).toEqual({ Date: "date", DateTime: "dateTime" });
  });

  // The name Action had before, which extensions are still written with.
  test("ActionPanel.Item is a plain Action", async () => {
    const runs: string[] = [];
    const action = await showAction(h(ActionPanel.Item, { title: "Open Tab", onAction: () => runs.push("opened") }));
    expect(action.props).toEqual({ title: "Open Tab" });
    await fire(action, "onAction");
    expect(runs).toEqual(["opened"]);
  });
});
