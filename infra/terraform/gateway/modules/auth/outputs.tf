output "api_key_secret_arn" {
  value       = var.use_api_key ? local.api_key_secret_arn : ""
  description = "ARN of the API key secret"
}

output "oauth_provider_arn" {
  value       = var.use_oauth ? aws_bedrockagentcore_oauth2_credential_provider.this[0].credential_provider_arn : ""
  description = "ARN of the OAuth credential provider"
}

output "workload_identity_arn" {
  value       = var.use_oauth ? aws_bedrockagentcore_workload_identity.this[0].workload_identity_arn : ""
  description = "ARN of the workload identity"
}
