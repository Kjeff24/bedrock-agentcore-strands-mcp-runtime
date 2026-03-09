import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { OidcSecurityService } from 'angular-auth-oidc-client';
import { switchMap } from 'rxjs/operators';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class AgentService {
  private readonly oidcSecurityService = inject(OidcSecurityService);
  private readonly runtimeUrl = environment.agentcore.runtimeUrl;

  constructor(private http: HttpClient) {}

  invokeAgent(prompt: string, atlassianToken?: string, sessionId?: string): Observable<any> {
    const payload: any = {
      input: { prompt }
    };

    if (atlassianToken) {
      payload.atlassianToken = atlassianToken;
    }
    if (sessionId) {
      payload.sessionId = sessionId;
    }

    return this.oidcSecurityService.getAccessToken().pipe(
      switchMap(token => {
        const headers = new HttpHeaders({
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        });

        return this.http.post(this.runtimeUrl, payload, { headers });
      })
    );
  }

  /**
   * Streaming invocation using Fetch + ReadableStream.
   * Exposes a stream of raw JSON event strings from the backend.
   */
  invokeAgentStream(prompt: string, atlassianToken?: string, sessionId?: string): Observable<string> {
    const payload: any = { input: { prompt } };
    if (atlassianToken) payload.atlassianToken = atlassianToken;
    if (sessionId) payload.sessionId = sessionId;

    return this.oidcSecurityService.getAccessToken().pipe(
      switchMap(token =>
        new Observable<string>(observer => {
          fetch(this.runtimeUrl, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${token}`,
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream'
            },
            body: JSON.stringify(payload)
          })
            .then(response => this.readStream(response, observer))
            .catch(err => observer.error(err));

          return () => {};
        })
      )
    );
  }

  /** Reads a newline-delimited stream and emits each non-empty line. */
  private readStream(
    response: Response,
    observer: { next: (v: string) => void; error: (e: any) => void; complete: () => void }
  ): void {
    if (!response.body) {
      observer.error(new Error('Streaming not supported by server'));
      return;
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';

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
