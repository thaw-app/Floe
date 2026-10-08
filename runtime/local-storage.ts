// An extension's LocalStorage: one JSON file in its support folder, shared by every process of the extension.
import fs from "node:fs";

type Items = Record<string, any>;

/// The file operations, replaceable so a test can count them or make one fail.
export const storagePersistence = {
    read(file: string): string {
        return fs.readFileSync(file, "utf8");
    },
    /// Written beside the file and renamed over it, so a kill mid-write keeps the previous complete file.
    /// The name carries the pid: two processes of one extension must not share a temporary file.
    write(file: string, content: string) {
        const temporary = `${file}.${process.pid}.tmp`;
        fs.writeFileSync(temporary, content);
        fs.renameSync(temporary, file);
    },
    /// What tells an unchanged file from a changed one without reading it.
    stamp(file: string): string | undefined {
        try {
            const info = fs.statSync(file);
            return `${info.mtimeMs}:${info.size}:${info.ino}`;
        } catch {
            return undefined;
        }
    },
    /// Holds the file for one read, change and write. Two processes of an extension, its view and a background
    /// run, may both save at once: each would read the same items and the later write would drop the earlier key.
    /// The lock is a file made only if it is not there. One left by a process that died is taken after five
    /// seconds, and a holder that takes two is not waited for: saving late is better than not saving.
    locked<T>(file: string, work: () => T): T {
        const lock = `${file}.lock`;
        const deadline = Date.now() + 2000;
        let held = false;
        while (!held) {
            try {
                fs.closeSync(fs.openSync(lock, "wx"));
                held = true;
            } catch (error) {
                // Anything but "it is there" is the write's to report: a folder that is missing, a disk that is full.
                if ((error as NodeJS.ErrnoException).code !== "EEXIST") break;
                try {
                    if (Date.now() - fs.statSync(lock).mtimeMs > 5000) {
                        fs.unlinkSync(lock);
                        continue;
                    }
                } catch {
                    // Released between the two calls: ask again.
                    continue;
                }
                if (Date.now() >= deadline) break;
                Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2);
            }
        }
        try {
            return work();
        } finally {
            if (held) {
                try {
                    fs.unlinkSync(lock);
                } catch {}
            }
        }
    },
    keepAside(file: string) {
        fs.renameSync(file, `${file}.unreadable-${Date.now()}`);
    },
};

/// Runs a write inside a promise, so one that fails rejects and a caller's catch() sees it.
function writing(work: () => void): Promise<void> {
    return new Promise((resolve) => {
        work();
        resolve();
    });
}

export function createLocalStorage(file: () => string) {
    let known: { file: string; stamp: string | undefined; items: Items } | undefined;

    /// The items on disk. Reread only when the file changed, which another process of the extension may have done.
    function load(): Items {
        const path = file();
        const stamp = storagePersistence.stamp(path);
        if (known?.file === path && known.stamp === stamp) return known.items;
        let items: Items = {};
        if (stamp !== undefined) {
            try {
                const parsed = JSON.parse(storagePersistence.read(path));
                if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not an object");
                items = parsed;
            } catch {
                // A file that cannot be read is moved aside, not overwritten: it may be all of someone's saved data.
                try {
                    storagePersistence.keepAside(path);
                } catch {}
                known = { file: path, stamp: undefined, items: {} };
                return known.items;
            }
        }
        known = { file: path, stamp, items };
        return items;
    }

    function save(items: Items) {
        const path = file();
        storagePersistence.write(path, JSON.stringify(items));
        known = { file: path, stamp: storagePersistence.stamp(path), items };
    }

    return {
        getItem<T = string>(key: string): Promise<T | undefined> {
            return Promise.resolve(load()[key] as T | undefined);
        },
        setItem(key: string, value: unknown): Promise<void> {
            return writing(() => storagePersistence.locked(file(), () => save({ ...load(), [key]: value })));
        },
        removeItem(key: string): Promise<void> {
            return writing(() =>
                storagePersistence.locked(file(), () => {
                    const items = load();
                    if (!(key in items)) return;
                    const rest = { ...items };
                    delete rest[key];
                    save(rest);
                }),
            );
        },
        allItems<T = Items>(): Promise<T> {
            // A copy: what the caller does to it must not reach the next read.
            return Promise.resolve({ ...load() } as T);
        },
        clear(): Promise<void> {
            return writing(() => storagePersistence.locked(file(), () => save({})));
        },
    };
}
