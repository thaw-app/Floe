//
//  support.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Shared by the unit tests: captures bridge messages, points ctx at a temp folder and renders into the one root.
import { afterAll, beforeAll, beforeEach } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import React, { useState } from "react";
import { ctx, setSink } from "../bridge";
import { dispatchEvent, render } from "../renderer";
import { NavigationRoot } from "../api/index";

export type TreeNode = {
  id: number;
  type: string;
  text?: string;
  props: Record<string, any>;
  handlers: string[];
  children: TreeNode[];
};
export type Message = { type: string; tree?: TreeNode; [key: string]: any };

const h = React.createElement;
const received: Message[] = [];

export function makeTempDir(label: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), `floe-${label}-`));
}

// Registers the hooks every test file needs. Returns the temp folder standing in for the support path.
export function installRuntime(extensionName: string): { readonly supportPath: string } {
  const runtime = { supportPath: "" };
  beforeAll(() => {
    runtime.supportPath = makeTempDir("support");
    ctx.extDir = path.join(runtime.supportPath, "extension");
    ctx.commandName = "main";
    ctx.commandMode = "view";
    ctx.supportPath = runtime.supportPath;
    ctx.manifest = { name: extensionName };
    setSink((line) => received.push(JSON.parse(line)));
  });
  beforeEach(() => {
    received.length = 0;
  });
  afterAll(() => {
    setSink();
    fs.rmSync(runtime.supportPath, { recursive: true, force: true });
  });
  return runtime;
}

// Everything sent over the bridge since the test began, renders left out.
export function sent(type?: string): Message[] {
  return received.filter((message) => message.type !== "render" && (type === undefined || message.type === type));
}

// The render messages as they were sent, references and all.
export function renders(): Message[] {
  return received.filter((message) => message.type === "render");
}

export function renderCount(): number {
  return received.filter((message) => message.type === "render").length;
}

// Long enough for React to commit and the renderer to flush its debounced message, with room to spare.
const quietPeriod = 30;

// How long an awaited render may take on a machine busy with other work.
const renderLimit = 5000;

// Waits until the host has gone quiet, then returns the last tree it rendered.
// Quiet before the awaited render is not settled: the render is still on its way. Without `after`, the first one is awaited.
export async function settle(after = 0): Promise<TreeNode> {
  const started = Date.now();
  let count = -1;
  while (count !== received.length || (renderCount() <= after && Date.now() - started < renderLimit)) {
    count = received.length;
    await Bun.sleep(quietPeriod);
  }
  const tree = received.findLast((message) => message.type === "render")?.tree;
  if (!tree) throw new Error("nothing has been rendered");
  return tree;
}

// The renderer has a single container, so the tests share one root and swap what it shows.
let setStageContent: ((content: React.ReactNode) => void) | undefined;
let shown = 0;
function Stage() {
  const [content, setContent] = useState<React.ReactNode>(null);
  setStageContent = setContent;
  return content;
}

// A root that hit a fatal error is gone; the next show() starts a new one.
export function resetStage() {
  setStageContent = undefined;
}

export async function show(element: React.ReactNode): Promise<TreeNode> {
  if (!setStageContent) {
    render(h(Stage));
    await settle();
  }
  // A fresh key each time, so no state leaks from the previous test's components.
  setStageContent?.(h(React.Fragment, { key: shown++ }, element));
  return settle();
}

export function showScreen(element: React.ReactNode): Promise<TreeNode> {
  return show(h(NavigationRoot, null, element));
}

// Calls a handler the way the Swift app does, then returns the tree that follows.
export function fire(node: TreeNode, prop: string, ...args: unknown[]): Promise<TreeNode> {
  dispatchEvent(node.id, prop, args);
  return settle();
}

// The same, for a handler that is expected to render: it waits for that render however long a busy machine takes.
export function fireForRender(node: TreeNode, prop: string, ...args: unknown[]): Promise<TreeNode> {
  const before = renderCount();
  dispatchEvent(node.id, prop, args);
  return settle(before);
}

export function findAll(node: TreeNode, type: string, found: TreeNode[] = []): TreeNode[] {
  if (node.type === type) found.push(node);
  for (const child of node.children ?? []) findAll(child, type, found);
  return found;
}

export function find(node: TreeNode, type: string): TreeNode {
  const [first] = findAll(node, type);
  if (!first) throw new Error(`no ${type} in the tree`);
  return first;
}

export function slot(node: TreeNode, name: string): TreeNode {
  const match = node.children.find((child) => child.type === "_slot" && child.props.name === name);
  if (!match) throw new Error(`no ${name} slot on ${node.type}`);
  return match;
}

export function text(node: TreeNode): string {
  return node.type === "#text" ? (node.text ?? "") : node.children.map(text).join("");
}
