# Integrating AgentCore Gateway with Strands Agent

## Overview
The AgentCore Gateway acts as an MCP server that your Strands agent can connect to for accessing tools and resources.

## Step 1: Deploy the Gateway

```bash
cd infra/terraform/gateway

terraform init
terraform apply \
  -var="gateway_name=my-gateway" \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://mcp-server.example.com" \
  -var="mcp_auth_type=API_KEY" \
  -var='mcp_api_key_config={value="your-api-key"}'
```

Get the Gateway URL:
```bash
terraform output gateway_url
```

## Step 2: Configure Your Strands Agent

In your Strands agent code, configure the MCP client to connect to the gateway:

```python
from strands import Agent
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

# Gateway URL from CloudFormation output
GATEWAY_URL = "https://your-gateway-url.amazonaws.com"

async def setup_agent():
    # Create MCP client session connected to the gateway
    async with stdio_client(
        StdioServerParameters(
            command="curl",
            args=["-X", "POST", GATEWAY_URL],
            env={"AWS_REGION": "us-east-1"}
        )
    ) as (read, write):
        async with ClientSession(read, write) as session:
            # Initialize the session
            await session.initialize()
            
            # List available tools from the gateway
            tools = await session.list_tools()
            
            # Create your Strands agent with the MCP tools
            agent = Agent(
                name="my-strands-agent",
                mcp_session=session,
                tools=tools
            )
            
            return agent
```

## Step 3: Use Gateway in Agent Runtime

If deploying your Strands agent on AgentCore Runtime, set the gateway URL as an environment variable in your Terraform configuration:

```hcl
# In infra/terraform/runtime/main.tf or via variables
terraform apply \
  -var="runtime_name=my-strands-agent" \
  -var="container_image_uri=123456789012.dkr.ecr.us-east-1.amazonaws.com/strands-agent:latest" \
  -var="gateway_id=your-gateway-id"
```

Then in your agent container:
```python
import os
from strands import Agent

gateway_url = os.environ["GATEWAY_URL"]
agent = Agent.from_mcp_gateway(gateway_url)
```

## Step 4: Add MCP Tools to Gateway

The gateway needs to be connected to actual MCP servers. Configure this when deploying the gateway:

```bash
terraform apply \
  -var="add_mcp_target=true" \
  -var="mcp_server_endpoint=https://your-mcp-server.com" \
  -var="mcp_auth_type=OAUTH" \
  -var='mcp_oauth_config={provider_vendor="GoogleOauth2",client_id="your-id",client_secret="your-secret",scopes=["read","write"]}'
```

## Authentication

The gateway uses AWS_IAM authentication. Your Strands agent needs AWS credentials:

```python
import boto3

# Use AWS credentials to sign requests to the gateway
session = boto3.Session()
credentials = session.get_credentials()
```

Or use IAM roles if running on AgentCore Runtime (automatic).
