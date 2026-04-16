# Frontend Environment Configuration

Copy the example files and configure with your values:

```bash
cp src/environments/environment.example.ts src/environments/environment.ts
cp src/environments/environment.prod.example.ts src/environments/environment.prod.ts
```

## Required Configuration

### Development (environment.ts)
- `YOUR_ATLASSIAN_CLIENT_ID` - Atlassian OAuth client ID
- `YOUR_AGENTCORE_RUNTIME_URL` - AgentCore Runtime invocation URL
- `USER_POOL_ID` - AWS Cognito User Pool ID
- `YOUR_COGNITO_CLIENT_ID` - Cognito App Client ID
- `YOUR_USER_POOL_DOMAIN` - Cognito User Pool domain

### Production (environment.prod.ts)
- Same as development but with production URLs and domains
- Update `redirectUrl` and `logoutUrl` to production domain

## Authentication Flow

This frontend uses `angular-auth-oidc-client` with AWS Cognito Hosted UI.

1. User clicks **Sign in with AWS Cognito**.
2. App redirects to Cognito Hosted UI (which may federate to Microsoft Entra ID).
3. Cognito redirects back to `/callback`.
4. App completes OIDC auth and then hard-redirects to `/`.

### Important Routes

- `/` - Main chat UI
- `/callback` - Cognito OIDC redirect callback

### Cognito App Client URL Requirements

Your Cognito App Client must include the exact frontend URLs:

- Callback URL: `http://localhost:4200/callback` (dev)
- Sign out URL: `http://localhost:4200/` (dev)

For production, replace with your deployed domain equivalents.

## Microsoft Federation Notes

If Cognito is configured with Microsoft as a social/enterprise IdP:

- Enable that IdP in the same Cognito App Client used by this frontend.
- Ensure redirect URLs match exactly between Cognito and this app.
- Keep OAuth response type as authorization code (`code`).

## Troubleshooting

### Login failed message on home page

If Cognito returns an OAuth error to `/callback` (for example `access_denied`), the app stores the error message and redirects back to `/`, where a login error banner is shown.

Common causes:

- Microsoft user is not linked/provisioned for the expected Cognito user pool flow.
- IdP is not enabled for the selected Cognito App Client.
- Callback URL mismatch (protocol/domain/path must be exact).
- User cancels login at the identity provider page.

## Setup

```bash
npm install
npm start  # Development
npm run build:prod  # Production
```
