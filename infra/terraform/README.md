# Terraform Deployment Guide

Terraform modules for deploying AgentCore Gateway and Runtime.

## Gateway

### Basic Gateway
```bash
cd terraform/gateway

terraform init
terraform plan
terraform apply
```

### Gateway with MCP Server (API Key)
```bash
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=API_KEY" \
  -var="api_key_value=your-secret-api-key"

# Or use existing secret
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=API_KEY" \
  -var="api_key_secret_arn=arn:aws:secretsmanager:region:account:secret:key"
```

### Gateway with MCP Server (OAuth)
```bash
# Uses default AWS callback URL automatically
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='oauth_scopes=["read","write"]'

# Or specify custom callback URLs
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='oauth_scopes=["read","write"]' \
  -var='oauth_callback_urls=["https://bedrock-agentcore.eu-west-1.amazonaws.com/identities/oauth2/callback"]'
```

### Gateway with MCP Server (IAM)
```bash
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=IAM"
```

## Runtime

```bash
cd terraform/runtime

terraform init
terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest"
```

## Using terraform.tfvars

Create `terraform.tfvars`:

```hcl
# Gateway
environment_name    = "prod"
gateway_name        = "my-gateway"
add_mcp_target      = true
mcp_server_endpoint = "https://your-server.com"
mcp_auth_type       = "API_KEY"
api_key_secret_arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:key"

# Runtime
runtime_name        = "my-runtime"
container_image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
```

Then simply run:
```bash
terraform apply
```

## Get Outputs

```bash
terraform output gateway_url
terraform output runtime_arn
```
