//
//  lines.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, test } from "bun:test";
import { lineSplitter } from "../lines";

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
