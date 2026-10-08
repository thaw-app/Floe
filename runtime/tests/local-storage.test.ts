import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createLocalStorage, storagePersistence } from "../local-storage";

let folder: string;
let file: string;
const original = { ...storagePersistence };

beforeEach(() => {
    folder = fs.mkdtempSync(path.join(os.tmpdir(), "floe-local-storage-"));
    file = path.join(folder, "local-storage.json");
});

afterEach(() => {
    Object.assign(storagePersistence, original);
    fs.rmSync(folder, { recursive: true, force: true });
});

const onDisk = () => JSON.parse(fs.readFileSync(file, "utf8"));

describe("LocalStorage", () => {
    test("values come back with their type, and removing and clearing work", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("name", "floe");
        await storage.setItem("count", 3);
        await storage.setItem("on", true);
        expect(await storage.getItem("name")).toBe("floe");
        expect(await storage.getItem<number>("count")).toBe(3);
        expect(await storage.getItem<boolean>("on")).toBe(true);
        expect(await storage.getItem("missing")).toBeUndefined();
        expect(await storage.allItems()).toEqual({ name: "floe", count: 3, on: true });
        await storage.removeItem("count");
        expect(onDisk()).toEqual({ name: "floe", on: true });
        await storage.clear();
        expect(onDisk()).toEqual({});
    });

    test("a file from before this change still loads", async () => {
        fs.writeFileSync(file, JSON.stringify({ token: "abc", seen: 2 }));
        const storage = createLocalStorage(() => file);
        expect(await storage.getItem("token")).toBe("abc");
        expect(await storage.allItems()).toEqual({ token: "abc", seen: 2 });
    });

    test("a write that dies midway leaves the previous file whole", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("kept", "yes");
        storagePersistence.write = (target, content) => {
            // What a kill between the two steps leaves: half a temporary file, and no rename.
            fs.writeFileSync(`${target}.${process.pid}.tmp`, content.slice(0, content.length / 2));
            throw new Error("killed");
        };
        await expect(storage.setItem("lost", "x".repeat(4096))).rejects.toThrow("killed");
        expect(onDisk()).toEqual({ kept: "yes" });
        expect(await createLocalStorage(() => file).getItem("kept")).toBe("yes");
    });

    test("a file that cannot be read is moved aside, not overwritten", async () => {
        fs.writeFileSync(file, '{"token": "abc", "half');
        const storage = createLocalStorage(() => file);
        expect(await storage.allItems()).toEqual({});
        await storage.setItem("fresh", 1);
        expect(onDisk()).toEqual({ fresh: 1 });
        const aside = fs.readdirSync(folder).filter((name) => name.includes(".unreadable-"));
        expect(aside).toHaveLength(1);
        expect(fs.readFileSync(path.join(folder, aside[0]), "utf8")).toBe('{"token": "abc", "half');
    });

    test("an unchanged file is not read again", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("a", 1);
        let reads = 0;
        const read = storagePersistence.read;
        storagePersistence.read = (target) => {
            reads += 1;
            return read(target);
        };
        for (let index = 0; index < 50; index += 1) await storage.getItem("a");
        await storage.allItems();
        expect(reads).toBe(0);
    });

    test("what another process of the extension wrote is seen, and a write keeps it", async () => {
        const view = createLocalStorage(() => file);
        const background = createLocalStorage(() => file);
        await view.setItem("fromView", 1);
        await background.setItem("fromBackground", 2);
        expect(await view.getItem<number>("fromBackground")).toBe(2);
        await view.setItem("later", 3);
        expect(onDisk()).toEqual({ fromView: 1, fromBackground: 2, later: 3 });
    });

    test("processes saving at the same moment lose none of each other's keys", async () => {
        const writer = path.join(import.meta.dir, "storage-writer.ts");
        const writers = ["view", "background", "menu", "extra"].map((prefix) => Bun.spawn(["bun", writer, file, prefix, "40"], { stdout: "ignore", stderr: "inherit" }));
        expect(await Promise.all(writers.map((process) => process.exited))).toEqual([0, 0, 0, 0]);
        expect(Object.keys(onDisk()).length).toBe(160);
        expect(fs.existsSync(`${file}.lock`)).toBe(false);
    }, 30000);

    test("a lock left by a process that died is taken, and a fresh one is waited out", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("first", 1);
        fs.writeFileSync(`${file}.lock`, "");
        const long = new Date(Date.now() - 60_000);
        fs.utimesSync(`${file}.lock`, long, long);
        await storage.setItem("afterStale", 2);
        expect(onDisk()).toEqual({ first: 1, afterStale: 2 });

        fs.writeFileSync(`${file}.lock`, "");
        const started = Date.now();
        await storage.setItem("afterHeld", 3);
        expect(Date.now() - started).toBeGreaterThanOrEqual(1900);
        expect(onDisk()).toEqual({ first: 1, afterStale: 2, afterHeld: 3 });
        fs.unlinkSync(`${file}.lock`);
    }, 15000);

    test("removing a key that is not there writes nothing", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("a", 1);
        let writes = 0;
        const write = storagePersistence.write;
        storagePersistence.write = (target, content) => {
            writes += 1;
            write(target, content);
        };
        await storage.removeItem("missing");
        expect(writes).toBe(0);
    });

    test("changing what allItems returned does not change what is stored", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("a", 1);
        const items = await storage.allItems<Record<string, number>>();
        items.a = 99;
        expect(await storage.getItem<number>("a")).toBe(1);
    });

    test("no temporary file is left behind after a write", async () => {
        const storage = createLocalStorage(() => file);
        await storage.setItem("a", 1);
        expect(fs.readdirSync(folder)).toEqual(["local-storage.json"]);
    });
});
