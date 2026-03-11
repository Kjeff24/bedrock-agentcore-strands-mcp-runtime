# GitHub Actions Setup

## Prerequisites

### 1. AWS OIDC Provider Setup

Configure AWS to trust GitHub Actions:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Create IAM Role

Create a role that GitHub Actions can assume:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

Attach policies:
```bash
aws iam attach-role-policy \
  --role-name GitHubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

aws iam attach-role-policy \
  --role-name GitHubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
```

### 3. Configure GitHub Secrets

Go to your repository → Settings → Secrets and variables → Actions

Add:
- `AWS_ROLE_ARN`: `arn:aws:iam::ACCOUNT_ID:role/GitHubActionsRole`

### 4. Configure Terraform Backend (Optional)

Create S3 bucket and DynamoDB table for state:

```bash
# S3 bucket
aws s3 mb s3://your-terraform-state-bucket

# DynamoDB table
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Update `backend.tf` in both gateway and runtime:
```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "gateway/terraform.tfstate"  # or "runtime/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

## Workflows

### Deploy Pipeline (`.github/workflows/deploy.yml`)

**Triggers:**
- Manual trigger via `workflow_dispatch`
- `push` event is present but branch filter is `none` (effectively disabled)
- `pull_request` plan logic exists in jobs, but the workflow currently has no PR trigger

**Jobs:**
1. **terraform-gateway** - Init/fmt/validate (apply only on push to `main`)
2. **build-push-image** - Builds ARM64 container and pushes to ECR
3. **terraform-runtime** - Init/fmt/validate using built image (apply only on push to `main`)

**Usage:**
```bash
# Manual trigger
# Go to Actions → Deploy AgentCore Infrastructure → Run workflow
```

If you want automatic deploys from pushes, update `deploy.yml` to:
- Replace `branches: [none]` with your deployment branch (for example `main`)
- Adjust `if` conditions on Terraform `apply` steps if you want applies during manual runs

### Destroy Pipeline (`.github/workflows/destroy.yml`)

**Triggers:**
- Manual only (requires typing "destroy" to confirm)

**Jobs:**
1. **destroy-runtime** - Destroys Runtime first
2. **destroy-gateway** - Destroys Gateway after Runtime

**Usage:**
```bash
# Go to Actions → Destroy AgentCore Infrastructure → Run workflow
# Type "destroy" in the confirmation field
```

## Customization

### Change AWS Region

Edit `.github/workflows/deploy.yml`:
```yaml
env:
  AWS_REGION: eu-west-1  # Change this
```

### Add Environment Variables

For gateway with MCP target:

```yaml
- name: Terraform Apply
  run: |
    terraform apply -auto-approve \
      -var="add_mcp_target=true" \
      -var="mcp_server_endpoint=${{ secrets.MCP_SERVER_ENDPOINT }}" \
      -var="mcp_auth_type=API_KEY" \
      -var='mcp_api_key_config={secret_arn="${{ secrets.API_KEY_SECRET_ARN }}"}'
```

Add secrets:
- `MCP_SERVER_ENDPOINT`
- `API_KEY_SECRET_ARN`

### Multi-Environment Setup

Create separate workflows for dev/staging/prod:

```yaml
# .github/workflows/deploy-dev.yml
on:
  push:
    branches: [develop]

env:
  AWS_REGION: us-east-1
  ENVIRONMENT: dev

jobs:
  terraform-gateway:
    steps:
      - name: Terraform Apply
        run: |
          terraform apply -auto-approve \
            -var="environment_name=dev" \
            -var="gateway_name=agentcore-gateway-dev"
```

## Monitoring Deployments

### View Logs
```bash
# In GitHub UI
Actions → Select workflow run → View job logs
```

### Check Terraform Outputs
```bash
# Gateway URL and Runtime ARN are output in the logs
# Or query via AWS CLI:
aws bedrock-agentcore list-gateways
aws bedrock-agentcore list-agent-runtimes
```

## Troubleshooting

### Permission Errors
- Verify IAM role trust policy includes your repo
- Check role has required policies attached

### Terraform State Lock
```bash
# If state is locked, force unlock:
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"your-terraform-state-bucket/gateway/terraform.tfstate-md5"}}'
```

### Container Build Fails
- Ensure Docker buildx supports ARM64
- Check ECR repository exists and has permissions

### Apply Fails
- Check CloudWatch logs for detailed errors
- Verify all required AWS services are available in region
- Check service quotas

## Security Best Practices

1. **Use OIDC** (already configured) - No long-lived credentials
2. **Least privilege** - Scope IAM role to specific resources
3. **Protect main branch** - Require PR reviews
4. **Scan containers** - Add security scanning step
5. **Rotate secrets** - Regularly update API keys and credentials

## Example: Add Container Scanning

```yaml
- name: Scan Container
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.build.outputs.image_uri }}
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Scan Results
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```
