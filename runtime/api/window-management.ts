//
//  window-management.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// WindowManagement, answered by the app through Accessibility (WindowManagement+System.swift).
import { request } from "../bridge";

type Bounds = { position: { x: number; y: number }; size: { width: number; height: number } };
type Window = {
  id: string;
  application?: { name: string; path: string; bundleId?: string };
  bounds: Bounds | "fullscreen";
  desktopId: string;
  fullScreenSettable: boolean;
  resizable: boolean;
  positionable: boolean;
  active: boolean;
};
type Desktop = { id: string; screenId: string; size: { width: number; height: number }; active: boolean; type: "User" | "FullScreen" };
type BoundsChange =
  | { id: string; bounds: { position?: { x?: number; y?: number }; size?: { width?: number; height?: number } }; desktopId?: string }
  | { id: string; bounds: "fullscreen" };

export const WindowManagement = {
  DesktopType: { User: "User", FullScreen: "FullScreen" },
  getDesktops: () => request("windowManagement.getDesktops", {}) as Promise<Desktop[]>,
  getActiveWindow: () => request("windowManagement.getActiveWindow", {}) as Promise<Window>,
  getWindowsOnActiveDesktop: () => request("windowManagement.getWindowsOnActiveDesktop", {}) as Promise<Window[]>,
  setWindowBounds: async (options: BoundsChange): Promise<void> => {
    await request("windowManagement.setWindowBounds", options);
  },
};
