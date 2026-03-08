export const environment = {
  production: true,
  atlassian: {
    authorizeUrl: 'https://mcp.atlassian.com/v1/authorize',
    tokenUrl: 'https://cf.mcp.atlassian.com/v1/token',
    scopes: 'openid email profile',
    clientId: 'YOUR_ATLASSIAN_CLIENT_ID'
  },
  agentcore: {
    runtimeUrl: 'https://bedrock-agentcore.your-region.amazonaws.com/runtimes/your-runtime-arn-url-encoded/invocations'
  },
  cognito: {
    authority: 'https://cognito-idp.REGION.amazonaws.com/USER_POOL_ID',
    clientId: 'YOUR_COGNITO_CLIENT_ID',
    redirectUrl: 'https://your-production-domain.com/',
    logoutUrl: 'https://your-production-domain.com/',
    scope: 'openid profile email',
    userPoolDomain: 'YOUR_PRODUCTION_USER_POOL_DOMAIN'
  }
};
