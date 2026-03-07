variable "gateway_name" {
  type        = string
  description = "Name for the gateway"
}

variable "environment_name" {
  type        = string
  description = "Environment name"
}

variable "gateway_authorizer_type" {
  type        = string
  description = "Gateway authorizer type"
}

variable "role_arn" {
  type        = string
  description = "IAM role ARN for the gateway"
}

variable "gateway_jwt_config" {
  type = object({
    discovery_url    = string
    allowed_audience = list(string)
    allowed_clients  = list(string)
  })
  description = "JWT configuration"
  default     = null
}

variable "mcp_instructions" {
  type        = string
  description = "MCP instructions"
}

variable "mcp_search_type" {
  type        = string
  description = "MCP search type"
}

variable "mcp_supported_versions" {
  type        = list(string)
  description = "MCP protocol versions"
}

variable "add_mcp_target" {
  type        = bool
  description = "Whether to add MCP target"
}

variable "mcp_auth_type" {
  type        = string
  description = "MCP authentication type"
}

variable "mcp_server_endpoint" {
  type        = string
  description = "MCP server endpoint"
}

variable "api_key_secret_arn" {
  type        = string
  description = "API key secret ARN"
}

variable "api_key_header_name" {
  type        = string
  description = "API key header name"
}

variable "oauth_provider_arn" {
  type        = string
  description = "OAuth provider ARN"
}

variable "oauth_scopes" {
  type        = list(string)
  description = "OAuth scopes"
}

variable "oauth_grant_type" {
  type        = string
  description = "OAuth grant type"
}

variable "oauth_return_url" {
  type        = string
  description = "OAuth callback URL"
}
