locals {
  use_api_key    = var.add_mcp_target && var.mcp_auth_type == "API_KEY"
  use_oauth      = var.add_mcp_target && var.mcp_auth_type == "OAUTH"
  use_iam        = var.add_mcp_target && var.mcp_auth_type == "IAM"
  use_custom_jwt = var.gateway_authorizer_type == "CUSTOM_JWT"
}

resource "aws_bedrockagentcore_gateway" "this" {
  name            = var.gateway_name
  description     = "AgentCore gateway for ${var.environment_name}"
  authorizer_type = var.gateway_authorizer_type
  protocol_type   = "MCP"
  role_arn        = var.role_arn

  dynamic "authorizer_configuration" {
    for_each = local.use_custom_jwt ? [1] : []
    content {
      custom_jwt_authorizer {
        discovery_url    = var.gateway_jwt_config.discovery_url
        allowed_audience = length(var.gateway_jwt_config.allowed_audience) > 0 ? var.gateway_jwt_config.allowed_audience : null
        allowed_clients  = length(var.gateway_jwt_config.allowed_clients) > 0 ? var.gateway_jwt_config.allowed_clients : null
      }
    }
  }

  protocol_configuration {
    mcp {
      instructions       = var.mcp_instructions
      search_type        = var.mcp_search_type
      supported_versions = var.mcp_supported_versions
    }
  }
}

# Gateway Target - API Key
resource "aws_bedrockagentcore_gateway_target" "api_key" {
  count = local.use_api_key ? 1 : 0

  name               = "${var.gateway_name}-mcp-target"
  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = var.mcp_server_endpoint
      }
    }
  }

  credential_provider_configuration {
    api_key {
      provider_arn              = var.api_key_secret_arn
      credential_location       = "HEADER"
      credential_parameter_name = var.api_key_header_name
    }
  }
}

# Gateway Target - OAuth
resource "aws_bedrockagentcore_gateway_target" "oauth" {
  count = local.use_oauth ? 1 : 0

  name               = "${var.gateway_name}-mcp-target"
  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = var.mcp_server_endpoint
      }
    }
  }

  credential_provider_configuration {
    oauth {
      provider_arn = var.oauth_provider_arn
      scopes       = var.oauth_scopes
    }
  }
}

# Gateway Target - IAM
resource "aws_bedrockagentcore_gateway_target" "iam" {
  count = local.use_iam ? 1 : 0

  name               = "${var.gateway_name}-mcp-target"
  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = var.mcp_server_endpoint
      }
    }
  }
}
