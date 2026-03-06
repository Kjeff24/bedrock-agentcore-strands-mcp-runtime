"""AgentCore Runtime entry point.

All heavy lifting is delegated to focused modules:
  config        – environment variables & system prompt
  hooks         – MemoryHook (Strands lifecycle callbacks)
  transport     – EnvTokenProvider + MCP transport factories
  agent_factory – get_agent() (cached Agent variants)
  utils         – clean_text / clean_message_payload
"""
import logging
import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp

from .agent_factory import get_agent
from .utils import clean_message_payload, clean_text

logger = logging.getLogger(__name__)

app = BedrockAgentCoreApp()


# ---------------------------------------------------------------------------
# Helpers shared by both entrypoints
# ---------------------------------------------------------------------------

def _extract_user_message(payload: dict) -> str | None:
    """Pull the prompt string out of the (potentially nested) request payload."""
    input_data = payload.get("input", payload)
    if isinstance(input_data, dict):
        return input_data.get("prompt")
    return input_data


def _set_atlassian_token(payload: dict) -> str | None:
    """Inject the Atlassian token from the payload into the environment."""
    token = payload.get("atlassianToken")
    if token:
        os.environ["ATLASSIAN_ACCESS_TOKEN"] = token
    return token


def _normalise_result(result) -> dict:
    """Convert a Strands agent result into a JSON-serialisable message dict."""
    message = result.message
    if isinstance(message, (dict, list)):
        return clean_message_payload(message)
    return {
        "role": "assistant",
        "content": [{"text": clean_text(message)}],
    }


# ---------------------------------------------------------------------------
# Entrypoints
# ---------------------------------------------------------------------------

@app.entrypoint
def invoke(payload: dict) -> dict:
    """Synchronous (non-streaming) entrypoint."""
    logger.info("Received payload: %s", payload)
    atlassian_token = _set_atlassian_token(payload)
    agent = get_agent(with_atlassian=bool(atlassian_token))
    user_message = _extract_user_message(payload)
    logger.info("Extracted message: %s", user_message)
    return {"result": _normalise_result(agent(user_message))}


@app.entrypoint
async def invoke_stream(payload: dict, context=None):
    """Streaming entrypoint that yields Bedrock-compatible event dicts."""
    logger.info("Received streaming payload: %s", payload)
    atlassian_token = _set_atlassian_token(payload)
    agent = get_agent(with_atlassian=bool(atlassian_token))
    user_message = _extract_user_message(payload)

    if not user_message:
        yield {"error": "No prompt provided"}
        return

    if hasattr(agent, "stream_async"):
        async for event in _stream_events(agent, user_message, context):
            yield event
    else:
        async for event in _stream_fallback(agent, user_message):
            yield event


# ---------------------------------------------------------------------------
# Streaming helpers
# ---------------------------------------------------------------------------

async def _stream_events(agent, user_message: str, context):
    """Forward filtered/cleaned events from agent.stream_async."""
    tool_block_indices: set[int] = set()
    try:
        async for event in agent.stream_async(
            user_message, invocation_state={"context": context}
        ):
            if not ("event" in event or "message" in event or "error" in event):
                continue

            if "event" in event:
                evt = event["event"]
                filtered, tool_block_indices = _filter_tool_event(evt, tool_block_indices)
                if filtered:
                    continue
                _clean_delta(evt)

            if "message" in event:
                if _is_tool_message(event["message"]):
                    continue
                _clean_message_content(event["message"])

            yield event
    except Exception as exc:
        yield {"error": f"Streaming failed: {exc}"}


def _filter_tool_event(evt: dict, indices: set[int]) -> tuple[bool, set[int]]:
    """Return (should_skip, updated_indices) for a raw event dict."""
    if "contentBlockStart" in evt:
        start = evt["contentBlockStart"].get("start", {})
        if "toolUse" in start:
            idx = evt["contentBlockStart"].get("contentBlockIndex")
            logger.info(
                "MCP toolUse started: name=%s index=%s",
                start.get("name"),
                idx,
            )
            return True, indices | {idx}

    if "contentBlockDelta" in evt and "toolUse" in evt["contentBlockDelta"].get("delta", {}):
        return True, indices

    if "contentBlockStop" in evt:
        idx = evt["contentBlockStop"].get("contentBlockIndex")
        if idx in indices:
            logger.info("MCP toolUse finished: index=%s", idx)
            return True, indices - {idx}

    if "messageStop" in evt and evt["messageStop"].get("stopReason") == "tool_use":
        return True, indices

    return False, indices


def _is_tool_message(message: dict) -> bool:
    content = message.get("content", [])
    return isinstance(content, list) and any(
        "toolResult" in item or "toolUse" in item for item in content
    )


def _clean_message_content(message: dict) -> None:
    message["content"] = [
        {**item, "text": clean_text(item["text"])}
        if isinstance(item, dict) and "text" in item
        else item
        for item in message.get("content", [])
    ]


def _clean_delta(evt: dict) -> None:
    """Strip tool markup from incremental contentBlockDelta text in-place."""
    if not isinstance(evt, dict):
        return
    delta = evt.get("contentBlockDelta", {}).get("delta")
    if isinstance(delta, dict) and "text" in delta:
        delta["text"] = clean_text(delta["text"], preserve_whitespace=True)


async def _stream_fallback(agent, user_message: str):
    """One-shot fallback for agents that don't support stream_async."""
    try:
        result_payload = _normalise_result(agent(user_message))
        if isinstance(result_payload, dict) and "content" in result_payload:
            yield {"message": clean_message_payload(result_payload)}
        else:
            yield {
                "message": {
                    "role": "assistant",
                    "content": [{"text": clean_text(str(result_payload))}],
                }
            }
    except Exception as exc:
        yield {"error": f"Invocation failed: {exc}"}


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.ping
def ping():
    from bedrock_agentcore.runtime import PingStatus
    return PingStatus.HEALTHY


# ---------------------------------------------------------------------------
# Local run
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    logger.info("🚀 Starting AgentCore Runtime...")
    logger.info("   Health check: /ping")
    logger.info("   Ready to receive requests at /invocations")
    try:
        app.run()
    except Exception as exc:
        logger.exception("Failed to start: %s", exc)
        import traceback
        traceback.print_exc()
