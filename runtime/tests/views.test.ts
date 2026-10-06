//
//  views.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import React, { useState } from "react";
import { handlePop, handlePopToRoot } from "../bridge";
import { Action, ActionPanel, Color, Detail, Form, Grid, Icon, List, MenuBarExtra, showToast, useNavigation } from "../api/index";
import { find, findAll, fire, fireForRender, installRuntime, renderCount, sent, settle, show, showScreen, slot, type TreeNode } from "./support";

const h = React.createElement;
const runtime = installRuntime("views-tests");

const types = (nodes: TreeNode[]) => nodes.map((node) => node.type);
const titles = (nodes: TreeNode[]) => nodes.map((node) => node.props.title);

describe("List", () => {
  test("renders sections and items with their props", async () => {
    const tree = await showScreen(
      h(
        List,
        { isLoading: true, searchBarPlaceholder: "Search planets", onSearchTextChange: () => {} },
        h(List.Section, { title: "Inner" }, h(List.Item, { title: "Mercury", subtitle: "Rocky", icon: Icon.Star })),
        h(List.Item, { title: "Pluto", accessories: [{ text: "dwarf", date: new Date(0) }] }),
      ),
    );
    const list = find(tree, "List");
    expect(list.props).toEqual({ isLoading: true, searchBarPlaceholder: "Search planets" });
    expect(list.handlers).toEqual(["onSearchTextChange"]);
    expect(types(list.children)).toEqual(["List.Section", "List.Item"]);
    expect(find(list, "List.Section").props.title).toBe("Inner");
    const [mercury, pluto] = findAll(list, "List.Item");
    expect(mercury.props).toEqual({ title: "Mercury", subtitle: "Rocky", icon: "icon:Star" });
    expect(pluto.props.accessories).toEqual([{ text: "dwarf", date: "1970-01-01T00:00:00.000Z" }]);
  });

  test("moves element-valued props into named slots", async () => {
    const tree = await showScreen(
      h(
        List,
        { actions: h(ActionPanel, null, h(Action, { title: "Reload", onAction: () => {} })) },
        h(List.Item, {
          title: "Earth",
          actions: h(ActionPanel, null, h(Action, { title: "Visit", onAction: () => {} })),
          detail: h(List.Item.Detail, {
            markdown: "# Earth",
            metadata: h(List.Item.Detail.Metadata, null, h(List.Item.Detail.Metadata.Label, { title: "Moons", text: "1" })),
          }),
        }),
        h(List.EmptyView, { title: "Nothing here", actions: h(ActionPanel, null, h(Action, { title: "Create" })) }),
      ),
    );
    const list = find(tree, "List");
    expect(list.props).toEqual({});
    expect(titles(findAll(slot(list, "actions"), "Action"))).toEqual(["Reload"]);

    const item = find(list, "List.Item");
    expect(item.props).toEqual({ title: "Earth" });
    expect(titles(findAll(slot(item, "actions"), "Action"))).toEqual(["Visit"]);
    const detail = find(slot(item, "detail"), "List.Item.Detail");
    expect(detail.props).toEqual({ markdown: "# Earth" });
    expect(find(slot(detail, "metadata"), "Metadata.Label").props).toEqual({ title: "Moons", text: "1" });

    const empty = find(list, "EmptyView");
    expect(empty.props).toEqual({ title: "Nothing here" });
    expect(titles(findAll(slot(empty, "actions"), "Action"))).toEqual(["Create"]);
  });

  test("leaves out the slot when the prop is not set", async () => {
    const tree = await showScreen(h(List, null, h(List.Item, { title: "Mars", actions: undefined })));
    expect(findAll(tree, "_slot")).toEqual([]);
  });
});

describe("Detail", () => {
  test("renders markdown with metadata and actions", async () => {
    const tree = await showScreen(
      h(Detail, {
        markdown: "# Venus",
        navigationTitle: "Venus",
        actions: h(ActionPanel, null, h(Action, { title: "Back" })),
        metadata: h(
          Detail.Metadata,
          null,
          h(Detail.Metadata.Label, { title: "Type", text: "Rocky", icon: { source: Icon.Circle, tintColor: Color.Orange } }),
          h(Detail.Metadata.Link, { title: "More", target: "https://example.com", text: "Wiki" }),
          h(Detail.Metadata.Separator),
          h(Detail.Metadata.TagList, { title: "Tags" }, h(Detail.Metadata.TagList.Item, { text: "hot", color: Color.Red })),
        ),
      }),
    );
    const detail = find(tree, "Detail");
    expect(detail.props).toEqual({ markdown: "# Venus", navigationTitle: "Venus" });
    const metadata = find(slot(detail, "metadata"), "Detail.Metadata");
    expect(types(metadata.children)).toEqual(["Metadata.Label", "Metadata.Link", "Metadata.Separator", "Metadata.TagList"]);
    expect(metadata.children[0].props.icon).toEqual({ source: "icon:Circle", tintColor: "color:Orange" });
    expect(find(metadata, "Metadata.TagList.Item").props).toEqual({ text: "hot", color: "color:Red" });
    expect(titles(findAll(slot(detail, "actions"), "Action"))).toEqual(["Back"]);
  });
});

describe("Form", () => {
  test("renders each field type with its handlers", async () => {
    const tree = await showScreen(
      h(
        Form,
        { actions: h(ActionPanel, null, h(Action.SubmitForm, { title: "Send", onSubmit: () => {} })) },
        h(Form.Description, { title: "About", text: "Tell us" }),
        h(Form.TextField, { id: "name", title: "Name", onChange: () => {} }),
        h(Form.PasswordField, { id: "secret" }),
        h(Form.TextArea, { id: "notes" }),
        h(Form.Checkbox, { id: "agree", label: "Agree" }),
        h(Form.DatePicker, { id: "due", type: Form.DatePicker.Type.Date, defaultValue: new Date(86_400_000) }),
        h(Form.Dropdown, { id: "tone" }, h(Form.Dropdown.Section, { title: "Tones" }, h(Form.Dropdown.Item, { value: "calm", title: "Calm" }))),
        h(Form.TagPicker, { id: "tags" }, h(Form.TagPicker.Item, { value: "a", title: "A" })),
        h(Form.FilePicker, { id: "files" }),
        h(Form.Separator),
        h(Form.LinkAccessory, { target: "https://example.com", text: "Help" }),
      ),
    );
    const form = find(tree, "Form");
    expect(types(form.children)).toEqual([
      "_slot",
      "Form.Description",
      "Form.TextField",
      "Form.PasswordField",
      "Form.TextArea",
      "Form.Checkbox",
      "Form.DatePicker",
      "Form.Dropdown",
      "Form.TagPicker",
      "Form.FilePicker",
      "Form.Separator",
      "Form.LinkAccessory",
    ]);
    expect(find(form, "Form.TextField").handlers).toEqual(["onChange"]);
    expect(find(form, "Form.DatePicker").props).toEqual({ id: "due", type: "date", defaultValue: "1970-01-02T00:00:00.000Z" });
    expect(find(find(form, "Form.Dropdown"), "Dropdown.Item").props).toEqual({ value: "calm", title: "Calm" });
    expect(find(form, "Form.TagPicker.Item").props.value).toBe("a");
  });

  test("the submit action hands the form values to onSubmit, dates revived", async () => {
    const submitted: Record<string, unknown>[] = [];
    const tree = await showScreen(
      h(Form, { actions: h(ActionPanel, null, h(Action.SubmitForm, { onSubmit: (values: Record<string, unknown>) => submitted.push(values) })) }),
    );
    const submit = find(tree, "Action");
    expect(submit.props).toEqual({ title: "Submit", isSubmit: true });
    expect(submit.handlers).toEqual(["onSubmit"]);
    await fire(submit, "onSubmit", { name: "Ada", due: { $date: "2026-01-02T00:00:00.000Z" } });
    expect(submitted).toEqual([{ name: "Ada", due: new Date("2026-01-02T00:00:00.000Z") }]);
  });
});

describe("Grid and MenuBarExtra", () => {
  test("Grid renders sections, items and its layout constants", async () => {
    const tree = await showScreen(
      h(
        Grid,
        { columns: 4, inset: Grid.Inset.Large, fit: Grid.Fit.Contain, itemSize: Grid.ItemSize.Small },
        h(Grid.Section, { title: "Icons" }, h(Grid.Item, { title: "Star", content: Icon.Star, actions: h(ActionPanel, null, h(Action, { title: "Pick" })) })),
        h(Grid.EmptyView, { title: "No icons" }),
      ),
    );
    const grid = find(tree, "Grid");
    expect(grid.props).toEqual({ columns: 4, inset: "large", fit: "contain", itemSize: "small" });
    const item = find(find(grid, "Grid.Section"), "Grid.Item");
    expect(item.props).toEqual({ title: "Star", content: "icon:Star" });
    expect(titles(findAll(slot(item, "actions"), "Action"))).toEqual(["Pick"]);
    expect(find(grid, "EmptyView").props.title).toBe("No icons");
  });

  test("MenuBarExtra renders its menu structure", async () => {
    const tree = await showScreen(
      h(
        MenuBarExtra,
        { title: "Floe" },
        h(MenuBarExtra.Section, { title: "Recent" }, h(MenuBarExtra.Item, { title: "One", onAction: () => {} })),
        h(MenuBarExtra.Separator),
        h(MenuBarExtra.Submenu, { title: "More" }, h(MenuBarExtra.Item, { title: "Two" })),
      ),
    );
    const menu = find(tree, "MenuBarExtra");
    expect(types(menu.children)).toEqual(["MenuBarExtra.Section", "MenuBarExtra.Separator", "MenuBarExtra.Submenu"]);
    expect(titles(findAll(menu, "MenuBarExtra.Item"))).toEqual(["One", "Two"]);
  });
});

describe("ActionPanel", () => {
  test("keeps sections and submenus nested, with titles, shortcuts and styles", async () => {
    const tree = await showScreen(
      h(Detail, {
        markdown: "",
        actions: h(
          ActionPanel,
          { title: "Planet" },
          h(Action, { title: "Top", shortcut: { modifiers: ["cmd"], key: "t" }, onAction: () => {} }),
          h(ActionPanel.Section, { title: "Danger" }, h(Action, { title: "Delete", style: Action.Style.Destructive, onAction: () => {} })),
          h(ActionPanel.Submenu, { title: "Share", icon: Icon.Link }, h(Action, { title: "Mail" }), h(Action, { title: "Message" })),
        ),
      }),
    );
    const panel = find(tree, "ActionPanel");
    expect(panel.props).toEqual({ title: "Planet" });
    expect(types(panel.children)).toEqual(["Action", "ActionPanel.Section", "ActionPanel.Submenu"]);
    expect(panel.children[0].props).toEqual({ title: "Top", shortcut: { modifiers: ["cmd"], key: "t" } });
    expect(panel.children[0].handlers).toEqual(["onAction"]);
    expect(find(panel.children[1], "Action").props).toEqual({ title: "Delete", style: "destructive" });
    expect(panel.children[2].props).toEqual({ title: "Share", icon: "icon:Link" });
    expect(titles(findAll(panel.children[2], "Action"))).toEqual(["Mail", "Message"]);
  });
});

function dropdownOf(tree: TreeNode, type: string): TreeNode {
  return find(slot(find(tree, type.split(".")[0]), "searchBarAccessory"), type);
}
const planetItems = [
  h(List.Dropdown.Section, { key: "inner", title: "Inner" }, h(List.Dropdown.Item, { value: "mercury", title: "Mercury" })),
  h(List.Dropdown.Item, { key: "venus", value: "venus", title: "Venus" }),
];

describe("search bar dropdown", () => {
  test("calls onChange on mount with the first item, even inside a section", async () => {
    const changes: string[] = [];
    const tree = await showScreen(
      h(List, { searchBarAccessory: h(List.Dropdown, { tooltip: "Planet", onChange: (value: string) => changes.push(value) }, ...planetItems) }),
    );
    expect(changes).toEqual(["mercury"]);
    const dropdown = dropdownOf(tree, "List.Dropdown");
    expect(dropdown.props).toEqual({ tooltip: "Planet", value: "mercury" });
    expect(titles(findAll(dropdown, "Dropdown.Item"))).toEqual(["Mercury", "Venus"]);
  });

  test("starts from defaultValue, and a controlled value wins over both", async () => {
    const changes: string[] = [];
    const onChange = (value: string) => changes.push(value);
    const uncontrolled = await showScreen(h(List, { searchBarAccessory: h(List.Dropdown, { defaultValue: "venus", onChange }, ...planetItems) }));
    expect(dropdownOf(uncontrolled, "List.Dropdown").props.value).toBe("venus");
    const controlled = await showScreen(
      h(List, { searchBarAccessory: h(List.Dropdown, { value: "earth", defaultValue: "venus", onChange }, ...planetItems) }),
    );
    expect(dropdownOf(controlled, "List.Dropdown").props.value).toBe("earth");
    expect(changes).toEqual(["venus", "earth"]);
  });

  test("does not call onChange on mount when there is nothing to select", async () => {
    const changes: string[] = [];
    await showScreen(h(List, { searchBarAccessory: h(List.Dropdown, { onChange: (value: string) => changes.push(value) }, "not an item") }));
    expect(changes).toEqual([]);
  });

  test("a selection updates the value and reaches onChange", async () => {
    const changes: string[] = [];
    const tree = await showScreen(h(Grid, { searchBarAccessory: h(Grid.Dropdown, { onChange: (value: string) => changes.push(value) }, ...planetItems) }));
    const after = await fire(dropdownOf(tree, "Grid.Dropdown"), "onChange", "venus");
    expect(dropdownOf(after, "Grid.Dropdown").props.value).toBe("venus");
    expect(changes).toEqual(["mercury", "venus"]);
    expect(fs.existsSync(path.join(runtime.supportPath, "dropdown-values.json"))).toBe(false);
  });

  test("storeValue remembers the selection per command and dropdown id", async () => {
    const element = () => h(List, { searchBarAccessory: h(List.Dropdown, { id: "planet", storeValue: true }, ...planetItems) });
    const tree = await showScreen(element());
    await fire(dropdownOf(tree, "List.Dropdown"), "onChange", "venus");
    expect(JSON.parse(fs.readFileSync(path.join(runtime.supportPath, "dropdown-values.json"), "utf8"))).toEqual({ "main:planet": "venus" });

    const reopened = await showScreen(element());
    expect(dropdownOf(reopened, "List.Dropdown").props.value).toBe("venus");

    const other = await showScreen(h(List, { searchBarAccessory: h(List.Dropdown, { id: "other", storeValue: true }, ...planetItems) }));
    expect(dropdownOf(other, "List.Dropdown").props.value).toBe("mercury");
  });
});

function PlanetDetail({ name }: { name: string }) {
  const { push, pop } = useNavigation();
  const [visits, setVisits] = useState(0);
  return h(Detail, {
    markdown: `# ${name} (${visits})`,
    onVisit: () => setVisits((current) => current + 1),
    onDeeper: () => push(h(PlanetDetail, { name: `${name} moon` })),
    onBack: pop,
  });
}
// Each render transmits only the visible screen, so a navigation tree holds exactly one screen.
const markdowns = (tree: TreeNode) => tree.children.map((screen) => find(screen, "Detail").props.markdown);
const screens = (tree: TreeNode) => tree.children;

describe("navigation", () => {
  test("each pushed view becomes the one transmitted screen", async () => {
    const tree = await showScreen(h(PlanetDetail, { name: "Saturn" }));
    expect(types(screens(tree))).toEqual(["_screen"]);
    const rootScreen = screens(tree)[0];
    const pushed = await fire(find(tree, "Detail"), "onDeeper");
    expect(types(screens(pushed))).toEqual(["_screen"], "the stack depth does not add transmitted screens");
    expect(markdowns(pushed)).toEqual(["# Saturn moon (0)"]);
    expect(screens(pushed)[0].id).not.toBe(rootScreen.id, "a pushed screen is a new node");
  });

  test("a lower screen keeps its id and state across a push and a pop", async () => {
    const tree = await showScreen(h(PlanetDetail, { name: "Saturn" }));
    const rootScreen = screens(tree)[0];
    const root = find(tree, "Detail");
    await fire(root, "onVisit");
    const pushed = await fire(root, "onDeeper");
    const popped = await fire(find(pushed, "Detail"), "onBack");
    expect(markdowns(popped)).toEqual(["# Saturn (1)"], "the visits state survived the push");
    expect(screens(popped)[0].id).toBe(rootScreen.id, "the restored screen keeps its node id");
    expect(find(popped, "Detail").id).toBe(root.id);
  });

  test("the app's pop message pops one screen, runs onPop, and exits at the root", async () => {
    const popped: string[] = [];
    function Root() {
      const { push } = useNavigation();
      return h(Detail, { markdown: "root", onOpen: () => push(h(Detail, { markdown: "child" }), () => popped.push("child")) });
    }
    const tree = await showScreen(h(Root));
    await fire(find(tree, "Detail"), "onOpen");

    handlePop();
    expect(markdowns(await settle())).toEqual(["root"]);
    expect(popped).toEqual(["child"]);
    expect(sent("exit")).toEqual([]);

    handlePop();
    await settle();
    expect(sent("exit")).toEqual([{ type: "exit" }]);
  });

  test("pop to root drops every pushed screen at once", async () => {
    const tree = await showScreen(h(PlanetDetail, { name: "Jupiter" }));
    const second = await fire(find(tree, "Detail"), "onDeeper");
    const third = await fire(find(second, "Detail"), "onDeeper");
    expect(screens(third)).toHaveLength(1, "the stack depth does not change the transmitted screens");

    handlePopToRoot();
    expect(markdowns(await settle())).toEqual(["# Jupiter (0)"]);
  });

  test("useNavigation outside a navigation root does nothing", async () => {
    const tree = await show(h(PlanetDetail, { name: "Stray" }));
    const after = await fire(find(tree, "Detail"), "onDeeper");
    await fire(find(after, "Detail"), "onBack");
    expect(findAll(after, "Detail")).toHaveLength(1);
  });
});

// A root that refreshes itself, as a timer or a finished fetch does, under the list it pushed.
function Refreshing({ rows }: { rows: number }) {
  const { push } = useNavigation();
  const [refreshes, setRefreshes] = useState(0);
  return h(Detail, {
    markdown: `refreshed ${refreshes}`,
    onRefresh: () => setRefreshes((current) => current + 1),
    onToast: () => showToast({ title: "from below" }),
    onOpen: () => push(h(Rows, { rows })),
  });
}
function Rows({ rows }: { rows: number }) {
  const { pop } = useNavigation();
  const [state, setState] = useState({ isLoading: false, navigationTitle: "Rows", searchText: "", selectedItemId: "0" });
  return h(
    List,
    { ...state, onChange: (change: object) => setState((current) => ({ ...current, ...change })), onBack: pop },
    Array.from({ length: rows }, (_, index) => h(List.Item, { key: index, id: String(index), title: `Row ${index}` })),
  );
}

describe("renders sent across a navigation stack", () => {
  // The renders one event causes, and the tree the app is left with.
  async function counted(node: TreeNode, prop: string, ...args: unknown[]): Promise<[number, TreeNode]> {
    const before = renderCount();
    const after = await fire(node, prop, ...args);
    return [renderCount() - before, after];
  }

  // For an event that renders: waits for the render, then counts, so a slow machine cannot read as none.
  async function rendered(node: TreeNode, prop: string, ...args: unknown[]): Promise<[number, TreeNode]> {
    const before = renderCount();
    const after = await fireForRender(node, prop, ...args);
    return [renderCount() - before, after];
  }

  test("twenty updates under a list of 1,000 rows send nothing, and Back shows the last of them", async () => {
    const tree = await showScreen(h(Refreshing, { rows: 1000 }));
    const root = find(tree, "Detail");
    const [pushes, pushed] = await rendered(root, "onOpen");
    expect(pushes).toBe(1);
    expect(findAll(pushed, "List.Item")).toHaveLength(1000);

    const before = renderCount();
    for (let update = 0; update < 20; update++) await fire(root, "onRefresh");
    expect(renderCount() - before).toBe(0);

    handlePop();
    const popped = await settle();
    expect(renderCount() - before).toBe(1);
    expect(markdowns(popped)).toEqual(["refreshed 20"]);
    expect(find(popped, "Detail").id).toBe(root.id);
  });

  test("each push and each pop sends one render", async () => {
    const tree = await showScreen(h(PlanetDetail, { name: "Mars" }));
    const [first, second] = await rendered(find(tree, "Detail"), "onDeeper");
    const [next, third] = await rendered(find(second, "Detail"), "onDeeper");
    const [back] = await rendered(find(third, "Detail"), "onBack");
    expect([first, next, back]).toEqual([1, 1, 1]);

    const before = renderCount();
    handlePop();
    expect(markdowns(await settle())).toEqual(["# Mars (0)"]);
    expect(renderCount() - before).toBe(1);
  });

  test("pop to root sends one render for the whole stack", async () => {
    const tree = await showScreen(h(PlanetDetail, { name: "Mars" }));
    const second = await fire(find(tree, "Detail"), "onDeeper");
    await fire(find(second, "Detail"), "onDeeper");
    const before = renderCount();
    handlePopToRoot();
    expect(markdowns(await settle())).toEqual(["# Mars (0)"]);
    expect(renderCount() - before).toBe(1);
  });

  test("what the top screen's view carries still reaches the app: loading, title, search text, selection", async () => {
    const tree = await showScreen(h(Refreshing, { rows: 3 }));
    const pushed = await fire(find(tree, "Detail"), "onOpen");
    const list = find(pushed, "List");
    const changes = [{ isLoading: true }, { navigationTitle: "Three rows" }, { searchText: "row" }, { selectedItemId: "2" }];
    for (const change of changes) {
      const [renders, after] = await rendered(list, "onChange", change);
      expect(renders).toBe(1);
      expect(find(after, "List").props).toMatchObject(change);
    }
  });

  test("a toast from a hidden screen is sent, with no render", async () => {
    const tree = await showScreen(h(Refreshing, { rows: 3 }));
    const root = find(tree, "Detail");
    await fire(root, "onOpen");
    const [renders] = await counted(root, "onToast");
    expect(renders).toBe(0);
    expect(sent("toast")).toEqual([expect.objectContaining({ title: "from below", hidden: false })]);
  });
});
