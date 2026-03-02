output "memory_id" {
  value       = aws_bedrockagentcore_memory.this.id
  description = "The ID of the created memory resource"
}

output "memory_arn" {
  value       = aws_bedrockagentcore_memory.this.arn
  description = "The ARN of the created memory resource"
}

output "memory_name" {
  value       = aws_bedrockagentcore_memory.this.name
  description = "The name of the created memory resource"
}
