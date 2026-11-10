//
//  jsx-dev-runtime.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// React's production build exports no jsxDEV, and bundles call it, so this module always has one.
import * as development from "react/jsx-dev-runtime";
import { jsx } from "react/jsx-runtime";

type JsxDEV = (type: unknown, props: unknown, key?: unknown, ...rest: unknown[]) => unknown;
const own = (development as { jsxDEV?: JsxDEV }).jsxDEV;

export const Fragment = development.Fragment;
export const jsxDEV: JsxDEV = own ?? ((type, props, key) => (jsx as JsxDEV)(type, props, key));
