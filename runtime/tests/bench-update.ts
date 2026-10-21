//
//  bench-update.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Standalone benchmark: a list of N rows, then one row changed many times, by its own state and by the list's.

import React, { useState } from "react";
import { setSink } from "../bridge";
import { dispatchEvent, render, renderStats, setReferences } from "../renderer";

const count = Number(process.argv[2] ?? 1000);
const rounds = 100;
const h = React.createElement;
let lines: string[] = [];
setSink((line) => lines.push(line));
setReferences(true);

function Row({ name, title }: { name: string; title: string }) {
  const [count, setCount] = useState(0);
  return h("Item", { id: name, title, subtitle: `bumped ${count}`, accessories: [{ text: name }], onBump: () => setCount((value) => value + 1) });
}
function Rows() {
  const [renamed, setRenamed] = useState(0);
  return h(
    "List",
    { onRename: () => setRenamed((value) => value + 1) },
    Array.from({ length: count }, (_, index) => h(Row, { key: index, name: `row-${index}`, title: index === 7 ? `renamed ${renamed}` : `row-${index}` })),
  );
}

const nextLine = async () => {
  const before = lines.length;
  while (lines.length === before) await Bun.sleep(0);
};
const median = (values: number[]) => values.toSorted((a, b) => a - b)[Math.floor(values.length / 2)];

render(h(Rows));
await nextLine();
type Sent = { id: number; type: string; children: Sent[] };
const sentList = (JSON.parse(lines[0]).tree as Sent).children[0];
const list = sentList.id;
const row = sentList.children[7].id;
// Per change: the median time from the change to its line, and the mean flush time and head() calls.
async function time(id: number, prop: string) {
  const elapsed: number[] = [];
  const { heads, flushTime } = renderStats;
  for (let round = 0; round < rounds; round += 1) {
    const started = performance.now();
    dispatchEvent(id, prop, []);
    await nextLine();
    elapsed.push(performance.now() - started);
  }
  const flush = (renderStats.flushTime - flushTime) / rounds;
  return `${median(elapsed).toFixed(2)}ms, flush ${flush.toFixed(3)}ms, ${(renderStats.heads - heads) / rounds} heads`;
}
console.log(`rows=${count}  one row's own state: ${await time(row, "onBump")}  the list's state: ${await time(list, "onRename")}`);
process.exit(0);
