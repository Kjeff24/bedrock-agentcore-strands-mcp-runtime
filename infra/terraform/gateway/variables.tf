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

variable "gateway_name" {
  type        = string
  default     = "agentcore-gateway"
  description = "Gateway name"
}

variable "gateway_authorizer_type" {
  type        = string
  default     = "AWS_IAM"
  description = "Gateway authorizer type"
  validation {
    condition     = contains(["AWS_IAM", "CUSTOM_JWT"], var.gateway_authorizer_type)
    error_message = "Authorizer type must be AWS_IAM or CUSTOM_JWT"
  }
}

variable "gateway_jwt_config" {
  type = object({
    discovery_url    = string
    allowed_audience = optional(set(string), [])
    allowed_clients  = optional(set(string), [])
  })
  default     = null
  description = "Gateway JWT authorizer configuration (required when gateway_authorizer_type=CUSTOM_JWT)"

  validation {
    condition     = var.gateway_authorizer_type != "CUSTOM_JWT" || var.gateway_jwt_config != null
    error_message = "gateway_jwt_config is required when gateway_authorizer_type is CUSTOM_JWT"
  }
}

variable "mcp_instructions" {
  type        = string
  default     = "MCP server providing tools for the Strands agent"
  description = "Instructions for agent tool usage"
}

variable "mcp_search_type" {
  type        = string
  default     = "SEMANTIC"
  description = "Search type for MCP"
  validation {
    condition     = contains(["SEMANTIC", "HYBRID"], var.mcp_search_type)
    error_message = "Search type must be SEMANTIC or HYBRID"
  }
}

variable "mcp_supported_versions" {
  type        = list(string)
  default     = ["2025-03-26"]
  description = "MCP protocol versions to support"

  validation {
    condition = alltrue([
      for v in var.mcp_supported_versions : contains(["2025-11-25", "2025-03-26", "2025-06-18"], v)
    ])
    error_message = "MCP versions must be one of: 2025-11-25, 2025-03-26, 2025-06-18."
  }
}

variable "add_mcp_target" {
  type        = bool
  default     = false
  description = "Add an MCP server target to the gateway"
}

variable "mcp_server_endpoint" {
  type        = string
  default     = ""
  description = "HTTPS endpoint of MCP server"
  validation {
    condition     = var.mcp_server_endpoint == "" || can(regex("^https://", var.mcp_server_endpoint))
    error_message = "MCP server endpoint must be an HTTPS URL or empty"
  }
}

variable "mcp_auth_type" {
  type        = string
  default     = "IAM"
  description = "MCP server authentication type"
  validation {
    condition     = contains(["API_KEY", "OAUTH", "IAM"], var.mcp_auth_type)
    error_message = "Auth type must be API_KEY, OAUTH, or IAM"
  }
}

variable "mcp_api_key_config" {
  type = object({
    secret_arn  = optional(string, "")
    value       = optional(string, "")
    header_name = optional(string, "X-API-Key")
  })
  default = {
    secret_arn  = ""
    value       = ""
    header_name = "X-API-Key"
  }
  sensitive   = true
  description = "MCP API key configuration (secret_arn or value required for API_KEY auth)"
}

variable "mcp_oauth_config" {
  type = object({
    provider_vendor        = optional(string, "CustomOauth2")
    issuer                 = optional(string, "")
    authorization_endpoint = optional(string, "")
    token_endpoint         = optional(string, "")
    response_types         = optional(list(string), [])
    client_id              = optional(string, "")
    client_secret          = optional(string, "")
    scopes                 = optional(list(string), [])
    callback_urls          = optional(list(string), [])
    grant_type             = optional(string, "CLIENT_CREDENTIALS")
    return_url             = optional(string, "")
  })
  default     = null
  sensitive   = true
  description = "MCP OAuth configuration (required for OAUTH auth)"

  validation {
    condition = var.mcp_oauth_config == null || (
      var.mcp_oauth_config.provider_vendor != "" &&
      var.mcp_oauth_config.client_id != "" &&
      contains(["CLIENT_CREDENTIALS", "AUTHORIZATION_CODE"], var.mcp_oauth_config.grant_type) &&
      (var.mcp_oauth_config.grant_type != "AUTHORIZATION_CODE" || var.mcp_oauth_config.return_url != "") &&
      (
        var.mcp_oauth_config.provider_vendor != "CustomOauth2" ||
        (
          var.mcp_oauth_config.issuer != "" &&
          var.mcp_oauth_config.authorization_endpoint != "" &&
          var.mcp_oauth_config.token_endpoint != ""
        )
      )
    )
    error_message = "OAuth config requires: provider_vendor, client_id, valid grant_type. AUTHORIZATION_CODE requires return_url. CustomOauth2 requires: issuer, authorization_endpoint, token_endpoint."
  }
}
