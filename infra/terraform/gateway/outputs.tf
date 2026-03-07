output "gateway_id" {
  description = "Gateway identifier"
  value       = module.gateway.gateway_id
}

output "gateway_arn" {
  description = "Gateway ARN"
  value       = module.gateway.gateway_arn
}

output "gateway_url" {
  description = "Gateway URL for Strands agent"
  value       = module.gateway.gateway_url
}

output "gateway_role_arn" {
  description = "Gateway IAM role ARN"
  value       = module.iam.role_arn
}

output "workload_identity_arn" {
  description = "Workload Identity ARN"
  value       = local.use_oauth ? module.auth[0].workload_identity_arn : null
}

output "api_key_secret_arn" {
  description = "API Key Secret ARN (if created)"
  value       = local.use_api_key ? module.auth[0].api_key_secret_arn : null
  sensitive   = true
}
