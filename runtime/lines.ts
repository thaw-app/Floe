//
//  lines.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { StringDecoder } from "node:string_decoder";

// Turns the chunks a pipe delivers into whole lines. A chunk may end in the middle of a character that takes
// several bytes: the decoder holds those bytes until the rest arrives, where decoding each chunk by itself
// would put a replacement character on each side of the cut.
export function lineSplitter(onLine: (line: string) => void): (chunk: Buffer) => void {
  const decoder = new StringDecoder("utf8");
  let buffered = "";
  return (chunk) => {
    buffered += decoder.write(chunk);
    let newline: number;
    while ((newline = buffered.indexOf("\n")) >= 0) {
      const line = buffered.slice(0, newline);
      buffered = buffered.slice(newline + 1);
      onLine(line);
    }
  };
}

// Control characters, line and paragraph separators and the marks that reverse text direction. In text a
// manifest or an extension wrote, they could start a line of their own or move a terminal's cursor. A backslash
// is in the set too, so text that spells out an escape can't pass for one of these.
const unprintable = /[\\\p{Cc}\u2028\u2029\u202a-\u202e\u2066-\u2069]/gu;

// Text for one line of output, with each of those written as an escape and a backslash doubled.
export function oneLine(text: string): string {
  return text.replace(unprintable, (character) =>
    character === "\\" ? "\\\\" : `\\u${character.codePointAt(0)!.toString(16).padStart(4, "0")}`,
  );
}
