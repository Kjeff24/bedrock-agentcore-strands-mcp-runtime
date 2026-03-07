/*
Module: AWS Cognito Authentication

Description:
- Provisions a Cognito User Pool, User Pool Client, Hosted UI domain, and optional
  federated identity providers (Google, Facebook, Login with Amazon, Apple, OIDC, SAML).
- Builds a dynamic list of supported identity providers based on which IdPs are configured.

Creates:
- data.aws_caller_identity.current
- aws_cognito_user_pool.user_pool
- aws_cognito_user_pool_client.user_pool_client
- aws_cognito_identity_provider.google | facebook | login_with_amazon | apple (conditional)
- aws_cognito_identity_provider.oidc (for_each)
- aws_cognito_identity_provider.saml (for_each)
- aws_cognito_user_pool_domain.user_pool_domain

Inputs:
- var.project_name (string)
- var.tags (map(string))
- var.user_pool_settings (object):
  - auto_verified_attributes (list(string))
  - username_attributes (list(string))
  - password_policy { min_length, require_uppercase, require_lowercase, require_numbers, require_symbols, temp_validity_days }
  - user_pool_schema (list(object))
- var.cognito_client_config (object):
  - generate_secret (bool)
  - oauth_settings { allowed_flows_user_pool, allowed_flows, allowed_scopes, explicit_auth_flows, callback_urls, logout_urls, supported_identity_providers }
  - token_validity { refresh_token, access_token, id_token, refresh_unit, access_unit, id_unit }
- var.managed_login_version (string)
- var.idp_google, var.idp_facebook, var.idp_login_with_amazon, var.idp_apple (object):
  - enabled (bool), client_id, client_secret, authorize_scopes
  - Apple: team_id, key_id, private_key
- var.idp_oidc_providers (list(object)):
  - name, issuer, client_id, client_secret
  - optional: authorize_url, token_url, attributes_url, jwks_uri, attributes_request_method, authorize_scopes, attribute_mapping
- var.idp_saml_providers (list(object)):
  - name, idp_init, metadata_url, encrypted_responses, idp_signout, request_signing_algorithm, attribute_mapping

Notes:
- Callback and logout URLs may need to be updated post-deployment to include the CloudFront domain.
- Set generate_secret=false for public browser-based clients.
- Identity providers are created only when configured (counts/for_each) and the client
  supported_identity_providers is derived from those actually present.
*/
data "aws_caller_identity" "current" {}

# Computed list of federated IdP names that actually exist in this plan
locals {
  dynamic_identity_providers = distinct(concat(
    aws_cognito_identity_provider.google[*].provider_name,
    aws_cognito_identity_provider.facebook[*].provider_name,
    aws_cognito_identity_provider.login_with_amazon[*].provider_name,
    aws_cognito_identity_provider.apple[*].provider_name,
    keys(aws_cognito_identity_provider.oidc),
    keys(aws_cognito_identity_provider.saml)
  ))
}

# 🔐 AWS Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                     = "${var.project_name}-user-pool"
  auto_verified_attributes = var.user_pool_settings.auto_verified_attributes
  username_attributes      = var.user_pool_settings.username_attributes

  password_policy {
    minimum_length                   = var.user_pool_settings.password_policy.min_length
    require_uppercase                = var.user_pool_settings.password_policy.require_uppercase
    require_lowercase                = var.user_pool_settings.password_policy.require_lowercase
    require_numbers                  = var.user_pool_settings.password_policy.require_numbers
    require_symbols                  = var.user_pool_settings.password_policy.require_symbols
    temporary_password_validity_days = var.user_pool_settings.password_policy.temp_validity_days
  }

  dynamic "schema" {
    for_each = var.user_pool_settings.user_pool_schema
    content {
      name                = schema.value.name
      attribute_data_type = schema.value.attribute_data_type
      mutable             = schema.value.mutable
      required            = schema.value.required
    }
  }

  lifecycle {
    ignore_changes = [schema]
  }
}

# 👤 AWS Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name            = "${var.project_name}-user-pool-client"
  user_pool_id    = aws_cognito_user_pool.user_pool.id
  generate_secret = var.cognito_client_config.generate_secret

  allowed_oauth_flows_user_pool_client = var.cognito_client_config.oauth_settings.allowed_flows_user_pool
  allowed_oauth_flows                  = var.cognito_client_config.oauth_settings.allowed_flows
  allowed_oauth_scopes                 = var.cognito_client_config.oauth_settings.allowed_scopes
  # Include only providers that exist; always allow COGNITO if present
  supported_identity_providers = distinct(concat(
    compact([
      for p in var.cognito_client_config.oauth_settings.supported_identity_providers :
      (p == "COGNITO" || contains(local.dynamic_identity_providers, p)) ? p : null
    ]),
    local.dynamic_identity_providers
  ))
  explicit_auth_flows = var.cognito_client_config.oauth_settings.explicit_auth_flows
  callback_urls       = var.cognito_client_config.oauth_settings.callback_urls
  logout_urls         = var.cognito_client_config.oauth_settings.logout_urls

  refresh_token_validity = var.cognito_client_config.token_validity.refresh_token
  access_token_validity  = var.cognito_client_config.token_validity.access_token
  id_token_validity      = var.cognito_client_config.token_validity.id_token

  token_validity_units {
    refresh_token = var.cognito_client_config.token_validity.refresh_unit
    access_token  = var.cognito_client_config.token_validity.access_unit
    id_token      = var.cognito_client_config.token_validity.id_unit
  }

  depends_on = [
    aws_cognito_user_pool.user_pool,
    aws_cognito_identity_provider.google,
    aws_cognito_identity_provider.facebook,
    aws_cognito_identity_provider.login_with_amazon,
    aws_cognito_identity_provider.apple,
    aws_cognito_identity_provider.oidc,
    aws_cognito_identity_provider.saml,
  ]
}

## 🔗 AWS Cognito Identity Providers (explicit)

# Google
resource "aws_cognito_identity_provider" "google" {
  count         = var.idp_google.enabled ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = "Google"
  provider_type = "Google"
  provider_details = {
    client_id        = var.idp_google.client_id
    client_secret    = var.idp_google.client_secret
    authorize_scopes = var.idp_google.authorize_scopes
  }
  attribute_mapping = {
    email       = "email"
    given_name  = "given_name"
    family_name = "family_name"
    username    = "sub"
  }
}

# Facebook
resource "aws_cognito_identity_provider" "facebook" {
  count         = var.idp_facebook.enabled ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = "Facebook"
  provider_type = "Facebook"
  provider_details = {
    client_id        = var.idp_facebook.client_id
    client_secret    = var.idp_facebook.client_secret
    authorize_scopes = var.idp_facebook.authorize_scopes
  }
  attribute_mapping = {
    email       = "email"
    given_name  = "first_name"
    family_name = "last_name"
    username    = "id"
  }
}

# Login with Amazon
resource "aws_cognito_identity_provider" "login_with_amazon" {
  count         = var.idp_login_with_amazon.enabled ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = "LoginWithAmazon"
  provider_type = "LoginWithAmazon"
  provider_details = {
    client_id        = var.idp_login_with_amazon.client_id
    client_secret    = var.idp_login_with_amazon.client_secret
    authorize_scopes = var.idp_login_with_amazon.authorize_scopes
  }
  attribute_mapping = {
    email    = "email"
    name     = "name"
    username = "user_id"
  }
}

# Sign in with Apple
resource "aws_cognito_identity_provider" "apple" {
  count         = var.idp_apple.enabled ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = "SignInWithApple"
  provider_type = "SignInWithApple"
  provider_details = {
    client_id        = var.idp_apple.client_id
    team_id          = var.idp_apple.team_id
    key_id           = var.idp_apple.key_id
    private_key      = var.idp_apple.private_key
    authorize_scopes = var.idp_apple.authorize_scopes
  }
  attribute_mapping = {
    email    = "email"
    name     = "name"
    username = "sub"
  }
}

# OIDC (multiple)
locals {
  oidc_map = { for p in var.idp_oidc_providers : p.name => p }
}

resource "aws_cognito_identity_provider" "oidc" {
  for_each      = local.oidc_map
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = each.value.name
  provider_type = "OIDC"
  provider_details = merge({
    attributes_request_method = coalesce(try(each.value.attributes_request_method, null), "GET"),
    oidc_issuer               = each.value.issuer,
    client_id                 = each.value.client_id,
    client_secret             = each.value.client_secret,
    authorize_scopes          = coalesce(try(each.value.authorize_scopes, null), "openid profile email")
  }, {
    for k, v in {
      authorize_url  = try(each.value.authorize_url, null)
      token_url      = try(each.value.token_url, null)
      attributes_url = try(each.value.attributes_url, null)
      jwks_uri       = try(each.value.jwks_uri, null)
    } : k => v if v != null
  })
  attribute_mapping = try(each.value.attribute_mapping, {
    email       = "email"
    given_name  = "given_name"
    family_name = "family_name"
    username    = "sub"
  })
}

# SAML (multiple)
locals {
  saml_map = { for p in var.idp_saml_providers : p.name => p }
}

resource "aws_cognito_identity_provider" "saml" {
  for_each      = local.saml_map
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = each.value.name
  provider_type = "SAML"
  provider_details = {
    for k, v in {
      IDPInit                = try(each.value.idp_init, null)
      MetadataURL            = try(each.value.metadata_url, null)
      EncryptedResponses     = try(each.value.encrypted_responses, null)
      IDPSignout             = try(each.value.idp_signout, null)
      RequestSigningAlgorithm = try(each.value.request_signing_algorithm, null)
    } : k => v if v != null
  }
  attribute_mapping = try(each.value.attribute_mapping, {
    email    = "email"
    name     = "name"
    username = "sub"
  })
}

# 🌐 AWS Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain                = "${replace(var.project_name, "_", "-")}-${data.aws_caller_identity.current.account_id}-domain"
  user_pool_id          = aws_cognito_user_pool.user_pool.id
  managed_login_version = var.managed_login_version
}