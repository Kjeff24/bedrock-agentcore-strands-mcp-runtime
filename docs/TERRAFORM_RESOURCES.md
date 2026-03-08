# AgentCore Terraform Resources

## Available Resources (as of Feb 2026)

### 1. `aws_bedrockagentcore_gateway`
Creates a Gateway for MCP protocol.

**Required:**
- `name` - Gateway name
- `role_arn` - IAM role ARN
- `authorizer_type` - `AWS_IAM` or `CUSTOM_JWT`
- `protocol_type` - `MCP`

**Optional:**
- `authorizer_configuration` - JWT config (required if `CUSTOM_JWT`)
- `protocol_configuration` - MCP-specific settings
- `interceptor_configuration` - Lambda interceptors

**Outputs:**
- `gateway_id` - Gateway identifier
- `gateway_url` - Gateway endpoint URL
- `gateway_arn` - Gateway ARN

### 2. `aws_bedrockagentcore_gateway_target`
Adds targets to a Gateway.

**Target Types:**
- `lambda` - Lambda function with tool schema
- `mcp_server` - External MCP server endpoint
- `open_api_schema` - OpenAPI-based API
- `smithy_model` - Smithy model-based API

**Authentication:**
- `gateway_iam_role {}` - Use Gateway's IAM role
- `api_key` - API key auth (requires credential provider)
- `oauth` - OAuth auth (requires IAM OIDC provider)

**MCP Server Constraint:**
- MCP server targets **only support OAuth** credential provider
- Cannot use `api_key` or `gateway_iam_role` with `mcp_server`

**Outputs:**
- `target_id` - Target identifier

### 3. `aws_bedrockagentcore_api_key_credential_provider`
Manages API key credentials for Gateway targets.

**Required:**
- `name` - Provider name

**Optional:**
- `api_key` - Plain API key (visible in logs)
- `api_key_wo` - Write-only API key (Terraform 1.11+)
- `api_key_wo_version` - Version number for updates

**Outputs:**
- `credential_provider_arn` - Provider ARN
- `api_key_secret_arn` - Secrets Manager secret ARN

## Not Available (Use AWS CLI)

- `aws_bedrockagentcore_runtime` - Use `aws bedrock-agentcore-control create-agent-runtime`
- `aws_bedrockagentcore_memory` - Use `aws bedrock-agentcore-control create-memory`
- OAuth credential provider - OAuth config is inline in `gateway_target` resource

## OAuth Limitations

**For MCP Server Targets:**
- Requires IAM OIDC Identity Provider with `.well-known/openid-configuration` endpoint
- GitHub OAuth is **not compatible** (no OIDC support)
- Must use OAuth providers that support OIDC (Google, Auth0, Okta, etc.)

**Workaround for GitHub:**
- Deploy GitHub MCP server as Lambda function
- Use `gateway_iam_role` authentication instead of OAuth
