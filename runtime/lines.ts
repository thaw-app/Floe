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
