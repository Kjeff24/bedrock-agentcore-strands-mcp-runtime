output "role_arn" {
  value       = aws_iam_role.gateway.arn
  description = "ARN of the gateway IAM role"
}

output "role_name" {
  value       = aws_iam_role.gateway.name
  description = "Name of the gateway IAM role"
}
