//
//  bench-navigation.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Standalone memory and wire-size workload for navigation snapshots: a hidden root list of 10,000
// rows with actions, a small detail pushed on top, more stacked details, a hidden root update and a
// return to the root. Transitions run through the real navigation handlers and every stage waits for
// the render that actually reflects it, bounded by a deadline instead of fixed sleeps. Only the
// latest render is retained; parsed trees are released after their scalars are extracted, so memory
// samples are not contaminated by harness history. Without --baseline the run also asserts the
// visible-screen contract: one transmitted root screen, no hidden rows under a detail, equal payloads
// at equal stack depths, no render for the hidden root update, and full restored root content after pop. React intentionally keeps the
// hidden components mounted, so Bun's retained heap is expected, not a leak this workload can show.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import React, { useEffect, useState } from "react";
import { NavigationRoot, useNavigation } from "../api/index";
import { ctx, setSink } from "../bridge";
import { dispatchEvent, render } from "../renderer";

const baseline = process.argv.includes("--baseline");
const rowCount = 10_000;
const stackedDetails = 2;
const deadline = Date.now() + 60_000;

const h = React.createElement;
const support = fs.mkdtempSync(path.join(os.tmpdir(), "floe-bench-navigation-"));
ctx.dataPath = support;
ctx.manifest = { name: "bench-navigation" };

type Capture = { sequence: number; line: string };
let latest: Capture = { sequence: 0, line: "" };
setSink((line) => {
    if (line.includes('"type":"error"')) console.error("[nav] host error:", line.trim());
    if (!line.includes('"type":"render"')) return;
    latest = { sequence: latest.sequence + 1, line };
});

type Tree = { id: number; type: string; props: Record<string, unknown>; children: Tree[] };

function countNodes(node: Tree): number {
    return 1 + node.children.reduce((total, child) => total + countNodes(child), 0);
}

function listRows(node: Tree): number {
    return node.children.reduce((total, child) => total + listRows(child), node.type === "row" ? 1 : 0);
}

function screensOf(node: Tree): Tree[] {
    return node.children.filter((child) => child.type === "_screen");
}

function findByTitle(node: Tree, prefix: string): Tree | undefined {
    if (node.type === "row" && String(node.props.title ?? "").startsWith(prefix)) return node;
    for (const child of node.children) {
        const found = findByTitle(child, prefix);
        if (found) return found;
    }
    return undefined;
}

function findByType(node: Tree, type: string): Tree | undefined {
    if (node.type === type) return node;
    for (const child of node.children) {
        const found = findByType(child, type);
        if (found) return found;
    }
    return undefined;
}

/// The last match in serialization order is the topmost screen of its kind.
function findTopmost(node: Tree, type: string): Tree | undefined {
    let found: Tree | undefined;
    if (node.type === type) found = node;
    for (const child of node.children) {
        const deeper = findTopmost(child, type);
        if (deeper) found = deeper;
    }
    return found;
}

function report(stage: string, capture: Capture) {
    const bytes = Buffer.byteLength(capture.line, "utf8");
    const tree = JSON.parse(capture.line).tree as Tree;
    const memory = process.memoryUsage();
    const stage_ = { bytes, nodes: countNodes(tree), rows: listRows(tree), screens: screensOf(tree).length };
    console.log(
        `[nav] stage=${stage} bytes=${stage_.bytes} nodes=${stage_.nodes} rootScreens=${stage_.screens} rows=${stage_.rows} ` +
            `heapUsed=${mebi(memory.heapUsed)}MiB external=${mebi(memory.external)}MiB ` +
            `arrayBuffers=${mebi(memory.arrayBuffers)}MiB rss=${mebi(memory.rss)}MiB`,
    );
    return stage_;
}

const mebi = (bytes: number) => (bytes / 1024 / 1024).toFixed(1);

async function nextRender(stage: string, matches?: (tree: Tree) => boolean): Promise<Capture> {
    const seen = latest.sequence;
    while (Date.now() < deadline) {
        if (latest.sequence > seen) {
            const tree = JSON.parse(latest.line).tree as Tree;
            if (!matches || matches(tree)) return latest;
        }
        await Bun.sleep(1);
    }
    console.error(`[nav] timed out waiting for a render at stage=${stage}`);
    process.exit(1);
}

const refreshCommitted = Promise.withResolvers<void>();

function HiddenRoot() {
    const [refreshed, setRefreshed] = useState(0);
    const { push } = useNavigation();
    // A refresh under a detail sends no render, so its commit is seen through this effect instead.
    useEffect(() => {
        if (refreshed > 0) refreshCommitted.resolve();
    }, [refreshed]);
    return h(
        "list",
        null,
        Array.from({ length: rowCount }, (_, index) =>
            h("row", {
                key: index,
                title: `Row ${index} r${refreshed}`,
                ...(index === 0 ? { onOpen: () => push(h(Detail, { depth: 1 })) } : {}),
                ...(index === 1 ? { onRefresh: () => setRefreshed((current) => current + 1) } : {}),
            }),
        ),
    );
}

function Detail({ depth }: { depth: number }) {
    const { push, pop } = useNavigation();
    return h("detail", {
        markdown: `# Detail ${depth}`,
        onPush: depth <= stackedDetails ? () => push(h(Detail, { depth: depth + 1 })) : undefined,
        onBack: pop,
    });
}

render(h(NavigationRoot, null, h(HiddenRoot)));
let capture = await nextRender("root list", (tree) => listRows(tree) === rowCount);
const rootStage = report("root-list", capture);
const rootTree = JSON.parse(capture.line).tree as Tree;
const openRow = findByTitle(rootTree, "Row 0")!;
const refreshRow = findByTitle(rootTree, "Row 1")!;

dispatchEvent(openRow.id, "onOpen", []);
capture = await nextRender("pushed detail", (tree) => findByType(tree, "detail") !== undefined);
const detailStage = report("detail-1", capture);
let detailNode = findTopmost(JSON.parse(capture.line).tree as Tree, "detail")!;

const stacked: { bytes: number; nodes: number }[] = [];
for (let depth = 2; depth <= stackedDetails + 1; depth++) {
    dispatchEvent(detailNode.id, "onPush", []);
    capture = await nextRender(`detail-${depth}`, (tree) => findTopmost(tree, "detail")?.props.markdown === `# Detail ${depth}`);
    stacked.push(report(`detail-${depth}`, capture));
    detailNode = findTopmost(JSON.parse(capture.line).tree as Tree, "detail")!;
}

dispatchEvent(refreshRow.id, "onRefresh", []);
const beforeRefresh = latest.sequence;
await refreshCommitted.promise;
// Longer than the renderer's 4 ms flush, so a render the refresh did schedule would have arrived.
await Bun.sleep(50);
const hiddenRefreshRenders = latest.sequence - beforeRefresh;
console.log(`[nav] stage=hidden-root-refresh renders=${hiddenRefreshRenders}`);

// Pop back down the stack one detail at a time, then to the root.
for (let depth = stackedDetails; depth >= 1; depth--) {
    dispatchEvent(detailNode.id, "onBack", []);
    capture = await nextRender(`restored detail ${depth}`, (tree) => findTopmost(tree, "detail")?.props.markdown === `# Detail ${depth}`);
    report(`restored-detail-${depth}`, capture);
    detailNode = findTopmost(JSON.parse(capture.line).tree as Tree, "detail")!;
}

dispatchEvent(detailNode.id, "onBack", []);
capture = await nextRender("restored root", (tree) => listRows(tree) === rowCount);
const restoredStage = report("restored-root", capture);

if (!baseline) {
    if (hiddenRefreshRenders !== 0) throw new Error(`a hidden root refresh sent ${hiddenRefreshRenders} render(s)`);
    for (const stage of [rootStage, detailStage, ...stacked, restoredStage]) {
        if (stage.screens !== 1) throw new Error(`expected exactly one transmitted root screen, got ${stage.screens}`);
    }
    for (const stage of [detailStage, ...stacked]) {
        if (stage.rows !== 0) throw new Error(`hidden rows leaked into the payload under a detail: ${stage.rows}`);
    }
    const nodes = stacked.map((stage) => stage.nodes);
    if (new Set(nodes).size !== 1) throw new Error(`stack depth changed the payload's node count: ${nodes.join(", ")}`);
    const byteCounts = stacked.map((stage) => stage.bytes);
    if (Math.max(...byteCounts) - Math.min(...byteCounts) > 64) throw new Error(`stack depth changed the payload size: ${byteCounts.join(", ")}`);
    if (restoredStage.rows !== rowCount) throw new Error(`the restored root lost rows: ${restoredStage.rows}`);
    if (!(restoredStage.bytes > detailStage.bytes)) throw new Error("the restored root is not bigger than the detail");
    if (!latest.line.includes("Row 0 r1")) throw new Error("the hidden root's update did not survive the pop");
}
setSink();
fs.rmSync(support, { recursive: true, force: true });
console.log(`[nav] done baseline=${baseline} bun=${Bun.version} rows=${rowCount} stacked=${stackedDetails}`);
