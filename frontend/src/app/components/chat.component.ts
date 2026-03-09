import { Component, ElementRef, OnInit, ViewChild, inject } from '@angular/core';
import { OidcSecurityService } from 'angular-auth-oidc-client';
import { OAuthService, AtlassianTokenResponse } from '../services/oauth.service';
import { AgentService } from '../services/agent.service';
import { AgentResponse, ChatMessage } from '../models/chat.models';
import { environment } from '../../environments/environment';

@Component({
  selector: 'app-chat',
  templateUrl: './chat.component.html'
})
export class ChatComponent implements OnInit {
  @ViewChild('messageContainer') private messageContainer!: ElementRef<HTMLElement>;
  private readonly oidcSecurityService = inject(OidcSecurityService);

  messages: ChatMessage[] = [];
  currentMessage = '';
  loading = false;
  isAwsAuthenticated = false;
  isAtlassianAuthenticated = false;
  useStreaming = true;
  sessionId: string | undefined;

  constructor(
    private oauthService: OAuthService,
    private agentService: AgentService
  ) {}

  ngOnInit(): void {
    const path = window.location.pathname;
    const params = new URLSearchParams(window.location.search);

    if (path === '/callback') {
      // Cognito redirect — let the OIDC library see the URL as-is.
      this.initAwsAuth();
      this.handleCognitoCallback();
    } else if (path === '/' && params.has('code') && params.has('state')) {
      // Atlassian OAuth callback. Strip code/state from the URL BEFORE calling
      // checkAuth() so the OIDC library doesn't mistake Atlassian's params for
      // a Cognito auth callback and invalidate the existing Cognito session.
      window.history.replaceState({}, document.title, window.location.pathname);
      this.initAwsAuth();
      this.handleAtlassianCallback(params.get('code')!, params.get('state')!);
    } else {
      this.initAwsAuth();
    }

    this.isAtlassianAuthenticated = this.oauthService.isAtlassianAuthenticated();
  }

  loginAws(): void {
    this.oidcSecurityService.authorize();
  }

  logoutAws(): void {
    sessionStorage.clear();
    const { userPoolDomain, clientId, logoutUrl } = environment.cognito;
    window.location.href = `https://${userPoolDomain}/logout?client_id=${clientId}&logout_uri=${logoutUrl}`;
  }

  authenticateAtlassian(): void {
    this.oauthService.startOAuthFlow();
  }

  disconnectAtlassian(): void {
    this.oauthService.clearToken();
    this.isAtlassianAuthenticated = false;
  }

  async sendMessage(): Promise<void> {
    const text = this.currentMessage.trim();
    if (!text || !this.isAwsAuthenticated || this.loading) return;

    this.messages.push({ role: 'user', content: text });
    this.currentMessage = '';
    this.loading = true;
    this.scrollToBottom();

    // Re-evaluate Atlassian auth on each send so an expired token is caught
    // promptly and the user is prompted to reconnect.
    const atlassianToken = this.oauthService.getValidAccessToken();
    this.isAtlassianAuthenticated = !!atlassianToken;

    try {
      if (this.useStreaming) {
        this.sendStreaming(text, atlassianToken, this.sessionId);
      } else {
        this.sendNonStreaming(text, atlassianToken, this.sessionId);
      }
    } catch (error: any) {
      this.pushErrorMessage(error.message);
      this.loading = false;
    }
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  /** Enter sends, Shift+Enter inserts a newline. */
  onKeyDown(event: KeyboardEvent): void {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      this.sendMessage();
    }
  }

  private initAwsAuth(): void {
    this.oidcSecurityService.checkAuth().subscribe(({ isAuthenticated }) => {
      this.isAwsAuthenticated = isAuthenticated;
    });
    this.oidcSecurityService.isAuthenticated$.subscribe(({ isAuthenticated }) => {
      this.isAwsAuthenticated = isAuthenticated;
    });
    this.oidcSecurityService.userData$.subscribe(({ userData }) => {
      this.sessionId = userData?.sub;
    });
  }

  private handleCognitoCallback(): void {
    setTimeout(() => {
      this.oidcSecurityService.checkAuth().subscribe(({ isAuthenticated }) => {
        this.isAwsAuthenticated = isAuthenticated;
        if (isAuthenticated) {
          window.location.href = '/';
        }
      });
    }, 1000);
  }

  private async handleAtlassianCallback(code: string, state: string): Promise<void> {
    try {
      const token: AtlassianTokenResponse = await this.oauthService.exchangeCodeForToken(code, state);
      this.oauthService.storeToken(token);
      this.isAtlassianAuthenticated = this.oauthService.isAtlassianAuthenticated();
    } catch (error: any) {
      console.error('Atlassian OAuth callback failed:', error);
    }
  }

  private sendStreaming(prompt: string, atlassianToken?: string, sessionId?: string): void {
    this.messages.push({ role: 'assistant', content: '' });
    this.agentService.invokeAgentStream(prompt, atlassianToken, sessionId).subscribe({
      next: (chunk: string) => this.handleStreamChunk(chunk),
      error: (error) => {
        this.pushErrorMessage(error.message, true);
        this.loading = false;
      },
      complete: () => {
        this.loading = false;
        this.scrollToBottom();
      }
    });
  }

  private sendNonStreaming(prompt: string, atlassianToken?: string, sessionId?: string): void {
    this.agentService.invokeAgent(prompt, atlassianToken, sessionId).subscribe({
      next: (response: AgentResponse) => {
        this.messages.push({ role: 'assistant', content: this.extractResponseText(response) });
        this.loading = false;
        this.scrollToBottom();
      },
      error: (error) => {
        this.pushErrorMessage(error.message);
        this.loading = false;
      }
    });
  }

  private handleStreamChunk(chunk: string): void {
    try {
      const json = chunk.startsWith('data:') ? chunk.slice(5).trim() : chunk;
      if (!json) return;

      const event = JSON.parse(json);
      const last = this.messages[this.messages.length - 1];
      if (!last || last.role !== 'assistant') return;

      if (event.error) {
        last.content = `Error: ${event.error}`;
        return;
      }

      // Final aggregated message from backend
      if (event.message?.content && Array.isArray(event.message.content)) {
        const text = event.message.content
          .map((c: any) => c?.text ?? '')
          .filter(Boolean)
          .join('');
        if (text) last.content = text;
        return;
      }

      // Incremental text delta
      const deltaText = event.event?.contentBlockDelta?.delta?.text;
      if (typeof deltaText === 'string' && deltaText) {
        last.content += deltaText;
        this.scrollToBottom();
      }
    } catch {
      // Non-JSON chunk; ignore
    }
  }

  private extractResponseText(response: AgentResponse): string {
    const result = response?.result;
    if (!result) return 'No response received';
    if (typeof result === 'object' && Array.isArray(result.content)) {
      const text = result.content
        .map(c => c?.text ?? '')
        .filter(Boolean)
        .join('\n\n');
      return text || JSON.stringify(result);
    }
    return typeof result === 'string' ? result : JSON.stringify(result);
  }

  private pushErrorMessage(message: string, replaceLastAssistant = false): void {
    const errorMsg: ChatMessage = { role: 'assistant', content: `Error: ${message}` };
    if (replaceLastAssistant && this.messages.at(-1)?.role === 'assistant') {
      this.messages[this.messages.length - 1] = errorMsg;
    } else {
      this.messages.push(errorMsg);
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      const el = this.messageContainer?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }
}
