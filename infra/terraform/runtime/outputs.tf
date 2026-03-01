output "runtime_id" {
  description = "Runtime ID"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
}

output "runtime_arn" {
  description = "Runtime ARN"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_arn
}

output "runtime_version" {
  description = "Runtime version"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_version
}

output "cloudwatch_logs_command" {
  description = "Command to stream CloudWatch logs"
  value       = "aws logs tail /aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.this.agent_runtime_id}-DEFAULT --follow --region ${var.aws_region}"
}
