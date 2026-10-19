//
//  browser.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// BrowserExtension, answered by the app from the browser itself through AppleScript (BrowserExtensionBridge.swift).
// The page is read by a script run in the tab, so the browser parses it and says what is visible.
import { request } from "../bridge";

type Tab = { id: number; url: string; title?: string; favicon?: string; active: boolean };
type ContentOptions = { format?: "html" | "text" | "markdown"; cssSelector?: string; tabId?: number };

export const BrowserExtension = {
  getTabs: () => request("browser.tabs", {}) as Promise<Tab[]>,
  async getContent(options: ContentOptions = {}): Promise<string> {
    const format = options.format ?? "markdown";
    const javascript = `(${pageContent.toString()})(${JSON.stringify(format)}, ${JSON.stringify(options.cssSelector ?? null)})`;
    const answer = JSON.parse((await request("browser.script", { javascript, tabId: options.tabId })) as string) as { content?: string };
    if (answer.content === undefined) throw new Error(`No element on the page matches "${options.cssSelector}"`);
    return answer.content;
  },
};

// Runs in the page, as source: it may use nothing from outside itself. Untyped, since the runtime has no DOM.
export function pageContent(format: string, selector: string | null): string {
  const doc = (globalThis as any).document;
  const root = selector ? doc.querySelector(selector) : doc.body ?? doc.documentElement;
  if (!root) return JSON.stringify({});
  if (format === "html") return JSON.stringify({ content: (selector ? root : doc.documentElement).outerHTML });
  if (format === "text") return JSON.stringify({ content: root.innerText });
  const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "HEAD", "IFRAME", "CANVAS", "BUTTON", "SELECT", "INPUT"]);
  const blocks = new Set(["P", "DIV", "SECTION", "ARTICLE", "HEADER", "FOOTER", "MAIN", "ASIDE", "NAV", "FIGURE", "TABLE", "FORM", "DL", "DD", "DT"]);
  const walk = (node: any, depth: number, pre: boolean): string => {
    if (node.nodeType === 3) return pre ? node.textContent : node.textContent.replace(/\s+/g, " ");
    if (node.nodeType !== 1) return "";
    const tag: string = node.tagName.toUpperCase();
    if (skipped.has(tag) || node.hidden || node.getAttribute("aria-hidden") === "true") return "";
    const inner = (nextDepth = depth, nextPre = pre) => Array.from(node.childNodes as any[], (child) => walk(child, nextDepth, nextPre)).join("");
    const wrapped = (mark: string) => {
      const text = inner().trim();
      return text ? `${mark}${text}${mark}` : "";
    };
    if (/^H[1-6]$/.test(tag)) return `\n\n${"#".repeat(Number(tag[1]))} ${inner().trim()}\n\n`;
    if (blocks.has(tag)) return `\n\n${inner()}\n\n`;
    switch (tag) {
      case "BR":
        return "\n";
      case "HR":
        return "\n\n---\n\n";
      case "STRONG":
      case "B":
        return wrapped("**");
      case "EM":
      case "I":
        return wrapped("_");
      case "CODE":
        return pre ? inner() : wrapped("`");
      case "PRE":
        return `\n\n\`\`\`\n${inner(depth, true).replace(/\n$/, "")}\n\`\`\`\n\n`;
      case "A": {
        const text = inner().trim();
        const href = node.getAttribute("href");
        return text && href && !href.startsWith("javascript:") ? `[${text}](${node.href})` : text;
      }
      case "IMG":
        return node.src ? `![${node.getAttribute("alt") ?? ""}](${node.src})` : "";
      case "UL":
      case "OL": {
        const items = Array.from(node.children as any[]).filter((child) => child.tagName.toUpperCase() === "LI");
        const lines = items.map((item, index) => {
          const marker = tag === "OL" ? `${index + 1}.` : "-";
          const text = Array.from(item.childNodes as any[], (child) => walk(child, depth + 1, pre)).join("").trim();
          return `${"  ".repeat(depth)}${marker} ${text}`;
        });
        return `\n\n${lines.join("\n")}\n\n`;
      }
      case "BLOCKQUOTE":
        const quoted = inner().trim().split("\n").map((line) => "> " + line);
        return `\n\n${quoted.join("\n")}\n\n`;
      case "TR":
        return `\n${Array.from(node.children as any[], (cell) => walk(cell, depth, pre).trim()).join(" | ")}\n`;
      default:
        return inner();
    }
  };
  const lines = walk(root, 0, false).split("\n").map((line) => line.trimEnd());
  const markdown = lines.join("\n").replace(/\n{3,}/g, "\n\n").trim();
  return JSON.stringify({ content: markdown });
}
