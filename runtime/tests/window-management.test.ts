//
//  window-management.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, test } from "bun:test";
import { handleReply } from "../bridge";
import { environment, WindowManagement } from "../api/index";
import { installRuntime, sent } from "./support";

installRuntime("window-management-tests");

describe("WindowManagement", () => {
  const desktop = { id: "1-3", screenId: "1", size: { width: 1440, height: 875 }, active: true, type: "User" };
  const window = { id: "42", bounds: "fullscreen", desktopId: "1-3", fullScreenSettable: true, resizable: true, positionable: true, active: true };

  // Each read is one request, and its answer is handed on as it came.
  async function answered(read: () => Promise<unknown>, method: string, answer: unknown) {
    const reading = read();
    const [ask] = sent("request");
    expect(ask.method).toBe(method);
    handleReply({ id: ask.id, result: answer });
    expect(await reading).toEqual(answer);
  }

  test("getDesktops asks the app", () => answered(WindowManagement.getDesktops, "windowManagement.getDesktops", [desktop]));
  test("getActiveWindow asks the app", () => answered(WindowManagement.getActiveWindow, "windowManagement.getActiveWindow", window));
  test("getWindowsOnActiveDesktop asks the app", () =>
    answered(WindowManagement.getWindowsOnActiveDesktop, "windowManagement.getWindowsOnActiveDesktop", [window]));

  test("setWindowBounds sends the window, its bounds and the desktop, and fails with the app's reason", async () => {
    const moved = WindowManagement.setWindowBounds({ id: "42", desktopId: "1-3", bounds: { position: { x: 10 }, size: { width: 600 } } });
    const [ask] = sent("request");
    expect(ask.method).toBe("windowManagement.setWindowBounds");
    expect(ask.params).toEqual({ id: "42", desktopId: "1-3", bounds: { position: { x: 10 }, size: { width: 600 } } });
    handleReply({ id: ask.id, result: null });
    expect(await moved).toBeUndefined();

    const filled = WindowManagement.setWindowBounds({ id: "42", bounds: "fullscreen" });
    const fill = sent("request")[1];
    expect(fill.params).toEqual({ id: "42", bounds: "fullscreen" });
    handleReply({ id: fill.id, error: "This window can't go full screen." });
    await expect(filled).rejects.toThrow("This window can't go full screen.");
  });

  test("an extension may use it when the app had Accessibility access", () => {
    delete process.env.FLOE_WINDOWS;
    expect(environment.canAccess(WindowManagement)).toBe(false);
    process.env.FLOE_WINDOWS = "1";
    expect(environment.canAccess(WindowManagement)).toBe(true);
    delete process.env.FLOE_WINDOWS;
    expect(WindowManagement.DesktopType.FullScreen).toBe("FullScreen");
  });
});
