# Connecting Strands Agent (AgentCore Runtime) to AgentCore Gateway

> **Note:** The AgentCore Gateway is not currently deployed in this project. This document is kept as a reference for future use. The runtime currently connects directly to the Atlassian MCP server without a gateway intermediary.

## Architecture Overview

```
┌─────────────────────┐
│  Strands Agent      │  ← Your agent code
│  (AgentCore Runtime)│
└──────────┬──────────┘
           │ MCP over HTTP
           │ (connects to gateway)
           ▼
┌─────────────────────┐
│  AgentCore Gateway  │  ← Exposes MCP endpoint
│  (MCP Server)       │
└──────────┬──────────┘
           │ Auth: IAM/OAuth/API Key
           │ (gateway authenticates to targets)
           ▼
┌─────────────────────┐
│  MCP Server/Tool    │  ← External services
│  (Target)           │
└─────────────────────┘
```

**Key Point:** The Gateway IS an MCP server that your agent connects to. The Gateway then routes requests to backend MCP servers/tools.

## Step 1: Deploy Gateway with Backend Targets

### Using Terraform

```bash
cd infra/terraform/gateway

# For API Key authentication
terraform apply \
  -var="gateway_name=my-gateway" \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://mcp-server.example.com" \
  -var="mcp_auth_type=API_KEY" \
  -var='mcp_api_key_config={value="your-api-key"}'

# For OAuth authentication
terraform apply \
  -var="gateway_name=my-gateway" \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://mcp-server.example.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='mcp_oauth_config={
    provider_vendor="GoogleOauth2",
    client_id="your-client-id",
    client_secret="your-client-secret",
    scopes=["openid","profile"]
  }'

# Get gateway URL
terraform output gateway_url
```

### Get Gateway URL

```bash
cd infra/terraform/gateway
terraform output gateway_url
```

## Step 2: Deploy Runtime with Gateway Connection

### Terraform

```bash
cd infra/terraform/runtime

terraform apply \
  -var="runtime_name=my-strands-agent" \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/strands-agent:latest" \
  -var='environment_variables={
    GATEWAY_URL="https://gateway-id.bedrock-agentcore.us-east-1.amazonaws.com"
  }'
```



## Step 3: Configure Strands Agent to Connect to Gateway

The Gateway exposes an MCP-over-HTTP endpoint. Your agent connects to this endpoint.

### Get Gateway URL

```bash
cd infra/terraform/gateway
GATEWAY_URL=$(terraform output -raw gateway_url)

echo $GATEWAY_URL
# Output: https://gateway-abc123.bedrock-agentcore.us-east-1.amazonaws.com
```

### In Your Agent Code (agent.py)

**Option 1: AWS_IAM Authentication (Default)**
```python
import os
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient
from mcp.client.streamable_http import streamablehttp_client

import os
from strands import Agent
from strands.models.bedrock import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from bedrock_agentcore.runtime import BedrockAgentCoreApp

GATEWAY_URL = os.environ["GATEWAY_URL"]
MODEL_REGION = os.environ.get("MODEL_REGION", "eu-west-1")

app = BedrockAgentCoreApp()

# The gateway transport uses AWS IAM SigV4 — the runtime's IAM role
# is used automatically. No tokens or credentials needed in code.
def _gateway_transport():
    return aws_iam_streamablehttp_client(
        endpoint=GATEWAY_URL,
        aws_region=MODEL_REGION,
        aws_service="bedrock-agentcore",
    )

bedrock_model = BedrockModel(
    model_id="eu.anthropic.claude-sonnet-4-20250514-v1:0",
    region_name=MODEL_REGION,
)

# MCPClient must be in tools= at Agent() construction time.
# Strands discovers tool definitions at construction — not lazily.
agent = Agent(
    model=bedrock_model,
    tools=[MCPClient(_gateway_transport)],
)

@app.entrypoint
def invoke(payload: dict) -> dict:
    result = agent(payload["prompt"])
    return {"result": result.message}

@app.entrypoint
async def invoke_stream(payload: dict, context=None):
    async for event in agent.stream_async(payload["prompt"]):
        yield event

@app.get("/ping")
async def ping():
    return {"status": "healthy"}

@app.post("/invocations")
async def invocations(request: Request):
    body = await request.json()
    user_input = body.get("input", "")
    model_id = body.get("model_id", "us.anthropic.claude-sonnet-4-20250514-v1:0")
    
    result = agent_runner.run(user_input, model_id)
    return {"output": result}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

### Environment Variables in Runtime

```hcl
cd infra/terraform/runtime

terraform apply \
  -var="runtime_name=my-strands-agent" \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/strands-agent:latest" \
  -var='environment_variables={
    GATEWAY_URL="https://gateway-abc123.bedrock-agentcore.us-east-1.amazonaws.com"
  }'
```

The gateway connection always uses AWS IAM SigV4 signing via the runtime's attached IAM role. No `GATEWAY_AUTH_TYPE` or JWT token env vars are needed.



## Gateway Authentication Types

The Gateway's `authorizer_type` determines how clients authenticate:

### 1. AWS_IAM (Default - Recommended)
- **Client uses:** AWS SigV4 signing with IAM credentials
- **No tokens needed:** Runtime's IAM role is used automatically
- **Setup:** Attach policy to Runtime IAM role:
  ```json
  {
    "Effect": "Allow",
    "Action": "bedrock-agentcore:InvokeGateway",
    "Resource": "arn:aws:bedrock-agentcore:*:*:gateway/my-gateway-*"
  }
  ```

### 2. CUSTOM_JWT
- **Client uses:** Bearer token (JWT)
- **Requires:** JWT from identity provider (Cognito, Auth0, etc.)
- **Setup:** Configure `jwt_config` when deploying gateway
- **Usage:**
  ```python
  headers = {"Authorization": f"Bearer {jwt_token}"}
  transport = streamable_http_client(gateway_url, headers=headers)
  ```

## OAuth Authentication Flow

### How OAuth Works in This Architecture

**Two separate authentication layers:**

1. **Agent → Gateway:** Uses IAM or JWT (based on gateway's `authorizer_type`)
2. **Gateway → Backend:** Uses OAuth/API Key/IAM (based on target configuration)

### OAuth Flow (Gateway to Backend)

```
1. Agent → Gateway: "Call tool X" (IAM SigV4 or JWT)
2. Gateway checks: Do I have OAuth token for backend?
3. If NO token:
   ┌──────────────────────────────────────────────┐
   │ Gateway → OAuth Provider: Get authorization  │
   │ OAuth Provider: Returns auth URL             │
   │ User (if interactive): Logs in via browser   │
   │ OAuth Provider → Gateway: Auth code          │
   │   (via callback URL)                         │
   │ Gateway → OAuth Provider: Exchange code      │
   │ OAuth Provider → Gateway: Access token       │
   │ Gateway: Caches token                        │
   └──────────────────────────────────────────────┘
4. Gateway → Backend: Request with OAuth token
5. Backend → Gateway: Response
6. Gateway → Agent: Tool result
```

### OAuth Callback URL

The OAuth callback URL is automatically configured:
```
https://bedrock-agentcore.{region}.amazonaws.com/identities/oauth2/callback
```

**Important:** Register this callback URL in your OAuth provider (Google, GitHub, etc.)

### Example: Google OAuth Setup

1. **Create OAuth Client in Google Cloud Console:**
   - Go to APIs & Services → Credentials
   - Create OAuth 2.0 Client ID
   - Add authorized redirect URI:
     ```
     https://bedrock-agentcore.us-east-1.amazonaws.com/identities/oauth2/callback
     ```

2. **Deploy Gateway with Google OAuth:**
   ```bash
   terraform apply \
     -var="mcp_auth_type=OAUTH" \
     -var='mcp_oauth_config={
       provider_vendor="GoogleOauth2",
       client_id="123456789.apps.googleusercontent.com",
       client_secret="GOCSPX-xxxxxxxxxxxxx",
       scopes=["openid","email","profile"]
     }'
   ```

3. **First Request Flow:**
   - Agent makes first request to gateway
   - Gateway initiates OAuth flow (transparent to agent)
   - User authenticates via browser (if interactive)
   - Gateway caches token for subsequent requests
   - Agent receives tool response

### Testing the Connection

**For AWS_IAM authorizer (default):**
```python
# test_gateway_connection.py
import os
import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from mcp.client.streamable_http import streamablehttp_client
from mcp import ClientSession

async def test_gateway():
    gateway_url = os.environ["GATEWAY_URL"]
    region = os.environ.get("AWS_REGION", "us-east-1")
    
    # IAM credentials from Runtime role are used automatically
    async with streamablehttp_client(gateway_url) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print(f"Available tools: {[t.name for t in tools.tools]}")

if __name__ == "__main__":
    import asyncio
    asyncio.run(test_gateway())
```

**For CUSTOM_JWT authorizer:**
```python
async def test_gateway_jwt():
    gateway_url = os.environ["GATEWAY_URL"]
    jwt_token = os.environ["JWT_TOKEN"]  # From Cognito/Auth0/etc
    
    headers = {"Authorization": f"Bearer {jwt_token}"}
    
    async with streamablehttp_client(gateway_url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print(f"Available tools: {[t.name for t in tools.tools]}")
```

## Step 4: IAM Permissions

### Runtime IAM Role Needs:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:InvokeGateway",
        "bedrock-agentcore:ListGatewayTargets"
      ],
      "Resource": "arn:aws:bedrock-agentcore:*:*:gateway/*"
    }
  ]
}
```

### Gateway IAM Role Needs:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:*"
    }
  ]
}
```

## Testing the Integration

### 1. Test Gateway Endpoint

**With AWS_IAM authorizer (default):**
```bash
GATEWAY_URL=$(terraform output -raw gateway_url)

# Uses AWS credentials from your environment
curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  --aws-sigv4 "aws:amz:us-east-1:bedrock-agentcore" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

**With CUSTOM_JWT authorizer:**
```bash
GATEWAY_URL=$(terraform output -raw gateway_url)
JWT_TOKEN="eyJhbGc..."  # From your identity provider

curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### 2. Test from Runtime Container
```bash
# Inside your container (IAM auth)
export GATEWAY_URL="https://gateway-abc123.bedrock-agentcore.us-east-1.amazonaws.com"
python test_gateway_connection.py
```

### 3. Invoke Runtime
```bash
curl -X POST https://runtime-xyz.bedrock-agentcore.us-east-1.amazonaws.com/invocations \
  -H "Content-Type: application/json" \
  -d '{"input":"What tools are available?"}'
```

## Troubleshooting

### Gateway Returns 401 Unauthorized
- Check OAuth credentials are correct
- Verify callback URL is registered with OAuth provider
- Check API key is in Secrets Manager (for API_KEY auth)

### Runtime Can't Connect to Gateway
- Verify network configuration (VPC/public)
- Check IAM role has `bedrock-agentcore:InvokeGateway` permission
- Ensure gateway URL is correct in environment variables

### OAuth Redirect Not Working
- Confirm callback URL matches exactly:
  `https://bedrock-agentcore.{region}.amazonaws.com/identities/oauth2/callback`
- Check OAuth provider allows the callback URL
- Verify scopes are correct for the OAuth provider

## Complete Example

See the full working implementation in the repository:
- [src/agentcore_strands/agent.py](../src/agentcore_strands/agent.py) - Runtime entrypoints
- [src/agentcore_strands/agent_factory.py](../src/agentcore_strands/agent_factory.py) - Agent + MCPClient construction
- [src/agentcore_strands/transport.py](../src/agentcore_strands/transport.py) - Gateway and Atlassian transports
- [Dockerfile](../Dockerfile) - Container configuration
- [infra/terraform/](../infra/terraform/) - Infrastructure code
