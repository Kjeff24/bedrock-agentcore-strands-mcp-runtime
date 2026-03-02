output "gateway_id" {
  value       = aws_bedrockagentcore_gateway.this.gateway_id
  description = "ID of the gateway"
}

output "gateway_arn" {
  value       = aws_bedrockagentcore_gateway.this.gateway_arn
  description = "ARN of the gateway"
}

output "gateway_url" {
  value       = aws_bedrockagentcore_gateway.this.gateway_url
  description = "URL of the gateway"
}
