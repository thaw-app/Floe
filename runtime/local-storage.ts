// An extension's LocalStorage: one SQLite database in its support folder, shared by every process of the extension.
// With the storage key from the app each value is sealed, as Raycast keeps its LocalStorage encrypted.
import { Database } from "bun:sqlite";
import { createCipheriv, createDecipheriv, randomBytes, randomInt } from "node:crypto";
import fs from "node:fs";

type Items = Record<string, any>;

const itemsTable = "CREATE TABLE IF NOT EXISTS items (key TEXT PRIMARY KEY, value TEXT NOT NULL)";
// The marker is one row and one row only: the uniqueness is what makes INSERT OR IGNORE below a claim
// that exactly one process wins, so a migration that has run is never run again.
const migrationTable = "CREATE TABLE IF NOT EXISTS migration (done INTEGER NOT NULL UNIQUE)";

/// Ceilings no extension reaches by keeping what it needs, which stop one that writes without end.
/// Raycast documents none; a write past one fails the way a failed write always has, by rejecting.
export const storageLimits = { valueBytes: 8 << 20, totalBytes: 64 << 20, keys: 65_536 };

// What the items take, kept by SQLite on every insert, change and delete, so a write checks it without a scan.
const size = (row: string) => `length(CAST(${row}.key AS BLOB)) + length(CAST(${row}.value AS BLOB))`;
const usage = [
    "CREATE TABLE IF NOT EXISTS usage (id INTEGER PRIMARY KEY CHECK (id = 1), keys INTEGER NOT NULL, bytes INTEGER NOT NULL)",
    `INSERT OR IGNORE INTO usage SELECT 1, count(*), coalesce(sum(${size("items")}), 0) FROM items WHERE NOT EXISTS (SELECT 1 FROM usage)`,
    `CREATE TRIGGER IF NOT EXISTS items_added AFTER INSERT ON items BEGIN UPDATE usage SET keys = keys + 1, bytes = bytes + ${size("new")}; END`,
    `CREATE TRIGGER IF NOT EXISTS items_changed AFTER UPDATE ON items BEGIN UPDATE usage SET bytes = bytes + ${size("new")} - (${size("old")}); END`,
    `CREATE TRIGGER IF NOT EXISTS items_removed AFTER DELETE ON items BEGIN UPDATE usage SET keys = keys - 1, bytes = bytes - (${size("old")}); END`,
];

// A sealed value: this prefix, then the IV, the tag and the AES-256-GCM ciphertext of its JSON, in base64. No JSON
// value starts with a letter s, so a plain value from before is never taken for one.
const sealedPrefix = "sealed1:";

/// The item's key is bound in, so a sealed value moved to another key does not open there.
function seal(itemKey: string, json: string, key: Buffer): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", key, iv);
    cipher.setAAD(Buffer.from(itemKey, "utf8"));
    const body = Buffer.concat([cipher.update(json, "utf8"), cipher.final()]);
    return sealedPrefix + Buffer.concat([iv, cipher.getAuthTag(), body]).toString("base64");
}

/// The JSON a stored value holds. Undefined for one sealed under another key, or damaged: it reads as missing.
function unseal(itemKey: string, stored: string, key: Buffer | undefined): string | undefined {
    if (!stored.startsWith(sealedPrefix)) return stored;
    if (!key) return undefined;
    try {
        const bytes = Buffer.from(stored.slice(sealedPrefix.length), "base64");
        const decipher = createDecipheriv("aes-256-gcm", key, bytes.subarray(0, 12));
        decipher.setAAD(Buffer.from(itemKey, "utf8"));
        decipher.setAuthTag(bytes.subarray(12, 28));
        return Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]).toString("utf8");
    } catch {
        return undefined;
    }
}

/// Seals what an older Floe stored plainly. Secure delete overwrites the plain text's pages from here on, and
/// a vacuum rewrites the file, so text deleted before then is gone too.
async function sealPlainRows(database: Database, key: Buffer) {
    database.run("PRAGMA secure_delete = ON");
    const update = database.prepare("UPDATE items SET value = ? WHERE key = ? AND value = ?");
    const sealed = await patiently(() =>
        database.transaction(() => {
            const plain = database.query(`SELECT key, value FROM items WHERE value NOT LIKE '${sealedPrefix}%'`).all() as { key: string; value: string }[];
            for (const row of plain) update.run(seal(row.key, row.value, key), row.key, row.value);
            return plain.length;
        })(),
    );
    // user_version 1 marks a file that was vacuumed once sealed. Checked on its own, since text deleted before
    // may be there with no plain row left, and a vacuum cut short by a quit is done at the next opening.
    const { user_version: version } = database.query("PRAGMA user_version").get() as { user_version: number };
    if (sealed > 0 || version < 1) {
        await patiently(() => database.run("VACUUM"));
        database.run("PRAGMA user_version = 1");
    }
}

/// The file operations, replaceable so a test can count them or make one fail.
export const storagePersistence = {
    /// The database of an extension's storage. Replaceable so a test can hold one or break one.
    open(file: string): Database {
        return new Database(file);
    },
    keepAside(file: string) {
        fs.renameSync(file, `${file}.unreadable-${Date.now()}`);
    },
};

/// True of an error that says the database is held by another process right now. A held database is waited for.
function isHeld(error: unknown): boolean {
    const code = (error as { code?: string }).code ?? "";
    if (code === "SQLITE_BUSY" || code === "SQLITE_LOCKED") return true;
    return /locked|busy/i.test((error as Error)?.message ?? "");
}

/// True of an error that says the file is no database, or a damaged one. Only such a file is moved aside:
/// a full disk or a read-only folder fails the call and leaves the data where it is.
function isBroken(error: unknown): boolean {
    const code = (error as { code?: string }).code ?? "";
    return code === "SQLITE_NOTADB" || code === "SQLITE_CORRUPT";
}

/// Runs a database step, waiting out a database another process holds. The wait is a sleep between
/// tries, so the event loop keeps running while the other process finishes its work.
async function patiently<T>(work: () => T | Promise<T>, deadline = Date.now() + 5000): Promise<T> {
    try {
        return await work();
    } catch (error) {
        if (Date.now() >= deadline || !isHeld(error)) throw error;
        // A random wait, so processes held up together do not all try again at once.
        await Bun.sleep(randomInt(25, 75));
        return patiently(work, deadline);
    }
}

function tables(database: Database) {
    database.transaction(() => [itemsTable, migrationTable, ...usage].forEach((statement) => database.run(statement)))();
}

/// What a plain value of this many bytes takes once sealed: the prefix, then base64 of IV, tag and ciphertext.
const sealedBytes = (bytes: number) => sealedPrefix.length + 4 * Math.ceil((bytes + 28) / 3);

/// Refuses a write that would take the storage past a ceiling, before anything is written. A value is measured
/// as plain JSON, and the whole as stored, against a ceiling grown by what sealing adds.
function checkRoom(database: Database, key: string, plain: string, value: string, sealed: boolean) {
    const valueBytes = Buffer.byteLength(plain);
    if (valueBytes > storageLimits.valueBytes) {
        throw new Error(`LocalStorage could not save "${key}": the value is ${megabytes(valueBytes)}, and one value may take ${megabytes(storageLimits.valueBytes)}.`);
    }
    const now = database.query("SELECT keys, bytes FROM usage").get() as { keys: number; bytes: number };
    const old = database.query(`SELECT ${size("items")} AS bytes FROM items WHERE key = ?`).get(key) as { bytes: number } | null;
    if (!old && now.keys >= storageLimits.keys) {
        throw new Error(`LocalStorage could not save "${key}": it holds ${storageLimits.keys} keys, as many as it may.`);
    }
    const bytes = now.bytes - (old?.bytes ?? 0) + Buffer.byteLength(key) + Buffer.byteLength(value);
    const rows = now.keys + (old ? 0 : 1);
    // Sealing adds a third, and to every value its prefix, IV, tag and padding.
    const ceiling = sealed ? Math.ceil((storageLimits.totalBytes * 4) / 3) + rows * (sealedBytes(0) + 4) : storageLimits.totalBytes;
    if (bytes > ceiling) {
        throw new Error(`LocalStorage could not save "${key}": everything stored would take ${megabytes(bytes)}, and it may take ${megabytes(ceiling)}.`);
    }
}

const megabytes = (bytes: number) => `${(bytes / (1 << 20)).toFixed(1)} MB`;

/// The tables of items and of the migration marker, made when they are not there. A database that
/// cannot be read is moved aside, never one that is merely locked: locked is not the same as broken.
async function settle(opened: Database, target: string): Promise<Database> {
    try {
        await patiently(() => tables(opened));
        return opened;
    } catch (error) {
        if (!isBroken(error)) throw error;
        try {
            opened.close();
        } catch {}
        try {
            storagePersistence.keepAside(target);
        } catch {}
        const again = storagePersistence.open(target);
        await patiently(() => tables(again));
        return again;
    }
}

/// The JSON kept from before this change is read into the database once and is gone. The claim and the
/// import are one transaction, so two processes that read the same file cannot both import. An import
/// never covers what a key already holds: anything in the table was written after the file was read.
/// A file that cannot be read is moved aside, not thrown away: it may be all of someone's saved data.
async function migrate(database: Database, file: string) {
    const former = file.replace(/\.sqlite$/, ".json");
    if (former === file || !fs.existsSync(former)) return;
    let items: Items;
    try {
        const parsed = JSON.parse(fs.readFileSync(former, "utf8"));
        if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not an object");
        items = parsed;
    } catch {
        try {
            storagePersistence.keepAside(former);
        } catch {}
        return;
    }
    const insert = database.prepare("INSERT OR IGNORE INTO items (key, value) VALUES (?, ?)");
    const claim = database.transaction(() => {
        const claimed = database.prepare("INSERT OR IGNORE INTO migration (done) VALUES (1)").run();
        if (claimed.changes === 0) return;
        for (const [key, value] of Object.entries(items)) insert.run(key, JSON.stringify(value));
    });
    await patiently(claim);
    fs.rmSync(former, { force: true });
}

/// Without a key, as in tests and a Floe that has none, values are stored as plain JSON. A locked storage is one
/// whose key Floe could not read: it saves nothing, so nothing sealed is replaced and nothing is written plainly.
export function createLocalStorage(file: () => string, storageKey: () => Buffer | undefined = () => undefined, locked: () => boolean = () => false) {
    const refuseWhenLocked = () => {
        if (locked()) throw new Error("LocalStorage can't save: Floe couldn't read the key it is encrypted with from your keychain.");
    };
    // One connection for as long as this storage lives, so what another process saved is seen here,
    // and what is saved here is seen by it: each statement is one whole transaction of its own.
    // The one opening is shared, so calls that meet before it is done wait for the same database.
    const openings = new Map<string, Promise<Database>>();

    function database(): Promise<Database> {
        const target = file();
        let opening = openings.get(target);
        if (!opening) {
            opening = (async () => {
                const db = await settle(storagePersistence.open(target), target);
                // A locked storage leaves the file from before alone: moved in, it would be stored plainly.
                if (!locked()) await migrate(db, target);
                const key = storageKey();
                if (key) await sealPlainRows(db, key);
                return db;
            })();
            opening.catch(() => openings.delete(target));
            openings.set(target, opening);
        }
        return opening;
    }

    return {
        async getItem<T = string>(key: string): Promise<T | undefined> {
            const read = await patiently(async () => {
                const row = (await database()).query("SELECT value FROM items WHERE key = ?").get(key) as { value: string } | null | undefined;
                const json = row == null ? undefined : unseal(key, row.value, storageKey());
                return json === undefined ? undefined : (JSON.parse(json) as T);
            });
            return read;
        },
        async setItem(key: string, value: unknown): Promise<void> {
            refuseWhenLocked();
            const sealing = storageKey();
            const plain = JSON.stringify(value);
            const json = plain !== undefined && sealing ? seal(key, plain, sealing) : plain;
            // An upsert, not INSERT OR REPLACE: a replacement deletes without running the delete trigger.
            await patiently(async () => {
                const db = await database();
                db.transaction(() => {
                    // JSON has no undefined: that write fails on the table's NOT NULL, as it always did.
                    if (json !== undefined && plain !== undefined) checkRoom(db, key, plain, json, sealing !== undefined);
                    db.query("INSERT INTO items (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value").run(key, json);
                })();
            });
        },
        async removeItem(key: string): Promise<void> {
            refuseWhenLocked();
            await patiently(async () => (await database()).query("DELETE FROM items WHERE key = ?").run(key));
        },
        async allItems<T = Items>(): Promise<T> {
            const rows = await patiently(async () => (await database()).query("SELECT key, value FROM items").all() as { key: string; value: string }[]);
            const key = storageKey();
            return Object.fromEntries(
                rows.flatMap(({ key: itemKey, value }) => {
                    const json = unseal(itemKey, value, key);
                    return json === undefined ? [] : [[itemKey, JSON.parse(json)]];
                }),
            ) as T;
        },
        async clear(): Promise<void> {
            refuseWhenLocked();
            await patiently(async () => (await database()).run("DELETE FROM items"));
        },
    };
}
