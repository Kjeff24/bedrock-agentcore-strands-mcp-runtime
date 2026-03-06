"""Strands agent lifecycle hooks."""
import logging
from strands.hooks import AgentInitializedEvent, HookProvider, MessageAddedEvent
from .config import MEMORY_ID, MODEL_REGION

logger = logging.getLogger(__name__)


class MemoryHook(HookProvider):
    """Reads recent conversation turns from Bedrock AgentCore Memory on agent
    initialisation and persists each new message after it is added."""

    def on_agent_initialized(self, event: AgentInitializedEvent) -> None:
        if not MEMORY_ID:
            return
        from bedrock_agentcore.memory import MemoryClient

        memory_client = MemoryClient(region_name=MODEL_REGION)
        session_id = event.agent.state.get("session_id") or "default"
        turns = memory_client.get_last_k_turns(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=session_id,
            k=3,
        )
        if turns:
            context = "\n".join(
                f"{m['role']}: {m['content']['text']}" for t in turns for m in t
            )
            event.agent.system_prompt += f"\n\nPrevious:\n{context}"

    def on_message_added(self, event: MessageAddedEvent) -> None:
        if not MEMORY_ID:
            return
        from bedrock_agentcore.memory import MemoryClient

        msg = event.agent.messages[-1]
        role = msg.get("role", "")
        content = msg.get("content", "")

        # Only persist plain user/assistant turns.  Tool-use and tool-result
        # messages are internal scaffolding — they are often very large and
        # not useful as conversation history.
        if role not in ("user", "assistant"):
            return

        if isinstance(content, list):
            # Skip any message whose content list contains tool blocks
            if any(isinstance(c, dict) and ("toolUse" in c or "toolResult" in c) for c in content):
                return
            # Flatten text-only content blocks into a single string
            text = " ".join(
                c["text"] for c in content if isinstance(c, dict) and "text" in c
            )
        else:
            text = str(content)

        if not text:
            return

        # The CreateEvent API rejects payloads where content.text exceeds
        # 100 000 characters.  Truncate with a marker so history is still
        # useful but the call never fails.
        _MAX_TEXT = 99_000
        if len(text) > _MAX_TEXT:
            text = text[:_MAX_TEXT] + " … [truncated]"

        memory_client = MemoryClient(region_name=MODEL_REGION)
        session_id = event.agent.state.get("session_id") or "default"
        try:
            memory_client.create_event(
                memory_id=MEMORY_ID,
                actor_id="user",
                session_id=session_id,
                messages=[(text, role)],
            )
        except Exception:
            logger.exception("Failed to persist message to memory (session=%s)", session_id)

    def register_hooks(self, registry) -> None:
        registry.add_callback(AgentInitializedEvent, self.on_agent_initialized)
        registry.add_callback(MessageAddedEvent, self.on_message_added)
