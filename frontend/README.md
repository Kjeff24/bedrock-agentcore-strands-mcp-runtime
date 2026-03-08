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

## Setup

```bash
npm install
npm start  # Development
npm run build:prod  # Production
```
