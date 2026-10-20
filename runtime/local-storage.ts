// An extension's LocalStorage: one SQLite database in its support folder, shared by every process of the extension.
import { Database } from "bun:sqlite";
import fs from "node:fs";

type Items = Record<string, any>;

const itemsTable = "CREATE TABLE IF NOT EXISTS items (key TEXT PRIMARY KEY, value TEXT NOT NULL)";
// The marker is one row and one row only: the uniqueness is what makes INSERT OR IGNORE below a claim
// that exactly one process wins, so a migration that has run is never run again.
const migrationTable = "CREATE TABLE IF NOT EXISTS migration (done INTEGER NOT NULL UNIQUE)";

/// The file operations, replaceable so a test can count them or make one fail.
export const storagePersistence = {
    /// Written beside the file and renamed over it, so a kill mid-write keeps the previous complete file.
    /// The name carries the pid: two processes of one extension must not share a temporary file.
    write(file: string, content: string) {
        const temporary = `${file}.${process.pid}.tmp`;
        fs.writeFileSync(temporary, content);
        fs.renameSync(temporary, file);
    },
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
        await Bun.sleep(25 + (crypto.getRandomValues(new Uint8Array(1))[0] % 50));
        return patiently(work, deadline);
    }
}

/// The tables of items and of the migration marker, made when they are not there. A database that
/// cannot be read is moved aside, never one that is merely locked: locked is not the same as broken.
async function settle(opened: Database, target: string): Promise<Database> {
    try {
        await patiently(() => {
            opened.run(itemsTable);
            opened.run(migrationTable);
        });
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
        await patiently(() => {
            again.run(itemsTable);
            again.run(migrationTable);
        });
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

export function createLocalStorage(file: () => string) {
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
                await migrate(db, target);
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
                return row == null ? undefined : (JSON.parse(row.value) as T);
            });
            return read;
        },
        async setItem(key: string, value: unknown): Promise<void> {
            await patiently(async () => (await database()).query("INSERT OR REPLACE INTO items (key, value) VALUES (?, ?)").run(key, JSON.stringify(value)));
        },
        async removeItem(key: string): Promise<void> {
            await patiently(async () => (await database()).query("DELETE FROM items WHERE key = ?").run(key));
        },
        async allItems<T = Items>(): Promise<T> {
            const rows = await patiently(async () => (await database()).query("SELECT key, value FROM items").all() as { key: string; value: string }[]);
            return Object.fromEntries(rows.map(({ key, value }) => [key, JSON.parse(value)])) as T;
        },
        async clear(): Promise<void> {
            await patiently(async () => (await database()).run("DELETE FROM items"));
        },
    };
}
