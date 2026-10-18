//
//  ws.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Stands in for Bun's built-in ws, which reads certificate settings only from a tls option of its own.
const builtin = require("ws");
const { pickTLS } = require("./network");

class WebSocket extends builtin {
  constructor(url: string | URL, protocols?: unknown, options?: Record<string, unknown>) {
    if (typeof protocols === "object" && protocols !== null && !Array.isArray(protocols)) {
      options = protocols as Record<string, unknown>;
      protocols = undefined;
    }
    const tls = pickTLS(options);
    super(url, protocols, tls && !options?.tls ? { ...options, tls } : options);
  }
}

Object.assign(WebSocket, builtin, { WebSocket });
module.exports = WebSocket;
