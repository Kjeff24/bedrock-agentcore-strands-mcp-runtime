"""Agent factory that creates and caches Strands Agent instances.

Strands discovers MCP tool definitions at ``Agent`` construction time.  The
Atlassian ``MCPClient`` must therefore be present in the ``tools`` list when
the ``Agent`` is first instantiated – appending to the list afterwards has no
effect.  To handle this, two agent variants are cached:

- ``"base"``      – no MCP tools (no Atlassian token available)
- ``"atlassian"`` – Atlassian MCP (token was supplied by the frontend)
"""
import logging
from strands import Agent
from strands.models.bedrock import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient

from .config import MEMORY_ID, MODEL_ID, MODEL_REGION, SYSTEM_PROMPT
from .hooks import MemoryHook
from .transport import create_atlassian_transport

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Shared model + hooks
# ---------------------------------------------------------------------------
bedrock_model = BedrockModel(model_id=MODEL_ID, region_name=MODEL_REGION)
hooks = [MemoryHook()] if MEMORY_ID else []

# ---------------------------------------------------------------------------
# Agent cache
# ---------------------------------------------------------------------------
_agent_cache: dict[str, Agent] = {}


def get_agent(*, with_atlassian: bool = False) -> Agent:
    """Return (and lazily create) a cached ``Agent`` for the requested variant.

    Args:
        with_atlassian: When ``True``, the returned agent includes the
            Atlassian MCP client so Atlassian tools are discoverable.
    """
    cache_key = "atlassian" if with_atlassian else "base"

    if cache_key not in _agent_cache:
        clients: list[MCPClient] = []

        if with_atlassian:
            atlassian_transport = create_atlassian_transport()
            clients.append(MCPClient(atlassian_transport))
            logger.info("Atlassian MCP client added to new agent instance")

        _agent_cache[cache_key] = Agent(
            model=bedrock_model,
            system_prompt=SYSTEM_PROMPT,
            tools=clients,
            hooks=hooks,
        )
        logger.info(
            "Created agent instance (key=%s, tools=%d)", cache_key, len(clients)
        )

    return _agent_cache[cache_key]
