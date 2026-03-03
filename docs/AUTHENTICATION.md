# MCP Server Authentication Options

The gateway supports three authentication methods for connecting to MCP servers:

## 1. API Key Authentication

Use when your MCP server requires an API key in headers or query parameters.

**Store API key in Secrets Manager:**
```bash
aws secretsmanager create-secret \
  --name mcp-server-api-key \
  --secret-string "your-api-key-here"
```

**Deploy with Terraform:**
```bash
cd infra/terraform/gateway

terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=API_KEY" \
  -var='mcp_api_key_config={secret_arn="arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-server-api-key",header_name="X-API-Key"}'
```

**Configuration:**
- `CredentialLocation`: HEADER or QUERY_PARAMETER
- `CredentialParameterName`: Header/query param name
- `CredentialPrefix`: Optional prefix (e.g., "Bearer")

## 2. OAuth2 Authentication

Use when your MCP server requires OAuth2 tokens.

**Deploy with Terraform:**
```bash
cd infra/terraform/gateway

terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='mcp_oauth_config={provider_vendor="GoogleOauth2",client_id="your-client-id",client_secret="your-client-secret",scopes=["read","write"]}'
```

**Grant Types:**
- `CLIENT_CREDENTIALS`: Service-to-service authentication
- `AUTHORIZATION_CODE`: User-delegated access

The workload identity is automatically created and used for OAuth flow.

## 3. IAM Authentication

Use when your MCP server accepts AWS SigV4 signed requests.

**Deploy with Terraform:**
```bash
cd infra/terraform/gateway

terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=IAM"
```

The gateway uses its IAM role to sign requests to your MCP server.

## Combining Multiple MCP Servers

To connect multiple MCP servers with different auth methods, you can deploy multiple gateway targets. Currently, the Terraform module supports one target per gateway. For multiple targets, deploy separate gateways or extend the module.

Your Strands agent connects to the gateway URL and gets tools from all configured MCP servers.
