export const environment = {
  production: false,
  atlassian: {
    authorizeUrl: 'https://mcp.atlassian.com/v1/authorize',
    tokenUrl: 'https://cf.mcp.atlassian.com/v1/token',
    scopes: 'openid email profile',
    clientId: 'szJj61dqE2kcouEe'
  },
  agentcore: {
    runtimeUrl: 'https://bedrock-agentcore.eu-west-1.amazonaws.com/runtimes/arn%3Aaws%3Abedrock-agentcore%3Aeu-west-1%3A517798689069%3Aruntime%2Fagentvault_runtime-m67Zlg5ZGs/invocations'
  },
  cognito: {
    authority: 'https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_Z0r3nDDaU',
    clientId: '1e5nr59tu2smdjmlbctebe3375',
    redirectUrl: 'http://localhost:8501/callback',
    logoutUrl: 'http://localhost:8501/',
    scope: 'openid profile email',
    userPoolDomain: 'agentvault-agent-517798689069-domain.auth.eu-west-1.amazoncognito.com'
  }
};
