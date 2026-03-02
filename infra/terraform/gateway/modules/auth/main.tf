locals {
  create_api_secret  = var.use_api_key && var.api_key_config.secret_arn == ""
  api_key_secret_arn = local.create_api_secret ? aws_secretsmanager_secret.api_key[0].arn : var.api_key_config.secret_arn

  oauth_callback_urls = var.use_oauth ? concat(
    ["https://bedrock-agentcore.${var.region_name}.amazonaws.com/identities/oauth2/callback"],
    var.oauth_config.callback_urls
  ) : []
}

# API Key Secret
resource "aws_secretsmanager_secret" "api_key" {
  count = local.create_api_secret ? 1 : 0

  name                    = "${var.gateway_name}-mcp-api-key"
  description             = "API key for MCP server authentication"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api_key" {
  count = local.create_api_secret ? 1 : 0

  secret_id     = aws_secretsmanager_secret.api_key[0].id
  secret_string = var.api_key_config.value
}

# Workload Identity for OAuth
resource "aws_bedrockagentcore_workload_identity" "this" {
  count = var.use_oauth ? 1 : 0

  name                                = "${var.gateway_name}-identity"
  allowed_resource_oauth2_return_urls = local.oauth_callback_urls
}

# OAuth2 Credential Provider
resource "aws_bedrockagentcore_oauth2_credential_provider" "this" {
  count = var.use_oauth ? 1 : 0

  name                       = "${var.gateway_name}-oauth-provider"
  credential_provider_vendor = var.oauth_config.provider_vendor

  oauth2_provider_config {
    dynamic "custom_oauth2_provider_config" {
      for_each = var.oauth_config.provider_vendor == "CustomOauth2" ? [1] : []
      content {
        client_id     = var.oauth_config.client_id
        client_secret = var.oauth_config.client_secret != "" ? var.oauth_config.client_secret : null

        oauth_discovery {
          authorization_server_metadata {
            issuer                 = var.oauth_config.issuer
            authorization_endpoint = var.oauth_config.authorization_endpoint
            token_endpoint         = var.oauth_config.token_endpoint
            response_types         = length(var.oauth_config.response_types) > 0 ? var.oauth_config.response_types : null
          }
        }
      }
    }

    dynamic "github_oauth2_provider_config" {
      for_each = var.oauth_config.provider_vendor == "GithubOauth2" ? [1] : []
      content {
        client_id     = var.oauth_config.client_id
        client_secret = var.oauth_config.client_secret
      }
    }

    dynamic "google_oauth2_provider_config" {
      for_each = var.oauth_config.provider_vendor == "GoogleOauth2" ? [1] : []
      content {
        client_id     = var.oauth_config.client_id
        client_secret = var.oauth_config.client_secret
      }
    }

    dynamic "microsoft_oauth2_provider_config" {
      for_each = var.oauth_config.provider_vendor == "Microsoft" ? [1] : []
      content {
        client_id     = var.oauth_config.client_id
        client_secret = var.oauth_config.client_secret
      }
    }

    dynamic "salesforce_oauth2_provider_config" {
      for_each = var.oauth_config.provider_vendor == "SalesforceOauth2" ? [1] : []
      content {
        client_id     = var.oauth_config.client_id
        client_secret = var.oauth_config.client_secret
      }
    }

    dynamic "slack_oauth2_provider_config" {
      for_each = var.oauth_config.provider_vendor == "SlackOauth2" ? [1] : []
      content {
        client_id     = var.oauth_config.client_id
        client_secret = var.oauth_config.client_secret
      }
    }
  }
}
