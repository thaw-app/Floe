//
//  folders.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import fs from "node:fs";
import path from "node:path";

// What Floe keeps in an extension's data folder. Anything else there was written by the extension.
const floeNames = [/^build$/, /^cache$/, /^support$/, /^preferences\.json$/, /^dropdown-values\.json$/, /^local-storage/, /^custom-icon-/, /^cache-/];

/// The extension's support folder sits inside Floe's data folder for it, so an extension that lists, sweeps or
/// expects an empty supportPath meets only its own files. Data from before the split is sorted once.
export function prepareFolders(dataPath: string): string {
  const supportPath = path.join(dataPath, "support");
  if (fs.existsSync(supportPath)) return supportPath;
  fs.mkdirSync(supportPath, { recursive: true });
  for (const name of fs.readdirSync(dataPath)) {
    const cache = /^cache-(.+\.json)$/.exec(name);
    // A second process of the same extension may be sorting the same folder.
    try {
      if (cache) {
        fs.mkdirSync(path.join(dataPath, "cache"), { recursive: true });
        fs.renameSync(path.join(dataPath, name), path.join(dataPath, "cache", cache[1]));
      } else if (!floeNames.some((pattern) => pattern.test(name))) {
        fs.renameSync(path.join(dataPath, name), path.join(supportPath, name));
      }
    } catch {}
  }
  return supportPath;
}
