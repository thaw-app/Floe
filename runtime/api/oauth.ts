//
//  oauth.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Raycast OAuth PKCE client. The browser flow and token storage run in the Swift app over the bridge.
// Off unless the app sets FLOE_OAUTH: a client still constructs, and only starting a sign-in fails.
import { ctx, request, send } from "../bridge";

const signInIsOn = () => process.env.FLOE_OAUTH === "1";

// A preference that takes a token or key, which most extensions accept in place of signing in.
function tokenPreference() {
  const command = ctx.manifest.commands?.find((candidate: { name: string }) => candidate.name === ctx.commandName);
  const declared: { name: string; title?: string; type?: string }[] = [...(ctx.manifest.preferences ?? []), ...(command?.preferences ?? [])];
  const secrets = declared.filter((preference) => preference.type === "password");
  const named = (preference: { name: string; title?: string }) => /token|api[ _-]?key|secret/i.test(`${preference.name} ${preference.title ?? ""}`);
  return secrets.find(named) ?? secrets[0] ?? declared.find(named);
}

// The providers whose sign-in the app can lend from one the user already has on this Mac, each with the tool it comes from.
const lenders: Record<string, { service: string; tool: string; login: string }> = {
  github: { service: "GitHub", tool: "GitHub CLI", login: "gh auth login" },
  gitlab: { service: "GitLab", tool: "GitLab CLI", login: "glab auth login" },
};

function lender(provider?: string) {
  const name = provider?.trim().toLowerCase() ?? "";
  return Object.hasOwn(lenders, name) ? lenders[name] : undefined;
}

// The app asks the user before it lends. An extension asks for saved tokens first, so it never starts a sign-in.
export function isLent(provider?: string): boolean {
  return lender(provider) !== undefined;
}

function signInUnavailable(provider?: string) {
  const preference = tokenPreference();
  const service = provider ? ` to ${provider}` : "";
  const instead = preference
    ? `Add "${preference.title ?? preference.name}" in this extension's preferences instead.`
    : "This extension has no token preference to use instead.";
  const lent = lender(provider);
  if (lent) {
    const token = preference ? ` Or add "${preference.title ?? preference.name}" in this extension's preferences.` : "";
    return new Error(`Floe signs in to ${lent.service} with the ${lent.tool}. Install it, run "${lent.login}", and allow it when Floe asks.${token}`);
  }
  // The app asks for the token in a form and runs the command again; the error is for a command with no form to show.
  if (preference) send({ type: "signIn", preference: preference.name, provider });
  return new Error(`Floe can't sign in${service} yet. ${instead}`);
}

// React renders a view that suspended on a sign-in again, and withAccessToken starts a new sign-in each time the last
// one failed: one cancel opened the browser a hundred times. For a moment after a failure, asking again fails with it.
const failureMemory = 2000;
function recentFailure(): Error | undefined {
  const failure = ctx.signInFailure;
  return failure && Date.now() - failure.at < failureMemory ? failure.error : undefined;
}

function failed(error: unknown): Error {
  const failure = error instanceof Error ? error : new Error(`Sign-in failed: ${JSON.stringify(error)}`);
  ctx.signInFailure = { error: failure, at: Date.now() };
  return failure;
}

export const RedirectMethod = { Web: "web", App: "app", AppURI: "appURI" } as const;

// Temporary: providers only allow Raycast's redirect addresses, so the browser returns through raycast.com.
const raycastRedirect = "https://raycast.com/redirect?packageName=Extension";
// The app addresses an OAuth app may name instead; the app opens them in Floe while the sign-in waits.
const redirectAddresses: Record<string, string> = {
  [RedirectMethod.Web]: raycastRedirect,
  [RedirectMethod.App]: "raycast://oauth?package_name=Extension",
  [RedirectMethod.AppURI]: "com.raycast:/oauth?package_name=Extension",
};

// Raycast's redirect page opens the scheme its state names, which is how the result reaches floe://oauth.
function stateForFloe(provider?: string): string {
  const state = JSON.stringify({ scheme: "floe", id: randomString(32), providerName: provider });
  return base64url(new TextEncoder().encode(state));
}

function isReceivable(method?: string): boolean {
  return method === undefined || Object.hasOwn(redirectAddresses, method);
}

const unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
// A byte past the last whole multiple of the alphabet is drawn again, so every character is as likely.
function randomString(length: number): string {
  const limit = 256 - (256 % unreserved.length);
  let out = "";
  while (out.length < length) {
    for (const value of crypto.getRandomValues(new Uint8Array(length - out.length))) {
      if (value < limit) out += unreserved[value % unreserved.length];
    }
  }
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

  // Why a sign-in can't start now: one failed a moment ago, or sign-in is off or can't receive this redirect.
  private refusal(): Error | undefined {
    const unavailable = !signInIsOn() || !isReceivable(this.options.redirectMethod);
    return recentFailure() ?? (unavailable ? failed(signInUnavailable(this.options.providerName)) : undefined);
  }

  async authorizationRequest(options: AuthorizationRequestOptions): Promise<AuthorizationRequest> {
    const refusal = this.refusal();
    if (refusal) throw refusal;
    const codeVerifier = randomString(64);
    const codeChallenge = await s256Challenge(codeVerifier);
    const state = stateForFloe(this.options.providerName);
    const redirectURI = redirectAddresses[this.options.redirectMethod ?? RedirectMethod.Web];
    return new AuthorizationRequest({ ...options, codeVerifier, codeChallenge, state, redirectURI });
  }

  async authorize(requestOrOptions: AuthorizationRequest | { url: string }): Promise<{ authorizationCode: string }> {
    const refusal = this.refusal();
    if (refusal) throw refusal;
    try {
      return await this.authorizeOnce(requestOrOptions);
    } catch (error) {
      throw failed(error);
    }
  }

  private async authorizeOnce(requestOrOptions: AuthorizationRequest | { url: string }): Promise<{ authorizationCode: string }> {
    const url = requestOrOptions instanceof AuthorizationRequest ? requestOrOptions.toURL() : requestOrOptions.url;
    const state = new URL(url).searchParams.get("state");
    if (!state) throw new Error("OAuth authorization URL has no state");
    const response = await request("oauth.authorize", { url, state, providerName: this.options.providerName });
    const callback = typeof response === "string" ? response : (response?.url as string);
    const params = new URL(callback).searchParams;
    const error = params.get("error");
    if (error) throw new Error(params.get("error_description") ?? error);
    if (params.get("state") !== state) throw new Error("OAuth state mismatch");
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
