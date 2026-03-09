# Strands Agent Integration

## Overview

This project uses [Strands](https://github.com/strands-agents/sdk-python) as the agent framework running inside an AWS Bedrock AgentCore Runtime container. Strands manages tool discovery, conversation state, and model calls. Atlassian MCP tools are connected via `MCPClient`.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  BedrockAgentCoreApp                                │
│  ┌──────────────────────────────────────────────┐  │
│  │  Strands Agent                               │  │
│  │  ├── BedrockModel (Claude via Bedrock)       │  │
│  │  ├── MCPClient → streamable_http_client      │  │
│  │  │   (Atlassian MCP, Bearer token)           │  │
│  │  └── MemoryHook (Bedrock AgentCore Memory)   │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Key Design: Tool Discovery at Construction Time

Strands discovers MCP tool definitions when `Agent()` is constructed, not lazily. You cannot append MCP clients to an existing agent instance — they must be in `tools=` at construction time.

This project handles it with a two-variant cache in `agent_factory.py`:

```python
# agent_factory.py
from strands import Agent
from strands.models.bedrock import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client

bedrock_model = BedrockModel(model_id=MODEL_ID, region_name=MODEL_REGION)

_agent_cache: dict[str, Agent] = {}

def get_agent(*, with_atlassian: bool = False) -> Agent:
    cache_key = "atlassian" if with_atlassian else "base"
    if cache_key not in _agent_cache:
        clients = []
        if with_atlassian:
            clients.append(MCPClient(create_atlassian_transport()))
        _agent_cache[cache_key] = Agent(
            model=bedrock_model,
            system_prompt=SYSTEM_PROMPT,
            tools=clients,
            hooks=hooks,
        )
    return _agent_cache[cache_key]
```

## Atlassian Transport (OAuth Bearer)

The Atlassian MCP transport reads the per-request token from a `ContextVar` (bound by `set_atlassian_token()` at request time):

```python
from mcp.client.streamable_http import streamable_http_client

def create_atlassian_transport():
    @asynccontextmanager
    async def _transport():
        token = EnvTokenProvider().get_access_token()  # reads ContextVar
        async with httpx.AsyncClient(
            headers={"Authorization": f"Bearer {token}"},
            timeout=..., follow_redirects=True
        ) as http_client:
            async with streamable_http_client(
                "https://mcp.atlassian.com/v1/mcp",
                http_client=http_client,
                terminate_on_close=True,
            ) as streams:
                yield streams
    return _transport
```

## Entrypoints

The runtime exposes two entrypoints via `BedrockAgentCoreApp`:

```python
from bedrock_agentcore.runtime import BedrockAgentCoreApp
app = BedrockAgentCoreApp()

@app.entrypoint
def invoke(payload: dict) -> dict:
    """Synchronous invocation."""
    atlassian_token = payload.get("atlassianToken")
    if atlassian_token:
        set_atlassian_token(atlassian_token)
    agent = get_agent(with_atlassian=bool(atlassian_token))
    result = agent(payload["prompt"])
    return {"result": result.message}

@app.entrypoint
async def invoke_stream(payload: dict, context=None):
    """Streaming invocation — yields event dicts."""
    ...
    async for event in agent.stream_async(user_message):
        yield event

@app.ping
def ping():
    from bedrock_agentcore.runtime import PingStatus
    return PingStatus.HEALTHY
```

## Deploy

```bash
cd infra/terraform/runtime
terraform apply \
  -var="container_image_uri=ACCOUNT.dkr.ecr.REGION.amazonaws.com/agentcore-strands-agent:latest"
```

The `MODEL_ID`, `MODEL_REGION`, and `MEMORY_ID` variables are configured in `terraform.tfvars`.

## References

- [Strands SDK](https://github.com/strands-agents/sdk-python)
- [Bedrock AgentCore Runtime docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime.html)
