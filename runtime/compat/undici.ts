//
//  undici.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Stands in for Bun's built-in undici, whose Agent and ProxyAgent forget what they were made with.
const builtin = require("undici");
const network = require("./network");

class Agent extends builtin.Agent {
  constructor(options?: { connect?: unknown }) {
    super(options);
    network.rememberDispatcher(this, { tls: network.pickTLS(options?.connect) });
  }
}

class ProxyAgent extends builtin.ProxyAgent {
  constructor(options: string | URL | { uri?: string | URL; requestTls?: unknown }) {
    super(options);
    const uri = typeof options === "string" || options instanceof URL ? options : options?.uri;
    network.rememberDispatcher(this, { proxy: network.addressOf(uri), tls: network.pickTLS(typeof options === "object" && !(options instanceof URL) ? options.requestTls : undefined) });
  }
}

module.exports = {
  ...builtin,
  Agent,
  ProxyAgent,
  fetch: network.withNodeOptions(builtin.fetch),
  setGlobalDispatcher: network.setGlobalDispatcher,
  getGlobalDispatcher: () => network.getGlobalDispatcher() ?? builtin.getGlobalDispatcher(),
};
