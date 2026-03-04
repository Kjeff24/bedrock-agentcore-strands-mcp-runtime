export const environment = {
  production: true,
  atlassian: {
    authorizeUrl: 'https://mcp.atlassian.com/v1/authorize',
    tokenUrl: 'https://cf.mcp.atlassian.com/v1/token',
    scopes: 'openid email profile',
    clientId: 'szJj61dqE2kcouEe'
  },
  agentcore: {
    runtimeUrl: 'https://bedrock-agentcore.eu-west-1.amazonaws.com/runtimes/arn%3Aaws%3Abedrock-agentcore%3Aeu-west-1%3A517798689069%3Aruntime%2Fagentvault_runtime-5TeWDqEid1/invocations'
  },
  cognito: {
    authority: 'https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_88B5QpIVS',
    clientId: '4inps3v0edgrj3dpdhmpqtjprs',
    redirectUrl: 'https://your-production-domain.com/',
    logoutUrl: 'https://your-production-domain.com/',
    scope: 'openid profile email',
    userPoolDomain: 'YOUR_PRODUCTION_USER_POOL_DOMAIN'
  }
};
