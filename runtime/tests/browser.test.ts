//
//  browser.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, test } from "bun:test";
import { handleReply } from "../bridge";
import { BrowserExtension, pageContent } from "../api/browser";
import { environment } from "../api/index";
import { installRuntime, sent } from "./support";

installRuntime("browser-tests");

// Just enough of a DOM for the page reader: elements, text and attributes.
type FakeNode = { nodeType: number; tagName?: string; textContent?: string; childNodes: FakeNode[]; children: FakeNode[]; [key: string]: unknown };
const textNode = (text: string): FakeNode => ({ nodeType: 3, textContent: text, childNodes: [], children: [] });
function element(tagName: string, attributes: Record<string, string>, ...content: (FakeNode | string)[]): FakeNode {
  const childNodes = content.map((child) => (typeof child === "string" ? textNode(child) : child));
  return { nodeType: 1, tagName, ...attributes, childNodes, children: childNodes.filter((child) => child.nodeType === 1), getAttribute: (name: string) => attributes[name] ?? null };
}

function read(body: FakeNode, format: string, selector: string | null = null) {
  const document = { body, documentElement: { outerHTML: "<html>whole</html>" }, querySelector: () => body };
  Object.assign(globalThis, { document });
  try {
    return JSON.parse(pageContent(format, selector));
  } finally {
    delete (globalThis as { document?: unknown }).document;
  }
}

describe("the page reader", () => {
  test("turns headings, emphasis, links, lists, code and images into Markdown, and leaves scripts out", () => {
    const body = element(
      "BODY",
      {},
      element("H1", {}, "Floe"),
      element("SCRIPT", {}, "track()"),
      element("P", {}, "A ", element("STRONG", {}, "fast"), " launcher, ", element("A", { href: "https://floe.test/docs" }, "docs"), "."),
      element("UL", {}, element("LI", {}, "one"), element("LI", {}, "two", element("OL", {}, element("LI", {}, "nested")))),
      element("PRE", {}, element("CODE", {}, "let a = 1\n")),
      element("IMG", { alt: "logo", src: "https://floe.test/logo.png" }),
    );

    expect(read(body, "markdown").content).toBe(
      "# Floe\n\nA **fast** launcher, [docs](https://floe.test/docs).\n\n- one\n- two\n\n  1. nested\n\n```\nlet a = 1\n```\n\n![logo](https://floe.test/logo.png)",
    );
  });

  test("a link that runs or embeds something keeps only its text", () => {
    const links = ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,<b>", "vbscript:msgbox"].map((href) => element("A", { href }, "here"));
    const body = element("BODY", {}, element("P", {}, ...links, element("A", { href: "mailto:a@floe.test" }, "mail")));

    expect(read(body, "markdown").content).toBe("herehereherehere[mail](mailto:a@floe.test)");
  });

  test("html is the whole document, or the matched element's; text is what the browser shows", () => {
    const body = { ...element("MAIN", {}), outerHTML: "<main>part</main>", innerText: "shown" };
    expect(read(body, "html").content).toBe("<html>whole</html>");
    expect(read(body, "html", "main").content).toBe("<main>part</main>");
    expect(read(body, "text").content).toBe("shown");
  });
});

describe("BrowserExtension", () => {
  test("getTabs asks the app, and environment.canAccess says yes", async () => {
    const tabs = BrowserExtension.getTabs();
    const [ask] = sent("request");
    expect(ask.method).toBe("browser.tabs");
    handleReply({ id: ask.id, result: [{ id: 1, url: "https://floe.test", title: "Floe", active: true }] });

    expect(await tabs).toEqual([{ id: 1, url: "https://floe.test", title: "Floe", active: true }]);
    expect(environment.canAccess(BrowserExtension)).toBe(true);
  });

  test("getContent runs the page reader in the tab asked for, Markdown by default", async () => {
    const content = BrowserExtension.getContent({ tabId: 7 });
    const [ask] = sent("request");
    expect(ask.method).toBe("browser.script");
    expect(ask.params.tabId).toBe(7);
    expect(ask.params.javascript).toContain('("markdown", null)');
    handleReply({ id: ask.id, result: JSON.stringify({ content: "# Page" }) });

    expect(await content).toBe("# Page");
  });

  test("a selector that matches nothing says so", async () => {
    const content = BrowserExtension.getContent({ cssSelector: "#missing" });
    handleReply({ id: sent("request")[0].id, result: "{}" });

    await expect(content).rejects.toThrow('No element on the page matches "#missing"');
  });
});
