locals {
  use_api_key = var.add_mcp_target && var.mcp_auth_type == "API_KEY"
  use_oauth   = var.add_mcp_target && var.mcp_auth_type == "OAUTH"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "iam" {
  source = "./modules/iam"

  gateway_name       = var.gateway_name
  account_id         = data.aws_caller_identity.current.account_id
  use_api_key        = local.use_api_key
  api_key_secret_arn = local.use_api_key ? module.auth[0].api_key_secret_arn : ""
}

module "auth" {
  count = local.use_api_key || local.use_oauth ? 1 : 0

  source = "./modules/auth"

  gateway_name   = var.gateway_name
  region_name    = data.aws_region.current.id
  use_api_key    = local.use_api_key
  use_oauth      = local.use_oauth
  api_key_config = local.use_api_key ? var.mcp_api_key_config : {
    secret_arn  = ""
    value       = ""
    header_name = ""
  }
  oauth_config = local.use_oauth ? var.mcp_oauth_config : {
    provider_vendor        = ""
    issuer                 = ""
    authorization_endpoint = ""
    token_endpoint         = ""
    response_types         = []
    client_id              = ""
    client_secret          = ""
    scopes                 = []
    callback_urls          = []
    grant_type             = "CLIENT_CREDENTIALS"
    return_url             = ""
  }
}

module "gateway" {
  source = "./modules/gateway"

  gateway_name            = var.gateway_name
  environment_name        = var.environment_name
  gateway_authorizer_type = var.gateway_authorizer_type
  role_arn                = module.iam.role_arn
  gateway_jwt_config      = var.gateway_jwt_config
  mcp_instructions        = var.mcp_instructions
  mcp_search_type         = var.mcp_search_type
  mcp_supported_versions  = var.mcp_supported_versions
  add_mcp_target          = var.add_mcp_target
  mcp_auth_type           = var.mcp_auth_type
  mcp_server_endpoint     = var.mcp_server_endpoint
  api_key_secret_arn      = local.use_api_key ? module.auth[0].api_key_secret_arn : ""
  api_key_header_name     = local.use_api_key ? var.mcp_api_key_config.header_name : ""
  oauth_provider_arn      = local.use_oauth ? module.auth[0].oauth_provider_arn : ""
  oauth_scopes            = local.use_oauth ? var.mcp_oauth_config.scopes : []
  oauth_grant_type        = local.use_oauth ? var.mcp_oauth_config.grant_type : "CLIENT_CREDENTIALS"
  oauth_return_url        = local.use_oauth ? var.mcp_oauth_config.return_url : ""
}
