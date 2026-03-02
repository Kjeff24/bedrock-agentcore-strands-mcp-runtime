variable "gateway_name" {
  type        = string
  description = "Name for the gateway"
}

variable "account_id" {
  type        = string
  description = "AWS account ID"
}

variable "use_api_key" {
  type        = bool
  description = "Whether API key authentication is used"
}

variable "api_key_secret_arn" {
  type        = string
  description = "ARN of the API key secret"
}
