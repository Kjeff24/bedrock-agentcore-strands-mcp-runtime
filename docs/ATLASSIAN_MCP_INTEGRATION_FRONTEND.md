# Atlassian MCP Integration — Frontend (Angular)

This guide covers the Angular frontend side of the Atlassian OAuth 2.0 (PKCE) flow: how the user token is obtained, stored, validated, and forwarded to the AgentCore Runtime backend.

For how the backend receives and uses, see [ATLASSIAN_MCP_INTEGRATION_BACKEND.md](ATLASSIAN_MCP_INTEGRATION_BACKEND.md).

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Environment Configuration](#environment-configuration)
4. [OAuth Flow — Step by Step](#oauth-flow--step-by-step)
   - [Step 1: Initiate the flow](#step-1-initiate-the-flow)
   - [Step 2: Handle the callback](#step-2-handle-the-callback)
   - [Step 3: Exchange code for token](#step-3-exchange-code-for-token)
   - [Step 4: Store the token](#step-4-store-the-token)
5. [Token Lifecycle Management](#token-lifecycle-management)
   - [Expiry detection](#expiry-detection)
   - [Connecting and disconnecting](#connecting-and-disconnecting)
6. [Forwarding the Token to the Backend](#forwarding-the-token-to-the-backend)
7. [Cognito Session Conflict — Critical Detail](#cognito-session-conflict--critical-detail)
8. [References](#references)

---

## Overview

The frontend performs the full OAuth 2.0 Authorization Code + PKCE flow **directly with Atlassian** — the AgentCore Runtime never participates in authentication. Once the user grants access, the frontend holds a short-lived `access_token`. This token is included in every request to the runtime, which forwards it as a Bearer token to Atlassian's MCP server.

```
┌──────────────────┐   1. Redirect to Atlassian   ┌──────────────────────┐
│  Angular App     │──────────────────────────────▶│  Atlassian Auth      │
│                  │◀──────────────────────────────│  (authorize endpoint)│
│                  │   2. Redirect back: ?code=&state=                    │
│                  │                               └──────────────────────┘
│                  │   3. POST to token endpoint   ┌──────────────────────┐
│                  │──────────────────────────────▶│  Atlassian Token     │
│                  │◀──────────────────────────────│  (token endpoint)    │
│                  │   4. { access_token, ... }    └──────────────────────┘
│                  │
│                  │   5. POST /invocations
│                  │   { prompt, atlassianToken }  ┌──────────────────────┐
│                  │──────────────────────────────▶│  AgentCore Runtime   │
│                  │◀──────────────────────────────│  (Strands Agent)     │
└──────────────────┘   6. Agent response           └──────────────────────┘
```

---

## Prerequisites

- Angular 17+
- `angular-auth-oidc-client` (for Cognito session management — separate from Atlassian OAuth)
- A `clientId` obtained via Dynamic Client Registration against `https://cf.mcp.atlassian.com/v1/register` (see [Environment Configuration](#environment-configuration))
  - Callback URL registered as your app's origin + `/` (e.g. `http://localhost:8501/`)

---

## Environment Configuration

All Atlassian OAuth parameters live in `src/environments/environment.ts`:

```typescript
export const environment = {
  atlassian: {
    clientId:             'YOUR_ATLASSIAN_CLIENT_ID',
    discoveryEndpoint:    'https://mcp.atlassian.com/.well-known/oauth-authorization-server',
    registrationEndpoint: 'https://cf.mcp.atlassian.com/v1/register',
    authorizeUrl:         'https://mcp.atlassian.com/v1/authorize',
    tokenUrl:             'https://cf.mcp.atlassian.com/v1/token',
    scopes:               'openid email profile'
  },
  agentcore: {
    runtimeUrl: 'YOUR_AGENTCORE_RUNTIME_INVOCATION_URL'
  },
  // ... Cognito config
};
```

| Parameter              | Value                                                                  |
|------------------------|------------------------------------------------------------------------|
| `discoveryEndpoint`    | `https://mcp.atlassian.com/.well-known/oauth-authorization-server`    |
| `registrationEndpoint` | `https://cf.mcp.atlassian.com/v1/register`                            |
| `authorizeUrl`         | `https://mcp.atlassian.com/v1/authorize`                              |
| `tokenUrl`             | `https://cf.mcp.atlassian.com/v1/token`                               |
| `scopes`               | Space-separated list of scopes your app needs                          |
| `clientId`             | From your app registration — see below                                |

### Dynamic Client Registration

Atlassian supports [OAuth 2.0 Dynamic Client Registration (RFC 7591)](https://datatracker.ietf.org/doc/html/rfc7591). Instead of pre-registering a `clientId` on the developer portal, you can register programmatically against the `registrationEndpoint`:

```bash
curl -s -X POST https://cf.mcp.atlassian.com/v1/register \
  -H 'Content-Type: application/json' \
  -d '{
    "client_name":                "My AgentCore App",
    "redirect_uris":              ["http://localhost:8501/"],
    "grant_types":                ["authorization_code", "refresh_token"],
    "response_types":             ["code"],
    "token_endpoint_auth_method": "none",
    "scope":                      "openid email profile"
  }'
```

The response includes a `client_id` you can set in `environment.ts`.

### Discovering Endpoints

The discovery endpoint returns the full OAuth server metadata (authorization endpoint, token endpoint, supported scopes, etc.):

```bash
curl -s https://mcp.atlassian.com/.well-known/oauth-authorization-server | jq .
```

> The redirect URI is always `window.location.origin + '/'` — set the same value in your Atlassian app's allowed callbacks.

---

## OAuth Flow — Step by Step

These four steps make up the complete PKCE flow. The code below is the full implementation — copy it into your project as-is.

### Data types

```typescript
export interface AtlassianTokenResponse {
  access_token:  string;
  token_type:    string;
  expires_in:    number;
  scope?:        string;
  refresh_token?: string;
  /** Epoch ms when the access token was received in the browser. */
  received_at:   number;
  /** Epoch ms when the access token will expire (approximate). */
  expires_at:    number;
}
```

### Step 1: Initiate the flow

Called when the user clicks "Connect Atlassian". Generates PKCE parameters, stores them in `sessionStorage` so they survive the redirect, then navigates to Atlassian's authorization endpoint.

```typescript
@Injectable({ providedIn: 'root' })
export class OAuthService {
  private readonly config   = environment.atlassian;
  private readonly TOKEN_KEY         = 'atlassian_token';
  private readonly TOKEN_PAYLOAD_KEY = 'atlassian_token_payload';

  // ── PKCE helpers ───────────────────────────────────────────────

  private generateCodeVerifier(): string {
    const array = new Uint8Array(32);
    crypto.getRandomValues(array);
    return this.base64URLEncode(array.buffer);
  }

  private async generateCodeChallenge(verifier: string): Promise<string> {
    const data   = new TextEncoder().encode(verifier);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return this.base64URLEncode(digest);
  }

  private generateState(): string {
    const array = new Uint8Array(16);
    crypto.getRandomValues(array);
    return btoa(String.fromCharCode(...array));
  }

  private base64URLEncode(buffer: ArrayBuffer): string {
    return btoa(String.fromCharCode(...new Uint8Array(buffer)))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  }

  // ── Step 1: redirect to Atlassian ──────────────────────────────

  async startOAuthFlow(): Promise<void> {
    const state         = this.generateState();
    const codeVerifier  = this.generateCodeVerifier();
    const codeChallenge = await this.generateCodeChallenge(codeVerifier);

    // Persist for validation after the redirect comes back
    sessionStorage.setItem('oauth_state',    state);
    sessionStorage.setItem('code_verifier',  codeVerifier);

    const params = new URLSearchParams({
      response_type:         'code',
      client_id:             this.config.clientId,
      redirect_uri:          window.location.origin + '/',
      scope:                 this.config.scopes,        // 'openid email profile'
      state,
      code_challenge:        codeChallenge,
      code_challenge_method: 'S256'
    });

    window.location.href = `${this.config.authorizeUrl}?${params}`;
    // → browser navigates away; Atlassian redirects back to /?code=…&state=…
  }
```

### Step 2: Handle the callback

Atlassian redirects back to `/?code=<auth_code>&state=<nonce>`. Detect this in the root component's `ngOnInit()`.

> **Critical ordering constraint:** `window.history.replaceState` **must** run before calling `checkAuth()` (Cognito's OIDC library). If `checkAuth()` sees `?code=&state=` it will interpret them as a Cognito callback, fail validation, and mark the Cognito session unauthenticated. See [Cognito Session Conflict](#cognito-session-conflict--critical-detail).

```typescript
ngOnInit(): void {
  const path   = window.location.pathname;
  const params = new URLSearchParams(window.location.search);

  if (path === '/' && params.has('code') && params.has('state')) {
    // ① Strip Atlassian's ?code&state from the URL FIRST
    window.history.replaceState({}, document.title, window.location.pathname);
    // ② Now it is safe to let Cognito run checkAuth()
    this.initAwsAuth();
    // ③ Exchange the auth code for an Atlassian token
    this.handleAtlassianCallback(params.get('code')!, params.get('state')!);
  } else {
    this.initAwsAuth();
  }

  this.isAtlassianAuthenticated = this.oauthService.isAtlassianAuthenticated();
}

private async handleAtlassianCallback(code: string, state: string): Promise<void> {
  try {
    const token = await this.oauthService.exchangeCodeForToken(code, state);
    this.oauthService.storeToken(token);
    this.isAtlassianAuthenticated = this.oauthService.isAtlassianAuthenticated();
  } catch (error: any) {
    console.error('Atlassian OAuth callback failed:', error);
  }
}
```

### Step 3: Exchange code for token

POSTs to Atlassian's token endpoint with the authorization code and the PKCE `code_verifier`. Validates the `state` parameter first to prevent CSRF / replay attacks.

```typescript
  async exchangeCodeForToken(code: string, state: string): Promise<AtlassianTokenResponse> {
    const storedState  = sessionStorage.getItem('oauth_state');
    const codeVerifier = sessionStorage.getItem('code_verifier');

    if (state !== storedState || !codeVerifier) {
      throw new Error('Invalid OAuth state — possible CSRF or replay attack');
    }

    const body = new URLSearchParams({
      grant_type:    'authorization_code',
      code,
      redirect_uri:  window.location.origin + '/',
      code_verifier: codeVerifier,     // proves this is the same client that started the flow
      client_id:     this.config.clientId
    });

    const response = await fetch(this.config.tokenUrl, {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    if (!response.ok) {
      throw new Error(`Token exchange failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    const now  = Date.now();

    // Clean up PKCE secrets — they are single-use
    sessionStorage.removeItem('oauth_state');
    sessionStorage.removeItem('code_verifier');

    return {
      access_token:  data.access_token,
      token_type:    data.token_type,
      expires_in:    data.expires_in,
      scope:         data.scope,
      refresh_token: data.refresh_token,
      received_at:   now,
      expires_at:    now + (data.expires_in ?? 0) * 1000   // convert seconds → epoch ms
    };
  }
```

### Step 4: Store the token

Persists the token in `sessionStorage` (never `localStorage` — session-scoped storage is automatically cleared when the tab closes, limiting the exposure window of a stolen token).

```typescript
  storeToken(token: AtlassianTokenResponse): void {
    sessionStorage.setItem(this.TOKEN_KEY,         token.access_token);
    sessionStorage.setItem(this.TOKEN_PAYLOAD_KEY, JSON.stringify(token));
    // Two keys:
    //   TOKEN_KEY         → raw access_token string, for fast lookup
    //   TOKEN_PAYLOAD_KEY → full response including expires_at, for expiry detection
  }
```

---

## Token Lifecycle Management

### Expiry detection

Before each agent request, retrieve the token through `getValidAccessToken()` which enforces a 1-minute safety margin before the stated expiry:

```typescript
  private getStoredPayload(): AtlassianTokenResponse | null {
    const raw = sessionStorage.getItem(this.TOKEN_PAYLOAD_KEY);
    if (!raw) return null;
    try   { return JSON.parse(raw) as AtlassianTokenResponse; }
    catch { return null; }
  }

  /**
   * Returns a valid, non-expired access token, or undefined if none exists.
   * Automatically clears an expired token so the UI reverts to "Connect Atlassian".
   */
  getValidAccessToken(): string | undefined {
    const rawToken = sessionStorage.getItem(this.TOKEN_KEY);
    if (!rawToken) return undefined;

    const payload = this.getStoredPayload();
    if (!payload || typeof payload.expires_at !== 'number') {
      return rawToken;   // no expiry metadata — treat as valid for this session
    }

    const marginMs = 60_000;   // 1-minute safety buffer
    if (Date.now() > payload.expires_at - marginMs) {
      this.clearToken();        // expired — remove and force re-authentication
      return undefined;
    }

    return rawToken;
  }

  isAtlassianAuthenticated(): boolean {
    return !!this.getValidAccessToken();
  }

  clearToken(): void {
    sessionStorage.removeItem(this.TOKEN_KEY);
    sessionStorage.removeItem(this.TOKEN_PAYLOAD_KEY);
  }
}  // end OAuthService
```

### Connecting and disconnecting

Wire the service methods to UI events in your component:

```typescript
// Re-check token validity on every message send (catches expiry mid-session)
async sendMessage(): Promise<void> {
  const atlassianToken = this.oauthService.getValidAccessToken();
  this.isAtlassianAuthenticated = !!atlassianToken;
  // ... proceed to invoke agent
}

// "Connect Atlassian" button
authenticateAtlassian(): void {
  this.oauthService.startOAuthFlow();
}

// Disconnect (×) button — clears token and reverts UI
disconnectAtlassian(): void {
  this.oauthService.clearToken();
  this.isAtlassianAuthenticated = false;
}
```

---

## Forwarding the Token to the Backend

Include the token in each request payload to the AgentCore Runtime. The runtime extracts it and uses it to authenticate against Atlassian's MCP server — it never touches the `Authorization` header for Atlassian.

```typescript
@Injectable({ providedIn: 'root' })
export class AgentService {
  private readonly oidcSecurityService = inject(OidcSecurityService);
  private readonly runtimeUrl = environment.agentcore.runtimeUrl;

  constructor(private http: HttpClient) {}

  /**
   * Streaming invocation. Yields raw newline-delimited JSON event strings.
   *
   * @param prompt         - The user's message
   * @param atlassianToken - Short-lived Atlassian access_token from OAuthService
   * @param sessionId      - Stable user identifier (e.g. Cognito sub) for memory isolation
   */
  invokeAgentStream(prompt: string, atlassianToken?: string, sessionId?: string): Observable<string> {
    const payload: Record<string, any> = { input: { prompt } };
    if (atlassianToken) payload['atlassianToken'] = atlassianToken;
    if (sessionId)      payload['sessionId']      = sessionId;

    return this.oidcSecurityService.getAccessToken().pipe(
      switchMap(cognitoToken =>
        new Observable<string>(observer => {
          fetch(this.runtimeUrl, {
            method:  'POST',
            headers: {
              // Cognito JWT — authorises the caller against the AgentCore Runtime's
              // API Gateway or ALB listener. Not forwarded to Atlassian.
              'Authorization': `Bearer ${cognitoToken}`,
              'Content-Type':  'application/json',
              'Accept':        'application/json, text/event-stream'
              // atlassianToken travels INSIDE the JSON body, not in headers
            },
            body: JSON.stringify(payload)
          })
            .then(res  => this.readStream(res, observer))
            .catch(err => observer.error(err));

          return () => {};   // teardown — nothing to cancel for fetch
        })
      )
    );
  }

  /** Non-streaming variant for environments that don't support SSE. */
  invokeAgent(prompt: string, atlassianToken?: string, sessionId?: string): Observable<any> {
    const payload: Record<string, any> = { input: { prompt } };
    if (atlassianToken) payload['atlassianToken'] = atlassianToken;
    if (sessionId)      payload['sessionId']      = sessionId;

    return this.oidcSecurityService.getAccessToken().pipe(
      switchMap(cognitoToken => {
        const headers = new HttpHeaders({
          'Authorization': `Bearer ${cognitoToken}`,
          'Content-Type':  'application/json'
        });
        return this.http.post(this.runtimeUrl, payload, { headers });
      })
    );
  }

  /** Reads a newline-delimited SSE stream and emits each non-empty line. */
  private readStream(
    response: Response,
    observer: { next: (v: string) => void; error: (e: any) => void; complete: () => void }
  ): void {
    if (!response.body) {
      observer.error(new Error('Streaming not supported by server'));
      return;
    }

    const reader  = response.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let   buffer  = '';

    const read = (): void => {
      reader.read().then(({ done, value }) => {
        if (done) {
          if (buffer.trim()) observer.next(buffer.trim());
          observer.complete();
          return;
        }

        buffer += decoder.decode(value, { stream: true });

        let idx: number;
        while ((idx = buffer.indexOf('\n')) !== -1) {
          const line = buffer.slice(0, idx).trim();
          buffer = buffer.slice(idx + 1);
          if (line) observer.next(line);
        }

        read();
      }).catch(err => observer.error(err));
    };

    read();
  }
}
```

**Two separate tokens on every request:**

| Location | Token | Purpose |
|---|---|---|
| `Authorization` header | Cognito JWT (`id_token` / `access_token`) | Authenticates the caller to the AgentCore Runtime (API Gateway / ALB) |
| `payload.atlassianToken` | Atlassian `access_token` | Forwarded by the runtime inside the `Authorization: Bearer` header to Atlassian's MCP server |

**`sessionId`** is the Cognito user's `sub` claim — a stable, unique, immutable identifier per user. Populate it from `oidcSecurityService.userData$`:

```typescript
sessionId: string | undefined;

private initAwsAuth(): void {
  this.oidcSecurityService.isAuthenticated$.subscribe(({ isAuthenticated }) => {
    this.isAwsAuthenticated = isAuthenticated;
  });
  // Capture the Cognito sub as session ID for memory isolation on the backend
  this.oidcSecurityService.userData$.subscribe(({ userData }) => {
    this.sessionId = userData?.sub;
  });
}
```

---

## Cognito Session Conflict — Critical Detail

Both Cognito (via `angular-auth-oidc-client`) and Atlassian use OAuth Authorization Code redirects back to the same origin with `?code=&state=` query parameters. If Cognito's `checkAuth()` runs while Atlassian's callback parameters are still in the URL, the OIDC library:

1. Sees `?code=&state=`
2. Attempts to validate them as a Cognito authorization code
3. Fails (wrong issuer, wrong nonce)
4. Marks the Cognito session as **unauthenticated**, logging the user out

**The fix** is to call `window.history.replaceState` to clean the URL **before** `checkAuth()` is ever called:

```typescript
// ngOnInit — Atlassian callback branch
window.history.replaceState({}, document.title, window.location.pathname); // ← strip ?code&state first
this.initAwsAuth();                                                          // ← then call checkAuth()
this.handleAtlassianCallback(params.get('code')!, params.get('state')!);
```

Order matters. Never call `checkAuth()` before cleaning the URL on the Atlassian callback path.

---

## References

- [Atlassian Remote MCP Server](https://support.atlassian.com/atlassian-rovo-mcp-server/)
- [OAuth 2.0 Dynamic Client Registration — RFC 7591](https://datatracker.ietf.org/doc/html/rfc7591)
- [Atlassian OAuth Server Discovery](https://mcp.atlassian.com/.well-known/oauth-authorization-server)
- [angular-auth-oidc-client](https://nice-hill-002425310.azurestaticapps.net/)
