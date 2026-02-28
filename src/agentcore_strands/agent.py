import os
import warnings
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent
from strands.models.bedrock import BedrockModel
from strands.hooks import AgentInitializedEvent, HookProvider, MessageAddedEvent
from strands.tools.mcp.mcp_client import MCPClient
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from pathlib import Path

# Suppress deprecation warnings from websockets library
warnings.filterwarnings("ignore", category=DeprecationWarning, module="websockets")
warnings.filterwarnings("ignore", category=DeprecationWarning, module="uvicorn")

# Load the system prompt from system-prompt.md
PROMPT_PATH = Path(__file__).parent / "system-prompt.md"
SYSTEM_PROMPT = PROMPT_PATH.read_text(encoding="utf-8")

# Model configuration
MODEL_ID = os.environ.get("MODEL_ID", "eu.anthropic.claude-sonnet-4-20250514-v1:0")
MODEL_REGION = os.environ.get("MODEL_REGION", "eu-west-1")

# Gateway configuration
GATEWAY_URL = os.environ.get("GATEWAY_URL")
GATEWAY_AUTH_TYPE = os.environ.get("GATEWAY_AUTH_TYPE", "IAM")
JWT_TOKEN = os.environ.get("JWT_TOKEN")

# Memory configuration
MEMORY_ID = os.environ.get("MEMORY_ID")


class MemoryHook(HookProvider):
    def on_agent_initialized(self, event):
        if not MEMORY_ID:
            return
        from bedrock_agentcore.memory import MemoryClient
        memory_client = MemoryClient(region_name=MODEL_REGION)
        session_id = event.agent.state.get("session_id") or "default"
        turns = memory_client.get_last_k_turns(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=session_id,
            k=3
        )
        if turns:
            context = "\n".join([f"{m['role']}: {m['content']['text']}" for t in turns for m in t])
            event.agent.system_prompt += f"\n\nPrevious:\n{context}"

    def on_message_added(self, event):
        if not MEMORY_ID:
            return
        from bedrock_agentcore.memory import MemoryClient
        memory_client = MemoryClient(region_name=MODEL_REGION)
        msg = event.agent.messages[-1]
        session_id = event.agent.state.get("session_id") or "default"
        memory_client.create_event(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=session_id,
            messages=[(str(msg["content"]), msg["role"])]
        )

    def register_hooks(self, registry):
        registry.add_callback(AgentInitializedEvent, self.on_agent_initialized)
        registry.add_callback(MessageAddedEvent, self.on_message_added)


def create_mcp_transport():
    """Create MCP transport with appropriate authentication"""
    if not GATEWAY_URL:
        return None
    
    if GATEWAY_AUTH_TYPE == "JWT":
        from mcp.client.streamable_http import streamable_http_client
        def jwt_factory():
            headers = {"Authorization": f"Bearer {JWT_TOKEN}"}
            return streamable_http_client(GATEWAY_URL, headers=headers)
        return jwt_factory
    else:
        # AWS_IAM: Use mcp-proxy-for-aws for SigV4 signing
        def iam_factory():
            return aws_iam_streamablehttp_client(
                endpoint=GATEWAY_URL,
                aws_region=MODEL_REGION,
                aws_service="bedrock-agentcore"
            )
        return iam_factory


# Initialize Bedrock model
bedrock_model = BedrockModel(
    model_id=MODEL_ID,
    region_name=MODEL_REGION,
)

# Configure hooks
hooks = [MemoryHook()] if MEMORY_ID else []

# Get Gateway MCP client if configured
mcp_client = None
if GATEWAY_URL:
    try:
        mcp_factory = create_mcp_transport()
        mcp_client = MCPClient(mcp_factory)
        print(f"Initialized MCP client for Gateway")
    except Exception as e:
        print(f"Warning: Failed to connect to Gateway at {GATEWAY_URL}: {e}")
        print("Agent will start without Gateway tools")

# Create Strands agent
strands_agent = Agent(
    model=bedrock_model,
    system_prompt=SYSTEM_PROMPT,
    tools=[mcp_client] if mcp_client else [],
    hooks=hooks,
    state={"session_id": "default"}
)

# Initialize AgentCore app
app = BedrockAgentCoreApp()


@app.entrypoint
def invoke(payload):
    """Process user input and return a response"""
    print(f"Received payload: {payload}")
    # Extract the prompt string from nested structure
    input_data = payload.get("input", payload)
    user_message = input_data.get("prompt") if isinstance(input_data, dict) else input_data
    print(f"Extracted message: {user_message}")
    result = strands_agent(user_message)
    return {"result": str(result.message)}


if __name__ == "__main__":
    app.run()
