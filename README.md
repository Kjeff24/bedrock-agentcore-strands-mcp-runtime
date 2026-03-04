# AgentCore Runtime and Gateway Templates

Terraform templates for deploying Amazon Bedrock AgentCore Runtime and Gateway.

## Structure

```
src/
└── agentcore_strands/
    ├── __init__.py
    └── agent.py          # Strands agent with memory support

scripts/
├── invoke.py             # Script to invoke deployed runtime
└── push-to-ecr.sh        # Script to build and push Docker image to ECR

examples/
├── agent.local.py        # Local development example
└── example.local.md

infra/terraform/
├── gateway/
├── runtime/
├── memory/
└── ecr/

docs/
├── AUTHENTICATION.md
├── JWT_TOKEN_GUIDE.md
├── CLOUDWATCH_LOGS.md
├── strands-agent-integration.md
└── runtime-gateway-integration.md

Dockerfile            # Container image for AgentCore Runtime
pyproject.toml        # uv dependency management
```

## Quick Start

### 1. Deploy ECR Repository

```bash
cd infra/terraform/ecr
terraform init
terraform apply -var="repository_name=agentcore-strands-agent"
```

### 2. Build and Push Docker Image

```bash
./scripts/push-to-ecr.sh
```

### 3. Deploy Gateway (Optional)

```bash
cd infra/terraform/gateway
terraform init
terraform apply
```

### 4. Deploy Memory (Optional)

```bash
cd infra/terraform/memory
terraform init
terraform apply -var="memory_name=my_agent_memory"
```

### 5. Deploy Runtime

```bash
cd infra/terraform/runtime
terraform init
terraform apply \
  -var="container_image_uri=ACCOUNT.dkr.ecr.REGION.amazonaws.com/agentcore-strands-agent:latest"
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

**Deploy:**
```bash
cd infra/terraform/runtime
terraform init
terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest"
```

**With Gateway integration:**
```bash
terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest" \
  -var="gateway_id=your-gateway-id"
```

**With Memory integration:**
```bash
terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest" \
  -var="memory_id=your-memory-id"
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
terraform apply -var="repository_name=agentcore-strands-agent"
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
```

## Documentation

- [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) - Authentication options for MCP servers
- [docs/JWT_TOKEN_GUIDE.md](docs/JWT_TOKEN_GUIDE.md) - Getting JWT tokens for CUSTOM_JWT authorizer
- [docs/CLOUDWATCH_LOGS.md](docs/CLOUDWATCH_LOGS.md) - CloudWatch logging configuration and troubleshooting
- [docs/strands-agent-integration.md](docs/strands-agent-integration.md) - Integrating with Strands agents
- [docs/runtime-gateway-integration.md](docs/runtime-gateway-integration.md) - Connecting Runtime to Gateway
- [infra/terraform/README.md](infra/terraform/README.md) - Terraform deployment guide

## Requirements

- AWS CLI configured
- Terraform >= 1.0
- Permissions to create IAM roles, Bedrock resources
- For Runtime: ECR container image with `/ping` and `/invocations` endpoints on port 8080

## CI/CD

See [.github/workflows/README.md](.github/workflows/README.md) for GitHub Actions setup.
