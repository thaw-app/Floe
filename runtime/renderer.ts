//
//  renderer.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Custom React renderer: keeps a plain object tree and ships it to Swift as JSON after each commit that changed what is on show.
import React from "react";
import Reconciler from "react-reconciler";
import { ConcurrentRoot, DefaultEventPriority } from "react-reconciler/constants";
import { send, sendLine } from "./bridge";

type Sent = { sentRound?: number; sentHead?: string; sentChildren?: Child[] };
type Instance = Sent & {
  id: number;
  type: string;
  props: Record<string, unknown>;
  children: (Instance | TextInstance)[];
  parent?: Instance;
};
type TextInstance = Sent & { id: number; text: string; parent?: Instance };
type Child = Instance | TextInstance;
const noChildren: Child[] = [];

let nextId = 1;
const instances = new Map<number, Instance>();
const container: Instance = { id: 0, type: "root", props: {}, children: [] };

const visibleScreen = (root: Instance) => root.children.findLast((child) => child.type === "_screen");

// Set by a commit that changed something the app is shown. A commit that only touched screens under
// the top one leaves it alone, so nothing is serialized or sent for it.
let dirty = true;
function touch(node: Instance | undefined) {
  if (dirty) return;
  let top = node;
  while (top?.parent && top.parent !== container) top = top.parent;
  // Only a node known to sit in a hidden screen is skipped: the root's own children and detached nodes count.
  dirty = top?.parent !== container || top.type !== "_screen" || top === visibleScreen(container);
}

function remove(parent: Instance, child: Child) {
  touch(parent);
  const index = parent.children.indexOf(child);
  if (index >= 0) parent.children.splice(index, 1);
  child.parent = undefined;
}
function append(parent: Instance, child: Child) {
  remove(parent, child);
  parent.children.push(child);
  child.parent = parent;
}
function insertBefore(parent: Instance, child: Child, before: Child) {
  remove(parent, child);
  const index = parent.children.indexOf(before);
  if (index < 0) parent.children.push(child);
  else parent.children.splice(index, 0, child);
  child.parent = parent;
}
function forget(child: Child) {
  if ("text" in child) return;
  instances.delete(child.id);
  child.children.forEach(forget);
}

// Props can hold anything an extension passes: functions, elements, class instances, cycles.
function plain(value: unknown, seen: Set<object>, depth = 0): unknown {
  if (value === null || typeof value !== "object") return typeof value === "function" || typeof value === "symbol" ? undefined : value;
  if (value instanceof Date) return value.toISOString();
  if (React.isValidElement(value) || seen.has(value) || depth > 8) return undefined;
  seen.add(value);
  const result = Array.isArray(value)
    ? value.map((item) => plain(item, seen, depth + 1) ?? null)
    : Object.fromEntries(Object.entries(value).map(([key, item]) => [key, plain(item, seen, depth + 1)]));
  seen.delete(value);
  return result;
}

// Each node carries what the app holds for it: its own text and its children as they were last sent,
// and the render that sent them. Only the one before this is the app's, so a screen that was hidden is sent anew.
let round = 0;
let heldRound = -1;
let referenced = false;
let sequence = 0;

// The app says which references it reads; with any other answer every render is sent whole.
export const referenceVersion = 1;
let references = process.env.FLOE_RENDER_REFERENCES === String(referenceVersion);
export function setReferences(enabled: boolean) {
  references = enabled;
  heldRound = -1;
}

function head(node: Child): string {
  if ("text" in node) return JSON.stringify({ id: node.id, type: "#text", text: node.text });
  const props: Record<string, unknown> = {};
  const handlers: string[] = [];
  for (const [key, value] of Object.entries(node.props)) {
    if (key === "children" || key === "ref" || value === undefined) continue;
    if (typeof value === "function") handlers.push(key);
    else props[key] = typeof value === "object" ? plain(value, new Set()) : value;
  }
  return `${JSON.stringify({ id: node.id, type: node.type, props, handlers }).slice(0, -1)},"children":[`;
}

const sameChildren = (sent: Child[] | undefined, now: Child[]) =>
  sent !== undefined && sent.length === now.length && now.every((child, index) => child === sent[index]);

// The node's JSON, or nothing when the app already holds this very subtree: the parent then names it by id.
// Compared as text, so anything that would be sent differently counts as a change, a handler's name included.
function write(node: Child, children: Child[]): string | undefined {
  const own = head(node);
  let same = node.sentRound === heldRound && node.sentHead === own && sameChildren(node.sentChildren, children);
  const parts = children.map((child) => write(child, "text" in child ? noChildren : child.children));
  if (parts.some((part) => part !== undefined)) same = false;
  if (references) {
    node.sentRound = round;
    node.sentHead = own;
    if (!sameChildren(node.sentChildren, children)) node.sentChildren = [...children];
  }
  if (same) return undefined;
  if ("text" in node) return own;
  if (parts.includes(undefined)) referenced = true;
  return `${own}${parts.map((part, index) => part ?? `{"ref":${children[index].id}}`).join(",")}]}`;
}

// Navigation keeps lower screens mounted so Back can restore them, but Swift only shows the last one:
// hidden screen subtrees are skipped before serialization ever walks them. The live tree is not touched.
function flush() {
  const visible = visibleScreen(container);
  const shown = container.children.filter((child) => child === visible || child.type !== "_screen");
  round += 1;
  referenced = false;
  const tree = write(container, shown);
  heldRound = references ? round : -1;
  // Nothing the app is shown changed, so there is nothing to tell it.
  if (tree === undefined) return;
  sequence += 1;
  const base = referenced ? `"base":${sequence - 1},"references":${referenceVersion},` : "";
  sendLine(`{"type":"render","sequence":${sequence},${base}"tree":${tree}}`);
}

// The app could not place a reference, or missed a render: the next one is sent whole.
export function renderInFull() {
  heldRound = -1;
  dirty = true;
  scheduleFlush();
}

let flushScheduled = false;
function scheduleFlush() {
  if (!dirty || flushScheduled) return;
  flushScheduled = true;
  setTimeout(() => {
    flushScheduled = false;
    dirty = false;
    flush();
  }, 4);
}

let updatePriority = 0;

const reconciler = Reconciler({
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  isPrimaryRenderer: true,
  noTimeout: -1,
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,
  supportsMicrotasks: true,
  scheduleMicrotask: queueMicrotask,

  createInstance(type: string, props: Record<string, unknown>) {
    const instance: Instance = { id: nextId++, type, props, children: [] };
    instances.set(instance.id, instance);
    return instance;
  },
  createTextInstance: (text: string): TextInstance => ({ id: nextId++, text }),
  // Initial children are freshly created, never moves, so no removal scan is needed before pushing.
  appendInitialChild(parent, child) {
    parent.children.push(child);
    child.parent = parent;
  },
  appendChild: append,
  appendChildToContainer: append,
  insertBefore,
  insertInContainerBefore: insertBefore,
  removeChild(parent: Instance, child: Child) {
    remove(parent, child);
    forget(child);
  },
  removeChildFromContainer(parent: Instance, child: Child) {
    remove(parent, child);
    forget(child);
  },
  commitUpdate(instance: Instance, _type: string, _oldProps: unknown, newProps: Record<string, unknown>) {
    touch(instance);
    instance.props = newProps;
  },
  commitTextUpdate(instance: TextInstance, _oldText: string, newText: string) {
    touch(instance.parent);
    instance.text = newText;
  },
  clearContainer(root: Instance) {
    touch(root);
    root.children.forEach(forget);
    root.children = [];
  },
  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  getRootHostContext: () => ({}),
  getChildHostContext: (context: unknown) => context,
  getPublicInstance: (instance: unknown) => instance,
  prepareForCommit: () => null,
  resetAfterCommit: scheduleFlush,
  preparePortalMount() {},
  hideInstance() {},
  unhideInstance() {},
  hideTextInstance() {},
  unhideTextInstance() {},
  detachDeletedInstance() {},
  getInstanceFromNode: () => null,
  beforeActiveInstanceBlur() {},
  afterActiveInstanceBlur() {},
  prepareScopeUpdate() {},
  getInstanceFromScope: () => null,
  setCurrentUpdatePriority(priority: number) {
    updatePriority = priority;
  },
  getCurrentUpdatePriority: () => updatePriority,
  resolveUpdatePriority: () => updatePriority || DefaultEventPriority,
  maySuspendCommit: () => false,
  shouldAttemptEagerTransition: () => false,
  requestPostPaintCallback() {},
  NotPendingTransition: null,
  HostTransitionContext: React.createContext(null),
  resetFormInstance() {},
  trackSchedulerEvent() {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  preloadInstance: () => true,
  startSuspendingCommit() {},
  suspendInstance() {},
  waitForCommitToBeReady: () => null,
} as never);

// Extensions throw strings and plain objects as well as Errors.
export function toError(error: unknown): Error {
  if (error instanceof Error) return error;
  return new Error(typeof error === "string" ? error : JSON.stringify(error));
}

// Fatal errors replace the view with an error screen; the rest show as a failure toast.
export function reportError(error: unknown, fatal = false) {
  const err = toError(error);
  console.error(err.stack ?? err.message);
  send({ type: "error", message: err.message, stack: err.stack, fatal });
}

export function render(element: React.ReactElement) {
  // A new root reports itself even when it renders nothing, as a menu bar command returning null does.
  dirty = true;
  const root = reconciler.createContainer(
    container,
    ConcurrentRoot,
    null,
    false,
    null,
    "",
    (error: unknown) => reportError(error, true),
    (error: unknown) => reportError(error),
    (error: unknown) => reportError(error),
    null,
  );
  reconciler.updateContainer(element, root, null, null);
}

// The Swift side tags dates as { $date: iso } since JSON has no date type.
function revive(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(revive);
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    if (typeof record.$date === "string") return new Date(record.$date);
    return Object.fromEntries(Object.entries(record).map(([key, item]) => [key, revive(item)]));
  }
  return value;
}

export function dispatchEvent(id: number, prop: string, args: unknown[]) {
  const handler = instances.get(id)?.props[prop];
  if (typeof handler !== "function") return;
  try {
    const result = handler(...args.map(revive));
    if (result instanceof Promise) result.catch(reportError);
  } catch (error) {
    reportError(error);
  }
}
