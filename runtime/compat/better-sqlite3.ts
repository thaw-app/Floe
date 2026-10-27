//
//  better-sqlite3.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// better-sqlite3 is a V8 addon, which Bun cannot load; bun:sqlite has nearly its API. This is the difference, in
// better-sqlite3's shape: the module is the Database class. Drizzle's better-sqlite3 driver runs on it.
const { Database: BunDatabase, SQLiteError } = require("bun:sqlite");

type BunStatement = {
  run(...params: unknown[]): { changes: number; lastInsertRowid: number | bigint };
  get(...params: unknown[]): unknown;
  all(...params: unknown[]): unknown[];
  values(...params: unknown[]): unknown[][];
  columnNames: string[];
};

class Statement {
  private returnsRaw = false;
  private returnsFirstColumn = false;

  constructor(
    private readonly inner: BunStatement,
    readonly source: string,
  ) {}

  get reader() {
    return this.inner.columnNames.length > 0;
  }

  raw(on = true) {
    this.returnsRaw = on;
    return this;
  }

  pluck(on = true) {
    this.returnsFirstColumn = on;
    return this;
  }

  run(...params: unknown[]) {
    return this.inner.run(...params);
  }

  get(...params: unknown[]) {
    if (this.returnsRaw || this.returnsFirstColumn) return this.all(...params)[0];
    // bun:sqlite says null for no row, better-sqlite3 undefined.
    return this.inner.get(...params) ?? undefined;
  }

  all(...params: unknown[]) {
    if (this.returnsFirstColumn) return this.inner.values(...params).map((row) => row[0]);
    return this.returnsRaw ? this.inner.values(...params) : this.inner.all(...params);
  }

  iterate(...params: unknown[]) {
    return this.all(...params)[Symbol.iterator]();
  }

  columns() {
    return this.inner.columnNames.map((name) => ({ name, column: name, table: null, database: null, type: null }));
  }
}

// The multiple-ciphers build encrypts with these pragmas, with or without a schema before the name. The SQLite under
// Bun has no cipher, and ignoring the key would write in the clear what the user asked to have encrypted.
const encryption = /\bPRAGMA\s+(?:["'`[]?\w+["'`\]]?\s*\.\s*)?["'`[]?(?:cipher\w*|key|rekey|hexkey|hexrekey)\b/i;

function refuseEncryption(source: string) {
  if (encryption.test(source)) {
    throw new Error("Floe can't open encrypted databases: the SQLite it runs extensions with has no encryption");
  }
}

class Database {
  private readonly inner: InstanceType<typeof BunDatabase>;

  constructor(
    readonly name = ":memory:",
    options: { readonly?: boolean; fileMustExist?: boolean } = {},
  ) {
    // strict: named parameters are bound from keys without their @, : or $, as better-sqlite3 binds them.
    this.inner = new BunDatabase(name, { strict: true, readonly: options.readonly, create: !options.fileMustExist && !options.readonly });
  }

  get inTransaction() {
    return this.inner.inTransaction;
  }

  prepare(source: string) {
    refuseEncryption(source);
    return new Statement(this.inner.prepare(source), source);
  }

  exec(source: string) {
    refuseEncryption(source);
    this.inner.exec(source);
    return this;
  }

  transaction<F extends (...args: never[]) => unknown>(fn: F) {
    return this.inner.transaction(fn);
  }

  pragma(source: string, options?: { simple?: boolean }) {
    refuseEncryption(`PRAGMA ${source}`);
    const rows = this.inner.prepare(`PRAGMA ${source}`).all() as Record<string, unknown>[];
    return options?.simple ? Object.values(rows[0] ?? {})[0] : rows;
  }

  close() {
    this.inner.close();
    return this;
  }
}

module.exports = Object.assign(Database, { default: Database, Database, SqliteError: SQLiteError });
