//
//  oauth.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Raycast OAuth PKCE client. The browser flow and token storage run in the Swift app over the bridge.
// Parked until the app sets FLOE_OAUTH: a client still constructs, and only starting a sign-in fails.
import { ctx, request } from "../bridge";

const signInIsOn = () => process.env.FLOE_OAUTH === "1";

// A preference that takes a token or key, which most extensions accept in place of signing in.
function tokenPreference() {
  const command = ctx.manifest.commands?.find((candidate: { name: string }) => candidate.name === ctx.commandName);
  const declared: { name: string; title?: string; type?: string }[] = [...(ctx.manifest.preferences ?? []), ...(command?.preferences ?? [])];
  const secrets = declared.filter((preference) => preference.type === "password");
  const named = (preference: { name: string; title?: string }) => /token|api[ _-]?key|secret/i.test(`${preference.name} ${preference.title ?? ""}`);
  return secrets.find(named) ?? secrets[0] ?? declared.find(named);
}

// A provider whose sign-in the app can lend from one the user already has on this Mac: GitHub, from the GitHub CLI.
// The app asks the user before it lends. An extension asks for saved tokens first, so it never starts a sign-in.
export function isLent(provider?: string): boolean {
  return /^github$/i.test(provider?.trim() ?? "");
}

function signInUnavailable(provider?: string) {
  const preference = tokenPreference();
  const service = provider ? ` to ${provider}` : "";
  const instead = preference
    ? `Add "${preference.title ?? preference.name}" in this extension's preferences instead.`
    : "This extension has no token preference to use instead.";
  if (isLent(provider)) {
    const token = preference ? ` Or add "${preference.title ?? preference.name}" in this extension's preferences.` : "";
    return new Error(`Floe signs in to GitHub with the GitHub CLI. Install it, run "gh auth login", and allow it when Floe asks.${token}`);
  }
  return new Error(`Floe can't sign in${service} yet. ${instead}`);
}

export const RedirectMethod = { Web: "web", App: "app", AppURI: "appURI" } as const;

function redirectURI(): string {
  // Floe cannot receive Raycast raycast.com or raycast:// redirects, so every method uses the app scheme.
  return `floe://oauth?package_name=${ctx.manifest.name}`;
}

const unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
function randomString(length: number): string {
  const values = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (const value of values) out += unreserved[value % unreserved.length];
  return out;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCodePoint(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function s256Challenge(verifier: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64url(new Uint8Array(hash));
}

export type AuthorizationRequestOptions = {
  endpoint: string;
  clientId: string;
  scope: string;
  extraParameters?: Record<string, string>;
};

export class AuthorizationRequest {
  endpoint: string;
  clientId: string;
  scope: string;
  extraParameters: Record<string, string>;
  codeVerifier: string;
  codeChallenge: string;
  state: string;
  redirectURI: string;

  constructor(init: AuthorizationRequestOptions & { codeVerifier: string; codeChallenge: string; state: string; redirectURI: string }) {
    this.endpoint = init.endpoint;
    this.clientId = init.clientId;
    this.scope = init.scope;
    this.extraParameters = init.extraParameters ?? {};
    this.codeVerifier = init.codeVerifier;
    this.codeChallenge = init.codeChallenge;
    this.state = init.state;
    this.redirectURI = init.redirectURI;
  }

  toURL(): string {
    const url = new URL(this.endpoint);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("code_challenge", this.codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
    url.searchParams.set("client_id", this.clientId);
    url.searchParams.set("redirect_uri", this.redirectURI);
    url.searchParams.set("scope", this.scope);
    url.searchParams.set("state", this.state);
    for (const [key, value] of Object.entries(this.extraParameters)) url.searchParams.set(key, value);
    return url.toString();
  }
}

export type TokenSetInit = {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  expiresIn?: number;
  scope?: string;
  updatedAt?: Date;
};

export class TokenSet {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  expiresIn?: number;
  scope?: string;
  updatedAt: Date;

  constructor(init: TokenSetInit) {
    this.accessToken = init.accessToken;
    this.refreshToken = init.refreshToken;
    this.idToken = init.idToken;
    this.expiresIn = init.expiresIn;
    this.scope = init.scope;
    this.updatedAt = init.updatedAt ?? new Date();
  }

  isExpired(): boolean {
    if (this.expiresIn === undefined) return false;
    return Date.now() >= this.updatedAt.getTime() + this.expiresIn * 1000 - 10000;
  }
}

type RawTokenResponse = {
  access_token: string;
  refresh_token?: string;
  id_token?: string;
  expires_in?: number;
  scope?: string;
};

function toPlainTokens(input: TokenSet | TokenSetInit | RawTokenResponse): Record<string, unknown> {
  if (input instanceof TokenSet) {
    return {
      accessToken: input.accessToken,
      refreshToken: input.refreshToken,
      idToken: input.idToken,
      expiresIn: input.expiresIn,
      scope: input.scope,
      updatedAt: input.updatedAt.toISOString(),
    };
  }
  const record = input as Record<string, unknown>;
  let updatedAt: string;
  if (record.updatedAt instanceof Date) updatedAt = record.updatedAt.toISOString();
  else if (typeof record.updatedAt === "string") updatedAt = record.updatedAt;
  else updatedAt = new Date().toISOString();
  if (typeof record.access_token === "string") {
    return {
      accessToken: record.access_token,
      refreshToken: record.refresh_token,
      idToken: record.id_token,
      expiresIn: record.expires_in,
      scope: record.scope,
      updatedAt,
    };
  }
  return {
    accessToken: record.accessToken,
    refreshToken: record.refreshToken,
    idToken: record.idToken,
    expiresIn: record.expiresIn,
    scope: record.scope,
    updatedAt,
  };
}

export type PKCEClientOptions = {
  redirectMethod: (typeof RedirectMethod)[keyof typeof RedirectMethod];
  providerName: string;
  providerIcon?: string;
  providerId?: string;
  description?: string;
};

export class PKCEClient {
  private readonly options: Partial<PKCEClientOptions>;

  constructor(options?: Partial<PKCEClientOptions>) {
    this.options = options ?? {};
  }

  private get providerId(): string {
    return this.options.providerId ?? this.options.providerName ?? "";
  }

  async authorizationRequest(options: AuthorizationRequestOptions): Promise<AuthorizationRequest> {
    if (!signInIsOn()) throw signInUnavailable(this.options.providerName);
    const codeVerifier = randomString(64);
    const codeChallenge = await s256Challenge(codeVerifier);
    return new AuthorizationRequest({ ...options, codeVerifier, codeChallenge, state: randomString(32), redirectURI: redirectURI() });
  }

  async authorize(requestOrOptions: AuthorizationRequest | { url: string }): Promise<{ authorizationCode: string }> {
    if (!signInIsOn()) throw signInUnavailable(this.options.providerName);
    const url = requestOrOptions instanceof AuthorizationRequest ? requestOrOptions.toURL() : requestOrOptions.url;
    const state = requestOrOptions instanceof AuthorizationRequest ? requestOrOptions.state : (requestOrOptions as { state?: string }).state;
    const response = await request("oauth.authorize", { url, state, providerName: this.options.providerName });
    const callback = typeof response === "string" ? response : (response?.url as string);
    const params = new URL(callback).searchParams;
    const error = params.get("error");
    if (error) throw new Error(params.get("error_description") ?? error);
    if (state !== undefined && params.get("state") !== state) throw new Error("OAuth state mismatch");
    const code = params.get("code");
    if (!code) throw new Error("OAuth callback has no authorization code");
    return { authorizationCode: code };
  }

  async setTokens(tokens: TokenSet | TokenSetInit | RawTokenResponse): Promise<void> {
    if (!signInIsOn()) throw signInUnavailable(this.options.providerName);
    await request("oauth.setTokens", { providerId: this.providerId, tokens: toPlainTokens(tokens) });
  }

  private get isLent(): boolean {
    return isLent(this.options.providerId) || isLent(this.options.providerName);
  }

  async getTokens(): Promise<TokenSet | undefined> {
    if (!signInIsOn() && !this.isLent) return undefined;
    const stored = await request("oauth.getTokens", { providerId: this.providerId });
    if (stored === null || stored === undefined) return undefined;
    return new TokenSet({ ...stored, updatedAt: new Date(stored.updatedAt) });
  }

  async removeTokens(): Promise<void> {
    if (!signInIsOn() && !this.isLent) return;
    await request("oauth.removeTokens", { providerId: this.providerId });
  }
}

export const OAuth = { RedirectMethod, PKCEClient, TokenSet, AuthorizationRequest };
