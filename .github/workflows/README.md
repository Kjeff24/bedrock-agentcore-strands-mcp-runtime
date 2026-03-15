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

### 4. Configure Terraform Backend

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

The workflow currently uses these defaults from `deploy.yml`:
- Terraform state bucket: `account-vending-terraform-state`
- AWS region: `eu-west-1`
- Project name: `agentvault_agent`
- Environment name: `prod`

The workflow keeps the per-module backend keys from each `backend.tf` file under `infra/terraform/*`.

Update `backend.tf` files if you want to change the backend key layout:
```hcl
terraform {
  backend "s3" {
    bucket       = "your-terraform-state-bucket"
    key          = "agentcore/runtime/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
  }
}
```

## Workflows

### Deploy Pipeline (`.github/workflows/deploy.yml`)

**Triggers:**
- `push` to `develop` validates and deploys the platform
- `workflow_dispatch` supports manual validation or manual apply via the `apply` input

**Jobs:**
1. **prepare** - Resolves deploy settings such as region, names, and image tag
2. **validate-terraform** - Runs `fmt` and `validate` across `ecr`, `cognito`, `memory`, `gateway`, and `runtime`
3. **validate-image** - Verifies the ARM64 runtime image build
4. **preflight** - Checks required repo config and Terraform backend access before deployment
5. **deploy-ecr** - Creates or updates the ECR repository
6. **build-image** - Builds and pushes the runtime image to ECR
7. **deploy-cognito** - Applies Cognito resources and exposes JWT/OIDC outputs
8. **deploy-memory** - Applies AgentCore Memory resources
9. **deploy-gateway** - Applies AgentCore Gateway resources
10. **deploy-runtime** - Applies Runtime using image, gateway, memory, and Cognito outputs

**Usage:**
```bash
# Automatic deploy on push to develop
git push origin develop

# Manual trigger
# Go to Actions → Deploy AgentCore Platform → Run workflow
# Set apply=false for validation-only manual runs
```

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

Edit the `env` block in `.github/workflows/deploy.yml`. If your Terraform backend bucket is in another region, update `TF_STATE_REGION` as well.

### Add Environment Variables

For environment-wide naming overrides, edit the `env` block in `.github/workflows/deploy.yml`:
- `PROJECT_NAME`
- `ENVIRONMENT_NAME`
- `ECR_REPOSITORY`
- `MEMORY_NAME`
- `RUNTIME_NAME`

For gateway with MCP target, keep the workflow unchanged and manage the target configuration through files or variables in `infra/terraform/gateway`.

Example apply command used by the workflow pattern:

```yaml
- name: Terraform Plan
  run: |
    terraform plan -out=tfplan \
      -var="add_mcp_target=true" \
      -var="mcp_server_endpoint=https://your-mcp-server.com" \
      -var="mcp_auth_type=API_KEY" \
      -var='mcp_api_key_config={secret_arn="arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-api-key"}'
```

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
  deploy-gateway:
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
# Gateway URL, Cognito outputs, and Runtime ARN are written to the job summary
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
- Confirm the backend bucket in `deploy.yml` and the Terraform `backend.tf` files is correct for your AWS account
- Confirm `AWS_ROLE_ARN` is configured in the repository

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
