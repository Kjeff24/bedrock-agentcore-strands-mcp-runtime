import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../environments/environment';

export interface AtlassianTokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
  scope?: string;
  refresh_token?: string;
  /** Epoch millis when the token was received in the browser. */
  received_at: number;
  /** Epoch millis when the access token will expire (approximate). */
  expires_at: number;
}

@Injectable({
  providedIn: 'root'
})
export class OAuthService {
  private readonly config = environment.atlassian;
  private readonly TOKEN_KEY = 'atlassian_token';
  private readonly TOKEN_PAYLOAD_KEY = 'atlassian_token_payload';

  constructor(private http: HttpClient) {}

  generateCodeVerifier(): string {
    const array = new Uint8Array(32);
    crypto.getRandomValues(array);
    return this.base64URLEncode(array.buffer);
  }

  async generateCodeChallenge(verifier: string): Promise<string> {
    const data = new TextEncoder().encode(verifier);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return this.base64URLEncode(digest);
  }

  generateState(): string {
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

  async startOAuthFlow(): Promise<void> {
    const state = this.generateState();
    const codeVerifier = this.generateCodeVerifier();
    const codeChallenge = await this.generateCodeChallenge(codeVerifier);
    
    sessionStorage.setItem('oauth_state', state);
    sessionStorage.setItem('code_verifier', codeVerifier);

    const params = new URLSearchParams({
      response_type: 'code',
      client_id: this.config.clientId,
      redirect_uri: window.location.origin + '/',
      scope: this.config.scopes,
      state: state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256'
    });

    window.location.href = `${this.config.authorizeUrl}?${params}`;
  }

  async exchangeCodeForToken(code: string, state: string): Promise<AtlassianTokenResponse> {
    const storedState = sessionStorage.getItem('oauth_state');
    const codeVerifier = sessionStorage.getItem('code_verifier');

    if (state !== storedState || !codeVerifier) {
      throw new Error('Invalid OAuth state');
    }

    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code: code,
      redirect_uri: window.location.origin + '/',
      code_verifier: codeVerifier,
      client_id: this.config.clientId
    });

    const response = await fetch(this.config.tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body
    });

    if (!response.ok) {
      throw new Error('Token exchange failed');
    }

    const data = await response.json();
    const now = Date.now();

    const tokenData: AtlassianTokenResponse = {
      access_token: data.access_token,
      token_type: data.token_type,
      expires_in: data.expires_in,
      scope: data.scope,
      refresh_token: data.refresh_token,
      received_at: now,
      expires_at: now + (data.expires_in ?? 0) * 1000
    };
    
    sessionStorage.removeItem('oauth_state');
    sessionStorage.removeItem('code_verifier');
    
    return tokenData;
  }

  /** Persist Atlassian token for the current browser session. */
  storeToken(token: AtlassianTokenResponse): void {
    sessionStorage.setItem(this.TOKEN_KEY, token.access_token);
    sessionStorage.setItem(this.TOKEN_PAYLOAD_KEY, JSON.stringify(token));
  }

  /** Get the raw token payload from storage, if present. */
  private getStoredPayload(): AtlassianTokenResponse | null {
    const raw = sessionStorage.getItem(this.TOKEN_PAYLOAD_KEY);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as AtlassianTokenResponse;
    } catch {
      return null;
    }
  }

  /**
   * Returns a non-expired access token if one exists.
   * If the token is expired or malformed, it is cleared and `undefined` is returned.
   */
  getValidAccessToken(): string | undefined {
    const rawToken = sessionStorage.getItem(this.TOKEN_KEY);
    if (!rawToken) {
      return undefined;
    }

    const payload = this.getStoredPayload();
    if (!payload || typeof payload.expires_at !== 'number') {
      // No metadata – assume valid for this session
      return rawToken;
    }

    const marginMs = 60_000; // 1 minute safety margin
    if (Date.now() > payload.expires_at - marginMs) {
      this.clearToken();
      return undefined;
    }

    return rawToken;
  }

  /** True if we currently have a valid Atlassian token. */
  isAtlassianAuthenticated(): boolean {
    return !!this.getValidAccessToken();
  }

  /** Clear any stored Atlassian token and metadata. */
  clearToken(): void {
    sessionStorage.removeItem(this.TOKEN_KEY);
    sessionStorage.removeItem(this.TOKEN_PAYLOAD_KEY);
  }
}
