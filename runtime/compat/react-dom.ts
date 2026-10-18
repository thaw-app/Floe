//
//  react-dom.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// An extension's own react-dom reads the internals of the React it was built for, which is not the one Floe runs.
// Without a DOM, what extensions take from it (React Query's batching, mostly) only has to run the function.
const React = require("react");

module.exports = {
  version: React.version,
  unstable_batchedUpdates: (callback: (value?: unknown) => unknown, value?: unknown) => callback(value),
  flushSync: (callback?: () => unknown) => callback?.(),
  createPortal: () => {
    throw new Error("Floe has no DOM to portal into");
  },
};
