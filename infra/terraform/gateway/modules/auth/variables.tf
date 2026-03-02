variable "gateway_name" {
  type        = string
  description = "Name for the gateway"
}

variable "region_name" {
  type        = string
  description = "AWS region name"
}

variable "use_api_key" {
  type        = bool
  description = "Whether to create API key resources"
}

variable "use_oauth" {
  type        = bool
  description = "Whether to create OAuth resources"
}

variable "api_key_config" {
  type = object({
    secret_arn  = string
    value       = string
    header_name = string
  })
  description = "API key configuration"
}

variable "oauth_config" {
  type = object({
    provider_vendor        = string
    issuer                 = string
    authorization_endpoint = string
    token_endpoint         = string
    response_types         = list(string)
    client_id              = string
    client_secret          = string
    scopes                 = list(string)
    callback_urls          = list(string)
  })
  description = "OAuth configuration"
}
