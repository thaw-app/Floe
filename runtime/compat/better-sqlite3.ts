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
const encryptionPragma = /^(?:cipher\w*|key|rekey|hexkey|hexrekey)$/i;

/// What closes each quote SQLite reads: strings, quoted names, and names in brackets.
const closers = new Map([["'", "'"], ['"', '"'], ["`", "`"], ["[", "]"]]);
/// A bare word as SQLite reads one: letters, digits, _ and $, and any character past ASCII, as in schéma.
const word = /[\w$\u0080-\u{10FFFF}]+/uy;

type Token = { text: string; quoted: boolean };

/// Past the end of the quoted token that opens at `at`. A doubled quote, as in "my "" vault", is part of the text.
function quotedEnd(source: string, at: number, close: string) {
  let end = source.indexOf(close, at + 1);
  while (end !== -1 && close !== "]" && source[end + 1] === close) {
    end = source.indexOf(close, end + 2);
  }
  return end === -1 ? source.length : end + 1;
}

/// Past the end of the comment that opens at `at`: the line's end for --, after the */ for /*.
function commentEnd(source: string, at: number) {
  const line = source.startsWith("--", at);
  const end = source.indexOf(line ? "\n" : "*/", at + 2);
  if (end === -1) return source.length;
  return line ? end : end + 2;
}

/// The SQL in tokens as SQLite reads it. Comments are dropped, so PRAGMA/**/key cannot hide, and quoted text is one
/// token, so a value that reads "PRAGMA key" is no pragma and a "--" in it starts no comment.
function tokens(source: string) {
  const found: Token[] = [];
  let at = 0;
  while (at < source.length) {
    const close = closers.get(source[at]);
    if (close) {
      const end = quotedEnd(source, at, close);
      found.push({ text: source.slice(at + 1, end - 1), quoted: true });
      at = end;
    } else if (source.startsWith("--", at) || source.startsWith("/*", at)) {
      at = commentEnd(source, at);
    } else if (/\s/.test(source[at])) {
      at += 1;
    } else {
      word.lastIndex = at;
      const text = word.exec(source)?.[0] ?? source[at];
      found.push({ text, quoted: false });
      at += text.length;
    }
  }
  return found;
}

/// Whether the SQL holds PRAGMA, a schema and a dot or not, then one of the encryption pragmas, quoted or bare.
function asksForEncryption(source: string) {
  const found = tokens(source);
  return found.some((token, index) => {
    if (token.quoted || token.text.toUpperCase() !== "PRAGMA") return false;
    const dot = found[index + 2];
    const name = dot && !dot.quoted && dot.text === "." ? found[index + 3] : found[index + 1];
    return name !== undefined && encryptionPragma.test(name.text);
  });
}

function refuseEncryption(source: string) {
  if (asksForEncryption(source)) {
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
