//
//  references.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import React, { useState } from "react";
import { Action, ActionPanel, Detail, List, useNavigation } from "../api/index";
import { referenceVersion, renderInFull, setReferences } from "../renderer";
import { find, findAll, fire, installRuntime, renders, settle, showScreen, type Message, type TreeNode } from "./support";

const h = React.createElement;
installRuntime("reference-tests");
beforeAll(() => setReferences(true));
afterAll(() => setReferences(false));

type Sent = TreeNode | { ref: number };
const isReference = (node: Sent): node is { ref: number } => "ref" in node;

// What the app does with a render: nodes of the last one are kept by id and put where a reference names them.
class App {
  private kept = new Map<number, TreeNode>();
  private sequence?: number;
  tree?: TreeNode;

  apply(message: Message) {
    if (message.base !== undefined && message.base !== this.sequence) throw new Error("a render refers to one the app does not hold");
    const next = new Map<number, TreeNode>();
    const keep = (node: TreeNode) => {
      next.set(node.id, node);
      (node.children ?? []).forEach(keep);
    };
    const build = (node: Sent): TreeNode => {
      if (!isReference(node)) {
        const built = node.type === "#text" ? node : { ...node, children: (node.children as Sent[]).map(build) };
        next.set(built.id, built);
        return built;
      }
      const held = this.kept.get(node.ref);
      if (!held) throw new Error(`nothing is kept for ${node.ref}`);
      keep(held);
      return held;
    };
    this.tree = build(message.tree as Sent);
    this.kept = next;
    this.sequence = message.sequence;
  }
}

function references(node: Sent, found: number[] = []): number[] {
  if (isReference(node)) found.push(node.ref);
  else (node.children as Sent[] | undefined)?.forEach((child) => references(child, found));
  return found;
}
const size = (message: Message) => JSON.stringify(message).length;

const planets = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"];
type Change = { loading?: boolean; renamed?: string; watched?: boolean; reversed?: boolean };
function Planets() {
  const [state, setState] = useState<Change>({});
  const names = state.reversed ? planets.toReversed() : planets;
  return h(
    List,
    { isLoading: state.loading ?? false, isShowingDetail: true, onChange: (change: Change) => setState((current) => ({ ...current, ...change })) },
    names.map((name) =>
      h(List.Item, {
        key: name,
        id: name,
        title: name === "Mars" ? (state.renamed ?? name) : name,
        actions: h(ActionPanel, null, h(Action, { title: `Visit ${name}`, onAction() {}, ...(name === "Venus" && state.watched ? { onWatch() {} } : {}) })),
        detail: h(List.Item.Detail, { markdown: `# ${name}\n\nA planet of the solar system, with a paragraph long enough to weigh something.` }),
      }),
    ),
  );
}

// Shows the list and hands back the app that followed along, with the list node to fire changes at.
async function showPlanets() {
  const tree = await showScreen(h(Planets));
  const app = new App();
  renders().forEach((message) => app.apply(message));
  return { app, list: find(tree, "List"), first: renders().length };
}
// The renders that followed a change, applied to the app as they came.
async function change(shown: Awaited<ReturnType<typeof showPlanets>>, change: Change): Promise<Message[]> {
  const before = renders().length;
  await fire(shown.list, "onChange", change);
  const sent = renders().slice(before);
  sent.forEach((message) => shown.app.apply(message));
  return sent;
}
// The whole tree as the runtime has it now, asked for the way the app asks.
async function full(): Promise<Message> {
  const before = renders().length;
  renderInFull();
  await settle(before);
  return renders().at(-1)!;
}

describe("references", () => {
  test("the first render is whole and refers to nothing", async () => {
    await showScreen(h(Planets));
    const message = renders().at(-1)!;
    expect(message.base).toBeUndefined();
    expect(references(message.tree as Sent)).toEqual([]);
    expect(findAll(message.tree!, "List.Item")).toHaveLength(planets.length);
  });

  test("a render that changes nothing the app is shown is not sent", async () => {
    const shown = await showPlanets();
    expect(await change(shown, { loading: false })).toEqual([]);
  });

  test("a change to the list alone sends its items by reference, in far fewer bytes", async () => {
    const shown = await showPlanets();
    const whole = size(renders().at(-1)!);
    const [message, ...rest] = await change(shown, { loading: true });
    expect(rest).toEqual([]);
    expect(message.references).toBe(referenceVersion);
    expect(message.base).toBe(message.sequence - 1);
    const items = findAll(shown.app.tree!, "List.Item").map((item) => item.id);
    expect(references(message.tree as Sent)).toEqual(items);
    expect(size(message)).toBeLessThan(whole / 5);
    expect(find(shown.app.tree!, "List").props.isLoading).toBe(true);
    expect(shown.app.tree).toEqual((await full()).tree!);
  });

  test("a changed item is sent whole, its untouched slots and the other items by reference", async () => {
    const shown = await showPlanets();
    const before = findAll(shown.app.tree!, "List.Item");
    const mars = before.find((item) => item.props.title === "Mars")!;
    const [message] = await change(shown, { renamed: "The red planet" });
    const sent = findAll(message.tree!, "List.Item");
    expect(sent.map((item) => item.props.title)).toEqual(["The red planet"]);
    expect(sent[0].id).toBe(mars.id);
    const others = before.filter((item) => item !== mars).map((item) => item.id);
    const slots = mars.children.map((child) => child.id);
    expect(references(message.tree as Sent).toSorted()).toEqual([...others, ...slots].toSorted());
    expect(shown.app.tree).toEqual((await full()).tree!);
  });

  test("a handler that appears is a change, though no prop differs", async () => {
    const shown = await showPlanets();
    const [message] = await change(shown, { watched: true });
    const actions = findAll(message.tree!, "Action");
    expect(actions.map((action) => action.handlers)).toEqual([["onAction", "onWatch"]]);
    expect(findAll(message.tree!, "List.Item").map((item) => item.props.title)).toEqual(["Venus"]);
    expect(shown.app.tree).toEqual((await full()).tree!);
  });

  test("items that only changed places are named in their new order", async () => {
    const shown = await showPlanets();
    const before = findAll(shown.app.tree!, "List.Item").map((item) => item.id);
    const [message] = await change(shown, { reversed: true });
    expect(references(message.tree as Sent)).toEqual(before.toReversed());
    expect(findAll(shown.app.tree!, "List.Item").map((item) => item.props.title)).toEqual(planets.toReversed());
  });

  test("a full render on request refers to nothing and the next one builds on it", async () => {
    const shown = await showPlanets();
    await change(shown, { loading: true });
    const message = await full();
    expect(message.base).toBeUndefined();
    expect(references(message.tree as Sent)).toEqual([]);
    expect(message.tree).toEqual(shown.app.tree!);
    shown.app.apply(message);
    const [next] = await change(shown, { loading: false });
    expect(next.base).toBe(message.sequence);
    expect(references(next.tree as Sent)).toHaveLength(planets.length);
  });

  test("with references off every render is whole", async () => {
    setReferences(false);
    try {
      const shown = await showPlanets();
      const [message] = await change(shown, { loading: true });
      expect(message.base).toBeUndefined();
      expect(references(message.tree as Sent)).toEqual([]);
      expect(findAll(message.tree!, "List.Item")).toHaveLength(planets.length);
    } finally {
      setReferences(true);
    }
  });
});

function Planet({ name }: { name: string }) {
  const { push, pop } = useNavigation();
  return h(Detail, { markdown: `# ${name}`, onDeeper: () => push(h(Planet, { name: `${name} moon` })), onBack: pop });
}

describe("references across navigation", () => {
  test("a pushed screen and the one a pop brings back are both sent whole", async () => {
    const tree = await showScreen(h(Planet, { name: "Saturn" }));
    const app = new App();
    renders().forEach((message) => app.apply(message));
    const follow = async (node: TreeNode, prop: string) => {
      const before = renders().length;
      await fire(node, prop);
      const sent = renders().slice(before);
      sent.forEach((message) => app.apply(message));
      return sent;
    };

    const pushed = await follow(find(tree, "Detail"), "onDeeper");
    expect(pushed.flatMap((message) => references(message.tree as Sent))).toEqual([]);
    expect(find(app.tree!, "Detail").props.markdown).toBe("# Saturn moon");

    const popped = await follow(find(app.tree!, "Detail"), "onBack");
    expect(popped.flatMap((message) => references(message.tree as Sent))).toEqual([], "the app dropped the lower screen when it was hidden");
    expect(find(app.tree!, "Detail").props.markdown).toBe("# Saturn");
    expect(find(app.tree!, "Detail").id).toBe(find(tree, "Detail").id);
  });
});
