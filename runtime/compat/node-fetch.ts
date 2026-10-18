//
//  node-fetch.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Stands in for Bun's built-in node-fetch, in its shape: the module is the fetch function.
const builtin = require("node-fetch");
const { withNodeOptions } = require("./network");

const fetch = withNodeOptions(builtin);
fetch.default = fetch;
fetch.fetch = fetch;
module.exports = fetch;
