# AgentCore Runtime Platform

Production-ready AWS Bedrock AgentCore runtime using Strands agents with Atlassian MCP tool integration, Cognito-authenticated streaming chat frontend, and Terraform infrastructure for ECR, Gateway, Memory, and Cognito.

## What This Repository Deploys

- Bedrock AgentCore Runtime running a Strands agent
- AgentCore Gateway and MCP target configuration
- AgentCore Memory for session and long-term context
- Cognito User Pool + OIDC app client for frontend authentication
- Angular streaming chat frontend secured with Cognito tokens
- ECR repository and ARM64 container image workflow

## Structure

```
src/
└── agentcore_strands/
    ├── __init__.py
    └── agent.py          # Strands agent with memory support

scripts/
└── invoke.py             # Script to invoke deployed runtime

push-to-ecr.sh            # Script to build and push Docker image to ECR

examples/
├── agent.local.py        # Local development example
└── example.local.md

infra/terraform/
├── cognito/
├── gateway/
├── memory/
├── runtime/
└── ecr/

docs/
├── AUTHENTICATION.md
├── JWT_TOKEN_GUIDE.md
├── CLOUDWATCH_LOGS.md
├── ATLASSIAN_MCP_INTEGRATION_BACKEND.md
├── ATLASSIAN_MCP_INTEGRATION_FRONTEND.md
├── strands-agent-integration.md
└── runtime-gateway-integration.md

frontend/                 # Angular chat client for runtime integration

Dockerfile            # Container image for AgentCore Runtime
pyproject.toml        # uv dependency management
```

## Quick Start

### 1. Deploy ECR Repository

```bash
cd infra/terraform/ecr
terraform init
terraform apply -var="repository_name=agentvault_agent"
```

### 2. Build and Push Docker Image

```bash
export AWS_REGION=eu-west-1
export ECR_REPO_NAME=agentvault_agent
./push-to-ecr.sh
```

Use the same repository name and region in Terraform, Docker push, and runtime deployment.

### 3. Deploy Gateway

```bash
cd infra/terraform/gateway
terraform init
terraform apply
```

### 4. Deploy Memory

```bash
cd infra/terraform/memory
terraform init
terraform apply -var="memory_name=my_agent_memory"
```

### 5. Deploy Cognito

```bash
cd infra/terraform/cognito
terraform init
terraform apply
```

### 6. Deploy Runtime

Deploy runtime with Gateway, Memory, and Cognito JWT authorizer values:

```bash
GATEWAY_ID=$(cd infra/terraform/gateway && terraform output -raw gateway_id)
MEMORY_ID=$(cd infra/terraform/memory && terraform output -raw memory_id)
JWT_ISSUER=$(cd infra/terraform/cognito && terraform output -raw cognito_authority)
JWT_AUDIENCE=$(cd infra/terraform/cognito && terraform output -raw user_pool_client_id)

cd infra/terraform/runtime
terraform init
terraform apply \
  -var="container_image_uri=ACCOUNT.dkr.ecr.eu-west-1.amazonaws.com/agentvault_agent:latest" \
  -var="gateway_id=$GATEWAY_ID" \
  -var="memory_id=$MEMORY_ID" \
  -var="jwt_issuer=$JWT_ISSUER" \
  -var="jwt_audience=$JWT_AUDIENCE"
```

## Terraform Deployment

### Gateway

**Basic gateway (no MCP server):**
```bash
cd infra/terraform/gateway
terraform init
terraform apply
```

**Gateway + MCP server with API Key:**
```bash
# Store API key in Secrets Manager
aws secretsmanager create-secret \
  --name mcp-api-key \
  --secret-string "your-api-key"

# Deploy
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=API_KEY" \
  -var='mcp_api_key_config={secret_arn="arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-api-key"}'
```

**Gateway + MCP server with OAuth:**
```bash
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='mcp_oauth_config={provider_vendor="GoogleOauth2",client_id="your-id",client_secret="your-secret",scopes=["read","write"]}'
```

**Gateway + MCP server with IAM:**
```bash
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=IAM"
```

### Runtime

**Deploy (production):**
```bash
cd infra/terraform/runtime
terraform init

GATEWAY_ID=$(cd ../gateway && terraform output -raw gateway_id)
MEMORY_ID=$(cd ../memory && terraform output -raw memory_id)
JWT_ISSUER=$(cd ../cognito && terraform output -raw cognito_authority)
JWT_AUDIENCE=$(cd ../cognito && terraform output -raw user_pool_client_id)

terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.eu-west-1.amazonaws.com/agentvault_agent:latest" \
  -var="gateway_id=$GATEWAY_ID" \
  -var="memory_id=$MEMORY_ID" \
  -var="jwt_issuer=$JWT_ISSUER" \
  -var="jwt_audience=$JWT_AUDIENCE"
```

### Cognito

**Deploy:**
```bash
cd infra/terraform/cognito
terraform init
terraform apply
```

**Get outputs for frontend/runtime wiring:**
```bash
cd infra/terraform/cognito
terraform output user_pool_id
terraform output user_pool_client_id
terraform output cognito_authority
terraform output user_pool_domain
```

### Memory

**Basic memory (STM only):**
```bash
cd infra/terraform/memory
terraform init
terraform apply -var="memory_name=my_agent_memory"
```

**With semantic strategy:**
```bash
terraform apply \
  -var="memory_name=my_agent_memory" \
  -var='strategies=[{name="semantic-strategy",type="SEMANTIC",namespaces=["default"]}]'
```

**With all built-in strategies:**
```bash
terraform apply \
  -var="memory_name=my_agent_memory" \
  -var='strategies=[{name="semantic",type="SEMANTIC",namespaces=["default"]},{name="summary",type="SUMMARIZATION",namespaces=["{sessionId}"]},{name="user-pref",type="USER_PREFERENCE",namespaces=["preferences"]}]'
```

**With custom strategy:**
```bash
terraform apply \
  -var="memory_name=my_agent_memory" \
  -var='strategies=[{name="custom-semantic",type="CUSTOM",namespaces=["{sessionId}"],configuration={type="SEMANTIC_OVERRIDE",consolidation={append_to_prompt="Focus on key relationships",model_id="anthropic.claude-3-sonnet-20240229-v1:0"}}}]'
```

### ECR

**Create repository:**
```bash
cd infra/terraform/ecr
terraform init
terraform apply -var="repository_name=agentvault_agent"
```

## Get Gateway URL

```bash
cd infra/terraform/gateway
terraform output gateway_url
```

## Invoke Runtime

After deploying the runtime, test it with:

```bash
# Get runtime ARN
cd infra/terraform/runtime
RUNTIME_ARN=$(terraform output -raw runtime_arn)

# Invoke with a prompt
python scripts/invoke.py "What is the weather today?" --runtime-arn $RUNTIME_ARN

# Continue conversation with session ID
python scripts/invoke.py "Tell me more" --runtime-arn $RUNTIME_ARN --session-id user123

# If your runtime is outside eu-west-1, pass --region
python scripts/invoke.py "Hello" --runtime-arn $RUNTIME_ARN --region us-east-1
```

## Configure Frontend

Copy and edit frontend environment files:

```bash
cp frontend/src/environments/environment.example.ts frontend/src/environments/environment.ts
cp frontend/src/environments/environment.prod.example.ts frontend/src/environments/environment.prod.ts
```

Populate these values from Terraform outputs:
- `agentcore.runtimeUrl` from runtime invoke URL
- `cognito.authority` from `infra/terraform/cognito` output `cognito_authority`
- `cognito.clientId` from `infra/terraform/cognito` output `user_pool_client_id`
- `cognito.userPoolDomain` from `infra/terraform/cognito` output `user_pool_domain`

Run frontend locally:

```bash
cd frontend
npm install
npm start
```

## Documentation

- [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) - Authentication options for MCP servers
- [docs/ATLASSIAN_MCP_INTEGRATION_BACKEND.md](docs/ATLASSIAN_MCP_INTEGRATION_BACKEND.md) - Backend Atlassian MCP integration
- [docs/ATLASSIAN_MCP_INTEGRATION_FRONTEND.md](docs/ATLASSIAN_MCP_INTEGRATION_FRONTEND.md) - Frontend Atlassian OAuth integration
- [docs/JWT_TOKEN_GUIDE.md](docs/JWT_TOKEN_GUIDE.md) - Getting JWT tokens for CUSTOM_JWT authorizer
- [docs/CLOUDWATCH_LOGS.md](docs/CLOUDWATCH_LOGS.md) - CloudWatch logging configuration and troubleshooting
- [docs/strands-agent-integration.md](docs/strands-agent-integration.md) - Integrating with Strands agents
- [docs/runtime-gateway-integration.md](docs/runtime-gateway-integration.md) - Connecting Runtime to Gateway
- [infra/terraform/README.md](infra/terraform/README.md) - Terraform deployment guide

## Requirements

- AWS CLI configured
- Terraform >= 1.0
- Python >= 3.10
- Node.js >= 18
- Permissions to create IAM roles, Bedrock resources
- For Runtime: ECR container image with `/ping` and `/invocations` endpoints on port 8080

## CI/CD

- Deploy workflow: [.github/workflows/deploy.yml](.github/workflows/deploy.yml)
- Destroy workflow: [.github/workflows/destroy.yml](.github/workflows/destroy.yml)
- Full setup guide: [.github/workflows/README.md](.github/workflows/README.md)

Current workflow behavior:
- Deploy is configured for `workflow_dispatch` (manual run) by default.
- Push-triggered applies are intentionally disabled by `branches: [none]`.
- In the current workflow file, Terraform `apply` steps run only on `push` to `main`, so manual runs validate/build but do not apply infrastructure unless you adjust those `if` conditions.
