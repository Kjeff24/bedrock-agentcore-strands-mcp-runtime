import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { HttpClientModule } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { RouterModule, Routes } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthModule } from 'angular-auth-oidc-client';
import { MarkdownModule } from 'ngx-markdown';

import { AppComponent } from './app.component';
import { ChatComponent } from './components/chat.component';
import { environment } from '../environments/environment';

const routes: Routes = [
  { path: '', component: ChatComponent },
  { path: 'callback', component: ChatComponent },
  { path: '**', redirectTo: '' }
];

@NgModule({
  declarations: [
    AppComponent,
    ChatComponent
  ],
  imports: [
    BrowserModule,
    CommonModule,
    HttpClientModule,
    FormsModule,
    RouterModule.forRoot(routes),
    MarkdownModule.forRoot(),
    AuthModule.forRoot({
      config: {
        authority: environment.cognito.authority,
        redirectUrl: `${window.location.origin}${environment.cognito.redirectPath}`,
        postLogoutRedirectUri: `${window.location.origin}${environment.cognito.logoutPath}`,
        clientId: environment.cognito.clientId,
        scope: environment.cognito.scope,
        responseType: 'code',
        // Prevent the library from calling router.navigateByUrl() after the
        // callback — we handle the redirect ourselves in ChatComponent so that
        // a hard reload (window.location.href) clears stale in-memory state.
        triggerAuthorizationResultEvent: true,
        silentRenew: true,
        useRefreshToken: true,
        renewTimeBeforeTokenExpiresInSeconds: 30,
        ignoreNonceAfterRefresh: true,
        triggerRefreshWhenIdTokenExpired: false
      }
    })
  ],
  providers: [],
  bootstrap: [AppComponent]
})
export class AppModule { }
