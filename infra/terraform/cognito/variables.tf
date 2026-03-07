variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
  default     = "agentvault_agent"
}

variable "environment_name" {
  type        = string
  default     = "prod"
  description = "Environment name"
}

############################
# 🔐 Cognito Configuration
############################
variable "user_pool_settings" {
  description = "Configuration for Cognito user pool, including verification, username attributes, password policy, and schema"
  type = object({
    auto_verified_attributes = list(string)
    username_attributes      = list(string)
    password_policy = object({
      min_length         = number
      require_uppercase  = bool
      require_lowercase  = bool
      require_numbers    = bool
      require_symbols    = bool
      temp_validity_days = number
    })
    user_pool_schema = list(object({
      name                = string
      attribute_data_type = string
      mutable             = bool
      required            = bool
    }))
  })

  default = {
    auto_verified_attributes = ["email"]
    username_attributes      = ["email"]
    password_policy = {
      min_length         = 8
      require_uppercase  = true
      require_lowercase  = true
      require_numbers    = true
      require_symbols    = true
      temp_validity_days = 7
    }
    user_pool_schema = [
      { name = "email", attribute_data_type = "String", mutable = false, required = true },
      { name = "role", attribute_data_type = "String", mutable = false, required = false }
    ]
  }

  validation {
    condition     = var.user_pool_settings.password_policy.min_length >= 8 && length(var.user_pool_settings.username_attributes) > 0
    error_message = "user_pool_settings invalid: password minimum length must be >= 8 and username_attributes must include at least one attribute."
  }
}

variable "cognito_client_config" {
  description = "Full configuration for Cognito user pool client. Generate secret should be false for public clients using PKCE."
  type = object({
    generate_secret = bool
    oauth_settings = object({
      allowed_flows                = list(string)
      allowed_scopes               = list(string)
      allowed_flows_user_pool      = bool
      supported_identity_providers = list(string)
      explicit_auth_flows          = list(string)
      callback_urls                = list(string)
      logout_urls                  = list(string)
    })
    token_validity = object({
      refresh_token = number
      access_token  = number
      id_token      = number
      refresh_unit  = string
      access_unit   = string
      id_unit       = string
    })
  })
  default = {
    generate_secret = false
    oauth_settings = {
      allowed_flows                = ["code"]
      allowed_scopes               = ["email", "openid", "aws.cognito.signin.user.admin", "profile"]
      allowed_flows_user_pool      = true
      supported_identity_providers = ["COGNITO"]
      explicit_auth_flows          = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
      callback_urls                = ["https://google.com/", "https://example.com/oauth2/code"]
      logout_urls                  = ["http://localhost:4200/logout", "https://example.com/logout"]
    }
    token_validity = {
      refresh_token = 30
      access_token  = 6
      id_token      = 6
      refresh_unit  = "days"
      access_unit   = "hours"
      id_unit       = "hours"
    }
  }

  validation {
    condition = alltrue([
      var.cognito_client_config.generate_secret == false,
      contains(var.cognito_client_config.oauth_settings.allowed_flows, "code"),
      var.cognito_client_config.oauth_settings.allowed_flows_user_pool == true,
      alltrue([for u in var.cognito_client_config.oauth_settings.callback_urls : can(regex("^https?://", u))]),
      alltrue([for u in var.cognito_client_config.oauth_settings.logout_urls : can(regex("^https?://", u))]),
      contains(["minutes", "hours", "days"], var.cognito_client_config.token_validity.refresh_unit),
      contains(["minutes", "hours", "days"], var.cognito_client_config.token_validity.access_unit),
      contains(["minutes", "hours", "days"], var.cognito_client_config.token_validity.id_unit),
      var.cognito_client_config.token_validity.refresh_token > 0,
      var.cognito_client_config.token_validity.access_token > 0,
      var.cognito_client_config.token_validity.id_token > 0
    ])
    error_message = "cognito_client_config invalid: PKCE clients must not generate secrets; allowed_flows must include 'code'; callback/logout URLs must start with http(s); token units must be minutes/hours/days; token durations must be > 0."
  }
}

############################
# 🔗 Federated Identity Providers (explicit variables)
############################

# Google
variable "idp_google" {
  description = "Google IdP configuration"
  type = object({
    enabled          = bool
    client_id        = string
    client_secret    = string
    authorize_scopes = optional(string, "openid email profile")
  })
  default = {
    enabled          = false
    client_id        = ""
    client_secret    = ""
    authorize_scopes = "openid email profile"
  }
  validation {
    condition     = (var.idp_google.enabled == false) || (length(var.idp_google.client_id) > 0 && length(var.idp_google.client_secret) > 0)
    error_message = "When idp_google.enabled is true, client_id and client_secret must be provided."
  }
}

# Facebook
variable "idp_facebook" {
  description = "Facebook IdP configuration"
  type = object({
    enabled          = bool
    client_id        = string
    client_secret    = string
    authorize_scopes = optional(string, "email public_profile")
  })
  default = {
    enabled          = false
    client_id        = ""
    client_secret    = ""
    authorize_scopes = "email public_profile"
  }
  validation {
    condition     = (var.idp_facebook.enabled == false) || (length(var.idp_facebook.client_id) > 0 && length(var.idp_facebook.client_secret) > 0)
    error_message = "When idp_facebook.enabled is true, client_id and client_secret must be provided."
  }
}

# Login with Amazon
variable "idp_login_with_amazon" {
  description = "Login with Amazon IdP configuration"
  type = object({
    enabled          = bool
    client_id        = string
    client_secret    = string
    authorize_scopes = optional(string, "profile")
  })
  default = {
    enabled          = false
    client_id        = ""
    client_secret    = ""
    authorize_scopes = "profile"
  }
  validation {
    condition     = (var.idp_login_with_amazon.enabled == false) || (length(var.idp_login_with_amazon.client_id) > 0 && length(var.idp_login_with_amazon.client_secret) > 0)
    error_message = "When idp_login_with_amazon.enabled is true, client_id and client_secret must be provided."
  }
}

# Sign in with Apple
variable "idp_apple" {
  description = "Sign in with Apple IdP configuration"
  type = object({
    enabled          = bool
    client_id        = string   # Services ID
    team_id          = string
    key_id           = string
    private_key      = string
    authorize_scopes = optional(string, "name email")
  })
  default = {
    enabled          = false
    client_id        = ""
    team_id          = ""
    key_id           = ""
    private_key      = ""
    authorize_scopes = "name email"
  }
  validation {
    condition     = (var.idp_apple.enabled == false) || (length(var.idp_apple.client_id) > 0 && length(var.idp_apple.team_id) > 0 && length(var.idp_apple.key_id) > 0 && length(var.idp_apple.private_key) > 0)
    error_message = "When idp_apple.enabled is true, client_id, team_id, key_id, and private_key must be provided."
  }
}

# Generic OIDC providers (zero or more)
variable "idp_oidc_providers" {
  description = "List of OIDC IdPs to create"
  type = list(object({
    name                   = string
    issuer                 = string
    client_id              = string
    client_secret          = string
    authorize_scopes       = optional(string, "openid profile email")
    attributes_request_method = optional(string, "GET")
    authorize_url          = optional(string)
    token_url              = optional(string)
    attributes_url         = optional(string)
    jwks_uri               = optional(string)
    attribute_mapping      = optional(map(string))
  }))
  default = []
  validation {
    condition     = length(distinct([for p in var.idp_oidc_providers : p.name])) == length(var.idp_oidc_providers)
    error_message = "Each OIDC provider must have a unique 'name'."
  }
  validation {
    condition = alltrue([
      for p in var.idp_oidc_providers : (length(p.issuer) > 0 && length(p.client_id) > 0 && length(p.client_secret) > 0)
    ])
    error_message = "Each OIDC provider must include non-empty issuer, client_id, and client_secret."
  }
}

# SAML providers (zero or more)
variable "idp_saml_providers" {
  description = "List of SAML IdPs to create"
  type = list(object({
    name                        = string
    metadata_url                = optional(string)
    metadata_file               = optional(string)
    idp_init                    = optional(string)   # "true" or "false"
    encrypted_responses         = optional(string)   # "true" or "false"
    idp_signout                 = optional(string)   # "true" or "false"
    request_signing_algorithm   = optional(string, "rsa-sha256")
    attribute_mapping           = optional(map(string))
  }))
  default = []
  validation {
    condition     = length(distinct([for p in var.idp_saml_providers : p.name])) == length(var.idp_saml_providers)
    error_message = "Each SAML provider must have a unique 'name'."
  }
  validation {
    condition = alltrue([
      for p in var.idp_saml_providers : (try(length(p.metadata_url) > 0, false) || try(length(p.metadata_file) > 0, false))
    ])
    error_message = "Each SAML provider must include either metadata_url or metadata_file."
  }
}


variable "managed_login_version" {
  description = "Cognito managed login version"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["1", "2"], var.managed_login_version)
    error_message = "managed_login_version must be \"1\" or \"2\" to match supported Cognito managed login experience versions."
  }
}