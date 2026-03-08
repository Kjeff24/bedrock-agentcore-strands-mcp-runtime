# Atlassian MCP Integration

This guide shows how to integrate Atlassian's hosted MCP server with your AgentCore Runtime agent.

## Authentication Methods

The agent supports three authentication methods for Atlassian MCP:

### 1. Service Account API Key (Recommended for Production)

Best for automated/serverless scenarios.

**Environment Variables:**
```bash
ATLASSIAN_AUTH_TYPE=API_KEY
ATLASSIAN_API_KEY=your_service_account_api_key
```

**Setup:**
1. Ask your Atlassian admin to create a service account
2. Generate an API key with required scopes
3. Set the environment variables in your runtime deployment

### 2. Personal API Token

Best for development and testing.

**Environment Variables:**
```bash
ATLASSIAN_AUTH_TYPE=PERSONAL_TOKEN
ATLASSIAN_EMAIL=your.email@example.com
ATLASSIAN_PERSONAL_TOKEN=your_personal_api_token
```

**Setup:**
1. Create a [personal API token](https://id.atlassian.com/manage-profile/security/api-tokens?autofillToken&expiryDays=max&appId=mcp&selectedScopes=all)
2. Set the environment variables with your email and token

### 3. OAuth 2.1

Best for interactive user sessions (not yet implemented).

## Terraform Deployment

Update your runtime deployment to include Atlassian credentials:

```bash
cd infra/terraform/runtime

# For Service Account API Key
terraform apply \
  -var="container_image_uri=ACCOUNT.dkr.ecr.REGION.amazonaws.com/agentcore-strands-agent:latest" \
  -var='environment_variables={"ATLASSIAN_AUTH_TYPE":"API_KEY","ATLASSIAN_API_KEY":"your_key"}'

# For Personal Token
terraform apply \
  -var="container_image_uri=ACCOUNT.dkr.ecr.REGION.amazonaws.com/agentcore-strands-agent:latest" \
  -var='environment_variables={"ATLASSIAN_AUTH_TYPE":"PERSONAL_TOKEN","ATLASSIAN_EMAIL":"you@example.com","ATLASSIAN_PERSONAL_TOKEN":"your_token"}'
```

## Using with Gateway

You can use both Gateway and Atlassian MCP simultaneously:

```bash
terraform apply \
  -var="container_image_uri=..." \
  -var="gateway_id=your-gateway-id" \
  -var='environment_variables={"ATLASSIAN_AUTH_TYPE":"API_KEY","ATLASSIAN_API_KEY":"your_key"}'
```

The agent will initialize both MCP clients and make all tools available.

## Local Testing

```bash
# Set environment variables
export ATLASSIAN_AUTH_TYPE=PERSONAL_TOKEN
export ATLASSIAN_EMAIL=your.email@example.com
export ATLASSIAN_PERSONAL_TOKEN=your_token

# Run locally
python examples/agent.local.py
```

## Limitations

- Some tools may not be available with API token auth (vs OAuth)
- Tokens are not bound to a specific cloudId - must pass explicitly in requests
- No domain allowlist validation (governed by IP allowlist only)

## References

- [Atlassian MCP Authentication Guide](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/configuring-authentication-via-api-token/)
- [Supported Tools](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/)
