# Quick Reference Guide

## 🚀 Deployment Commands

### Gateway Only
```bash
cd infra/terraform/gateway
terraform init
terraform apply
```

### Gateway with MCP Server (API Key)
```bash
cd infra/terraform/gateway
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=API_KEY" \
  -var='mcp_api_key_config={value="your-api-key"}'
```

### Gateway with MCP Server (OAuth)
```bash
cd infra/terraform/gateway
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-server.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='mcp_oauth_config={provider_vendor="GoogleOauth2",client_id="xxx",client_secret="xxx",scopes=["read"]}'
```

### Runtime
```bash
cd infra/terraform/runtime
terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.eu-west-1.amazonaws.com/agent:latest"
```

### Runtime with Gateway
```bash
cd infra/terraform/runtime
terraform apply \
  -var="container_image_uri=123456789012.dkr.ecr.eu-west-1.amazonaws.com/agent:latest" \
  -var="gateway_id=your-gateway-id"
```

## 📋 Get Outputs

```bash
# Gateway URL
cd infra/terraform/gateway
terraform output gateway_url

# Runtime ARN
cd infra/terraform/runtime
terraform output runtime_arn
```

## 🔧 Environment Variables

### For agent.py (basic)
```bash
MODEL_ID=eu.anthropic.claude-sonnet-4-20250514-v1:0
MODEL_REGION=eu-west-1
```

### For agent-with-gateway.py
```bash
MODEL_ID=eu.anthropic.claude-sonnet-4-20250514-v1:0
MODEL_REGION=eu-west-1
GATEWAY_URL=https://gateway-xxx.bedrock-agentcore.eu-west-1.amazonaws.com
GATEWAY_AUTH_TYPE=IAM  # or JWT
# JWT_TOKEN=xxx  # only if GATEWAY_AUTH_TYPE=JWT
```

## 🐳 Docker Commands

### Build
```bash
docker build --platform linux/arm64 -t my-agent:latest .
```

### Test Locally
```bash
docker run -p 8080:8080 \
  -e MODEL_ID=eu.anthropic.claude-sonnet-4-20250514-v1:0 \
  -e MODEL_REGION=eu-west-1 \
  my-agent:latest
```

### Push to ECR
```bash
# Login
aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.eu-west-1.amazonaws.com

# Tag
docker tag my-agent:latest 123456789012.dkr.ecr.eu-west-1.amazonaws.com/my-agent:latest

# Push
docker push 123456789012.dkr.ecr.eu-west-1.amazonaws.com/my-agent:latest
```

## 🧪 Testing

### Test Agent Locally
```bash
# Health check
curl http://localhost:8080/ping

# Invoke
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input":{"prompt":"Hello, how are you?"}}'
```

### Test Gateway Connection
```bash
GATEWAY_URL=$(cd infra/terraform/gateway && terraform output -raw gateway_url)

curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  --aws-sigv4 "aws:amz:eu-west-1:bedrock-agentcore" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

## 🗑️ Cleanup

### Destroy Runtime
```bash
cd infra/terraform/runtime
terraform destroy
```

### Destroy Gateway
```bash
cd infra/terraform/gateway
terraform destroy
```

## 📚 Documentation

- [README.md](README.md) - Main documentation
- [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) - MCP server authentication
- [docs/JWT_TOKEN_GUIDE.md](docs/JWT_TOKEN_GUIDE.md) - JWT token setup
- [docs/strands-agent-integration.md](docs/strands-agent-integration.md) - Strands integration
- [docs/runtime-gateway-integration.md](docs/runtime-gateway-integration.md) - Runtime-Gateway connection
- [infra/terraform/README.md](infra/terraform/README.md) - Terraform guide
- [REVIEW_SUMMARY.md](REVIEW_SUMMARY.md) - Technical review

## 🔐 IAM Permissions Required

### For Terraform Deployment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:*",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue"
      ],
      "Resource": "*"
    }
  ]
}
```

### For Runtime Execution
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:InvokeGateway"
      ],
      "Resource": "arn:aws:bedrock-agentcore:*:*:gateway/*"
    }
  ]
}
```

## 🐛 Troubleshooting

### Terraform Issues
```bash
# Reinitialize
terraform init -upgrade

# Check state
terraform state list

# Refresh state
terraform refresh
```

### Agent Issues
```bash
# Check logs
docker logs <container-id>

# Test Python syntax
python -m py_compile agent.py

# Check dependencies
pip install -r requirements.txt
```

### Gateway Connection Issues
```bash
# Verify gateway exists
aws bedrock-agentcore get-gateway --gateway-identifier <gateway-id>

# Check IAM permissions
aws sts get-caller-identity

# Test with verbose curl
curl -v -X POST $GATEWAY_URL ...
```

## 📞 Support

For issues or questions:
1. Check [REVIEW_SUMMARY.md](REVIEW_SUMMARY.md) for technical details
2. Review documentation in [docs/](docs/)
3. Validate Terraform: `terraform validate`
4. Check AWS service quotas
