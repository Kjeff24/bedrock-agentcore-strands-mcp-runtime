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

variable "runtime_name" {
  type        = string
  default     = "agentcore_runtime"
  description = "Runtime name (alphanumeric and underscore only)"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.runtime_name))
    error_message = "Runtime name must start with a letter and contain only alphanumeric and underscore characters (no hyphens)"
  }
}

variable "container_image_uri" {
  type        = string
  description = "ECR container image URI (use digest @sha256:... for automatic updates)"
  validation {
    condition     = can(regex("^\\d{12}\\.dkr\\.ecr\\.[a-z0-9\\-]+\\.amazonaws\\.com/.+[:|@].+$", var.container_image_uri))
    error_message = "Must be a valid ECR image URI with tag or digest"
  }
}

variable "force_redeploy" {
  type        = string
  default     = ""
  description = "Change this value to force redeployment (e.g., timestamp or git commit SHA)"
}

variable "network_mode" {
  type        = string
  default     = "PUBLIC"
  description = "Network mode for the runtime"
  validation {
    condition     = contains(["PUBLIC", "VPC"], var.network_mode)
    error_message = "Network mode must be PUBLIC or VPC"
  }
}

variable "protocol_type" {
  type        = string
  default     = "HTTP"
  description = "Protocol configuration"
  validation {
    condition     = contains(["MCP", "HTTP", "A2A"], var.protocol_type)
    error_message = "Protocol type must be MCP, HTTP, or A2A"
  }
}

variable "gateway_id" {
  type        = string
  default     = ""
  description = "Gateway ID to grant invoke access (optional)"
}

variable "memory_id" {
  type        = string
  default     = ""
  description = "Memory ID to grant access (optional)"
}

variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Additional environment variables for the agent container"
}

# JWT Authentication Configuration
variable "jwt_issuer" {
  description = "JWT issuer URL (Cognito authority)"
  type        = string
  default     = ""
}

variable "jwt_audience" {
  description = "JWT audience (Cognito client ID)"
  type        = string
  default     = ""
}
