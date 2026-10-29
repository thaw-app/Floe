//
//  lines.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, test } from "bun:test";
import { lineSplitter, oneLine } from "../lines";

function linesFrom(chunks: Buffer[]): string[] {
  const lines: string[] = [];
  const feed = lineSplitter((line) => lines.push(line));
  chunks.forEach(feed);
  return lines;
}

describe("lines from a pipe", () => {
  test("a character cut in two by a chunk boundary arrives whole", () => {
    const whole = Buffer.from('{"title":"café ☕ 日本語 👍🏽"}\n', "utf8");
    for (let cut = 1; cut < whole.length; cut++) {
      expect(linesFrom([whole.subarray(0, cut), whole.subarray(cut)])).toEqual(['{"title":"café ☕ 日本語 👍🏽"}']);
    }
  });

  test("a byte at a time is the same as all at once", () => {
    const whole = Buffer.from("één\ntwee 🎉\n", "utf8");
    expect(linesFrom([...whole].map((byte) => Buffer.from([byte])))).toEqual(["één", "twee 🎉"]);
  });

  test("several lines in one chunk, and a line over several chunks", () => {
    expect(linesFrom([Buffer.from("one\ntwo\nthr"), Buffer.from("ee\n")])).toEqual(["one", "two", "three"]);
  });

  test("what has no newline yet is held, not handed on", () => {
    expect(linesFrom([Buffer.from("no end")])).toEqual([]);
    expect(linesFrom([Buffer.from("\n\n")])).toEqual(["", ""]);
  });
});

describe("text for one line of output", () => {
  test("control characters are written as escapes, so a name cannot start a line or move the cursor", () => {
    expect(oneLine("cmd\nok         fake/entry")).toBe("cmd\\u000aok         fake/entry");
    expect(oneLine("a\rb\u001b[2Kc\u0007\u007f\u0085")).toBe("a\\u000db\\u001b[2Kc\\u0007\\u007f\\u0085");
    expect(oneLine("x\u2028y\u202ez")).toBe("x\\u2028y\\u202ez");
  });

  test("ordinary text is left as it is", () => {
    expect(oneLine("café ☕ 👍🏽 tab-less")).toBe("café ☕ 👍🏽 tab-less");
  });
});
