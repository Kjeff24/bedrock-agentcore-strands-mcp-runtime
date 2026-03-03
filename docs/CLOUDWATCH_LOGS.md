# CloudWatch Logs for AgentCore Runtime

## Automatic Logging

AgentCore Runtime **automatically creates and configures CloudWatch logs** when you deploy. No additional configuration needed in Terraform.

## Log Location

Your runtime logs are automatically sent to:

```
/aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT
```

Where `{runtime-id}` is the ID of your deployed runtime.

## Find Your Runtime ID

```bash
cd infra/terraform/runtime
terraform output runtime_id
```

## View Logs

### AWS Console
1. Go to CloudWatch → Log groups
2. Find `/aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT`
3. Click on log streams to view logs

### AWS CLI

**Tail logs in real-time:**
```bash
aws logs tail /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT --follow
```

**Filter for errors:**
```bash
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --filter-pattern "ERROR"
```

**Get recent logs:**
```bash
aws logs tail /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --since 1h
```

## What Gets Logged

All stdout/stderr from your container appears in CloudWatch:

```python
# In agent.py
print("Processing request...")  # ✅ Shows in CloudWatch
import logging
logging.info("Agent started")   # ✅ Shows in CloudWatch
```

## Add Structured Logging

```python
import sys
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)

logger = logging.getLogger(__name__)

@app.post("/invocations")
async def invoke_agent(request: InvocationRequest):
    logger.info(f"Received request: {request.input}")
    try:
        result = strands_agent(request.input.get("prompt"))
        logger.info("Request processed successfully")
        return InvocationResponse(output={"response": result})
    except Exception as e:
        logger.error(f"Error processing request: {e}", exc_info=True)
        raise
```

## Troubleshooting: No Logs Appearing

### 1. Check IAM Permissions

Your runtime IAM role needs CloudWatch permissions (already included in Terraform):

```hcl
resource "aws_iam_role_policy_attachment" "runtime_cloudwatch" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
```

### 2. Verify Runtime is Running

```bash
cd infra/terraform/runtime
terraform output runtime_status
```

Should show `ACTIVE`.

### 3. Invoke the Agent

Logs only appear when the agent is invoked:

```bash
# Get runtime ARN
RUNTIME_ARN=$(cd infra/terraform/runtime && terraform output -raw runtime_arn)

# Invoke via AWS CLI
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn $RUNTIME_ARN \
  --runtime-session-id $(uuidgen) \
  --payload '{"prompt":"test"}' \
  --qualifier DEFAULT \
  response.json
```

### 4. Check Log Group Exists

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/bedrock-agentcore/runtimes/
```

### 5. Check for Log Streams

```bash
aws logs describe-log-streams \
  --log-group-name /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --order-by LastEventTime \
  --descending \
  --max-items 5
```

## Common Log Patterns

### Invocation Logs
```bash
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --filter-pattern "/invocations"
```

### Error Logs
```bash
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

### Container Startup Logs
```bash
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --filter-pattern "healthy"
```

## CloudWatch Insights Queries

### Invocation Count Over Time
```
fields @timestamp, @message
| filter @message like /invocations/
| stats count() by bin(5m)
```

### Error Analysis
```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

### Response Time Analysis
```
fields @timestamp, @message
| filter @message like /Processing time/
| parse @message /Processing time: (?<duration>\d+)ms/
| stats avg(duration), max(duration), min(duration)
```

## Log Retention

Default retention is managed by AWS. To set custom retention:

```bash
aws logs put-retention-policy \
  --log-group-name /aws/bedrock-agentcore/runtimes/{runtime-id}-DEFAULT \
  --retention-in-days 7
```

## Enable Observability

For advanced tracing and monitoring, enable AgentCore Observability:

1. Follow [Enabling AgentCore runtime observability](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-configure.html)
2. View traces in CloudWatch Transaction Search
3. Monitor agent performance and tool usage

## Quick Reference

```bash
# Get runtime ID
RUNTIME_ID=$(cd infra/terraform/runtime && terraform output -raw runtime_id)

# Tail logs
aws logs tail /aws/bedrock-agentcore/runtimes/${RUNTIME_ID}-DEFAULT --follow

# Filter errors
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/runtimes/${RUNTIME_ID}-DEFAULT \
  --filter-pattern "ERROR"

# List log streams
aws logs describe-log-streams \
  --log-group-name /aws/bedrock-agentcore/runtimes/${RUNTIME_ID}-DEFAULT \
  --order-by LastEventTime \
  --descending
```
