data "aws_caller_identity" "current" {}

# IAM Role for Runtime
resource "aws_iam_role" "runtime" {
  name = "${var.runtime_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "runtime_cloudwatch" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "runtime_ecr" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Policy to invoke Bedrock models
resource "aws_iam_role_policy" "runtime_bedrock_access" {
  name = "BedrockModelInvokeAccess"
  role = aws_iam_role.runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [
        "arn:aws:bedrock:*::foundation-model/*",
        "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      ]
    }]
  })
}

# Policy to invoke AgentCore Gateway
resource "aws_iam_role_policy" "runtime_gateway_access" {
  count = var.gateway_id != "" ? 1 : 0
  name  = "GatewayInvokeAccess"
  role  = aws_iam_role.runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock-agentcore:InvokeGateway",
        "bedrock-agentcore:GetGateway"
      ]
      Resource = "arn:aws:bedrock-agentcore:*:${data.aws_caller_identity.current.account_id}:gateway/${var.gateway_id}"
    }]
  })
}

# Policy to access AgentCore Memory
resource "aws_iam_role_policy" "runtime_memory_access" {
  count = var.memory_id != "" ? 1 : 0
  name  = "MemoryAccess"
  role  = aws_iam_role.runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock-agentcore:GetMemory",
        "bedrock-agentcore:CreateEvent",
        "bedrock-agentcore:GetEvents",
        "bedrock-agentcore:ListEvents",
        "bedrock-agentcore:QueryMemory"
      ]
      Resource = "arn:aws:bedrock-agentcore:*:${data.aws_caller_identity.current.account_id}:memory/${var.memory_id}"
    }]
  })
}

# AgentCore Runtime
resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = var.runtime_name
  description        = "AgentCore runtime for ${var.environment_name}"
  role_arn           = aws_iam_role.runtime.arn

  protocol_configuration {
    server_protocol = var.protocol_type
  }

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_image_uri
    }
  }

  network_configuration {
    network_mode = var.network_mode
  }

  # JWT Authorization Configuration
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = "${var.jwt_issuer}/.well-known/openid-configuration"
      allowed_clients  = [var.jwt_audience]  # Use allowed_clients instead of allowed_audience
    }
  }

  environment_variables = merge(
    var.environment_variables,
    var.memory_id != "" ? { MEMORY_ID = var.memory_id } : {},
    var.force_redeploy != "" ? { FORCE_REDEPLOY = var.force_redeploy } : {}
  )
}


