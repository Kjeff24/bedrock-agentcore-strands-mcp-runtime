# Integrating Atlassian MCP with a Strands Agent on AgentCore Runtime (Backend)

This guide explains exactly how to wire Atlassian's hosted MCP server (`https://mcp.atlassian.com/v1/mcp`) into any Strands agent that will run inside AWS Bedrock AgentCore Runtime.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Authentication Model](#authentication-model)
4. [Module Breakdown](#module-breakdown)
   - [transport.py — token & transport factory](#transportpy--token--transport-factory)
   - [agent_factory.py — cached agent variants](#agent_factorypy--cached-agent-variants)
   - [hooks.py — memory lifecycle](#hookspy--memory-lifecycle)
   - [agent.py — entrypoints](#agentpy--entrypoints)
5. [Why ContextVar, not os.environ](#why-contextvar-not-osenviron)
6. [Why Two Cached Agent Variants](#why-two-cached-agent-variants)
7. [Request Payload Contract](#request-payload-contract)
8. [Streaming vs Non-Streaming](#streaming-vs-non-streaming)
9. [Local Development](#local-development)
10. [Dependencies](#dependencies)
11. [References](#references)

---

## Overview

Atlassian exposes Jira, Confluence, and Rovo tools through a hosted [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server. A Strands agent connects to this server over `StreamableHTTP`, authenticating each request with a short-lived user OAuth Bearer token.

The integration has three layers:

```
┌───────────────┐      HTTP POST     ┌─────────────────┐     StreamableHTTP     ┌──────────────────────┐
│   Caller      │──{ prompt, token }─▶  AgentCore       │──Bearer <user_token>──▶  Atlassian MCP Server │
│  (frontend    │                    │  Runtime         │                        │  mcp.atlassian.com   │
│   / script)   │◀──  response  ─────│  (Strands Agent) │◀── tool results ───────│  (Jira, Confluence…) │
└───────────────┘                    └─────────────────┘                        └──────────────────────┘
```

The key design decisions are:

- **No server-side Atlassian credentials.** The runtime holds nothing. Tokens come in per-request from the caller.
- **`ContextVar` for token isolation.** Async-safe; concurrent requests never bleed tokens.
- **Two cached agent variants.** Strands discovers MCP tools at `Agent()` construction time — tools cannot be added later. So a separate cached instance exists for the Atlassian-enabled path.

---

## Prerequisites

- Python ≥ 3.10
- `strands-agents` with `BedrockModel` and `MCPClient`
- `bedrock-agentcore` (`BedrockAgentCoreApp`)
- `mcp-proxy-for-aws` (provides the `streamable_http_client`)
- `httpx`
- An Atlassian Cloud account with API access and an OAuth 2.0 (3LO) app configured

---

## Authentication Model

Atlassian's MCP server uses **OAuth 2.0 Bearer tokens**. Each caller (e.g., your frontend) must obtain a short-lived user access token directly from Atlassian (via Authorization Code + PKCE) and pass it with every request.

```
┌──────────────┐          ┌─────────────────────┐          ┌────────────────────┐
│  Caller      │          │  AgentCore Runtime  │          │  Atlassian         │
└──────┬───────┘          └──────────┬──────────┘          └────────┬───────────┘
       │                             │                               │
       │  OAuth 2.0 PKCE (direct)   │                               │
       │◀──────────────────────────────────────────────────────────▶│
       │  access_token obtained      │                               │
       │                             │                               │
       │  POST /invocations          │                               │
       │  { prompt, atlassianToken } │                               │
       │────────────────────────────▶│                               │
       │                             │  set_atlassian_token(token)   │
       │                             │  (stored in ContextVar)       │
       │                             │                               │
       │                             │  GET /v1/mcp                  │
       │                             │  Authorization: Bearer <token>│
       │                             │──────────────────────────────▶│
       │                             │◀──── MCP tools / results ─────│
       │◀──── response ──────────────│                               │
```

**The runtime never stores, caches, or logs the token.** It is bound to the async context for one invocation and discarded.

---

## Module Breakdown

### `transport.py` — token & transport factory

This module owns two responsibilities: request-scoped token storage, and the factory function that creates an `httpx`-based MCP transport.

#### 1. ContextVar token store

```python
from contextvars import ContextVar

_atlassian_token: ContextVar[str | None] = ContextVar("atlassian_token", default=None)

def set_atlassian_token(token: str) -> None:
    """Bind token to the current async context (one invocation)."""
    _atlassian_token.set(token)
```

> Call `set_atlassian_token()` at the very start of every `@app.entrypoint` handler,
> before `get_agent()` is called.

#### 2. Token provider class

```python
class EnvTokenProvider:
    def get_access_token(self) -> str:
        token = _atlassian_token.get() or os.environ.get("ATLASSIAN_ACCESS_TOKEN")
        if not token:
            raise RuntimeError("Atlassian access token is not set")
        return token
```

The provider reads exclusively from the `ContextVar`. There is no `os.environ` fallback — `os.environ` is process-global and unsafe under concurrent requests.

#### 3. Transport factory

```python
from contextlib import asynccontextmanager
import httpx
from mcp.client.streamable_http import streamable_http_client

_ATLASSIAN_MCP_URL = "https://mcp.atlassian.com/v1/mcp"

def create_atlassian_transport():
    @asynccontextmanager
    async def _transport():
        token = EnvTokenProvider().get_access_token()
        headers = {"Authorization": f"Bearer {token}"}
        async with streamable_http_client(
            _ATLASSIAN_MCP_URL,
            headers=headers,
            timeout=...,
            sse_read_timeout=...,
        ) as (read, write):
            yield read, write

    return _transport
```

The factory **returns a function** (not a live connection). `MCPClient` calls it at agent initialisation time. Because the `ContextVar` is read inside `_transport()` — which runs at invocation time, not at import time — the correct per-request token is always used even though the agent instance is cached.

---

### `agent_factory.py` — cached agent variants

Strands' `Agent` class calls MCP tool discovery (`list_tools`) at construction time. This means **you cannot add an `MCPClient` to an already-constructed agent**. The solution is two variants:

| Cache key     | `tools=`                  | When used                          |
|---------------|---------------------------|------------------------------------|
| `"base"`      | `[]`                      | No Atlassian token in the request  |
| `"atlassian"` | `[MCPClient(transport)]`  | Atlassian token present            |

```python
from strands import Agent
from strands.models.bedrock import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient

from .transport import create_atlassian_transport

_agent_cache: dict[str, Agent] = {}

def get_agent(*, with_atlassian: bool = False) -> Agent:
    cache_key = "atlassian" if with_atlassian else "base"

    if cache_key not in _agent_cache:
        clients: list[MCPClient] = []

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

**Important:** `create_atlassian_transport()` is called during agent construction (first warm-up of the `"atlassian"` variant). It returns a factory function, not a live connection — the actual HTTP connection to Atlassian is opened per-invocation by `MCPClient` when it calls the transport. This is what makes the cached agent + per-request token combination work correctly.

---

### `hooks.py` — memory lifecycle

`MemoryHook` is a Strands `HookProvider` that integrates with **Bedrock AgentCore Memory**. It is wired into both cached agent variants via the `hooks=` argument in `get_agent()`.

Two Strands lifecycle events are handled:

| Event | What happens |
|---|---|
| `AgentInitializedEvent` | Loads the last 3 conversation turns from memory and injects them into the system prompt |
| `MessageAddedEvent` | Persists each new user/assistant message to memory |

#### Loading history on agent initialization

At the start of every invocation, Strands fires `AgentInitializedEvent`. The hook reads recent turns from AgentCore Memory scoped to the current `session_id` (the caller's Cognito `sub`) and prepends them to the system prompt:

```python
class MemoryHook(HookProvider):

    def __init__(self) -> None:
        if MEMORY_ID:
            from bedrock_agentcore.memory import MemoryClient
            self._client = MemoryClient(region_name=MODEL_REGION)
        else:
            self._client = None

    def on_agent_initialized(self, event: AgentInitializedEvent) -> None:
        if not self._client:
            return

        session_id = get_session_id()   # reads the ContextVar set by set_session_id()
        turns = self._client.get_last_k_turns(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=session_id,
            k=3,                        # last 3 turns = up to 6 messages
        )
        if turns:
            context = "\n".join(
                f"{m['role']}: {m['content']['text']}" for t in turns for m in t
            )
            # Replace (not append) so the cached agent's system prompt doesn't
            # grow on every warm-cache hit.
            event.agent.system_prompt = SYSTEM_PROMPT + f"\n\nPrevious:\n{context}"
```

> **Why replace, not append?** The agent instance is cached and reused. If history were appended to `system_prompt`, each warm-cache request would accumulate the previous request's history on top of the current one, producing an ever-growing, stale prompt. Replacing it with a fresh `SYSTEM_PROMPT + new_context` on every `AgentInitializedEvent` keeps the injected context correct and bounded.

#### Persisting messages after each turn

After every message is added to the agent's conversation (user prompt, assistant response, tool calls, tool results), Strands fires `MessageAddedEvent`. The hook filters aggressively before writing to memory:

```python
    def on_message_added(self, event: MessageAddedEvent) -> None:
        if not self._client:
            return

        msg  = event.agent.messages[-1]
        role = msg.get("role", "")

        # Only persist plain user/assistant turns.
        # Tool-use and tool-result messages are MCP scaffolding — they are
        # often very large and are not useful as conversation history.
        if role not in ("user", "assistant"):
            return

        content = msg.get("content", "")
        if isinstance(content, list):
            # Skip messages whose content contains tool blocks (toolUse / toolResult)
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

        # AgentCore Memory rejects payloads where content.text > 100 000 chars.
        _MAX_TEXT = 99_000
        if len(text) > _MAX_TEXT:
            text = text[:_MAX_TEXT] + " … [truncated]"

        session_id = get_session_id()
        self._client.create_event(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=session_id,
            messages=[(text, role)],
        )
```

**What is stored vs. filtered:**

| Message type | Stored? | Reason |
|---|---|---|
| `role: user` — plain text | ✅ Yes | Core conversation history |
| `role: assistant` — plain text | ✅ Yes | Core conversation history |
| `role: assistant` — contains `toolUse` | ❌ No | MCP tool call scaffolding — large, not useful as history |
| `role: user` — contains `toolResult` | ❌ No | MCP tool result payload — large, not useful as history |
| Any other role | ❌ No | Not a conversation turn |

> ⚠️ **Important for developers: MCP tool messages must be filtered from memory.**
>
> When a Strands agent uses an MCP tool (e.g. a Jira search via Atlassian MCP), Strands adds **two extra messages** to the conversation:
> 1. An `assistant` message with a `toolUse` block — the agent's decision to call the tool and its arguments.
> 2. A `user` message with a `toolResult` block — the raw response from the MCP server.
>
> These messages fire `MessageAddedEvent` just like normal conversation turns. **If you write every `MessageAddedEvent` to AgentCore Memory without filtering**, tool messages will be persisted. This causes two problems:
> - **Size:** MCP tool results (e.g. a full Jira issue list) can be hundreds of kilobytes. AgentCore Memory's `CreateEvent` API rejects payloads where `content.text` exceeds 100 000 characters, so large tool results will cause `create_event` to fail and throw an exception.
> - **Noise:** Tool call/result scaffolding is not useful as conversation history. Re-injecting it into the system prompt on the next request pollutes the context window with structured JSON rather than human-readable dialogue.
>
> The fix — already implemented in `on_message_added` — is to skip any message whose content list contains a `toolUse` or `toolResult` block:
> ```python
> if any(isinstance(c, dict) and ("toolUse" in c or "toolResult" in c) for c in content):
>     return   # ← do not write MCP scaffolding to memory
> ```
> Only plain-text `user` and `assistant` messages are ever written to AgentCore Memory.

This means Atlassian MCP tool calls (Jira lookups, Confluence searches, etc.) are **never written to AgentCore Memory**. Only the human-readable user prompts and final assistant responses are persisted.

#### Memory is disabled when `MEMORY_ID` is not set

If the `MEMORY_ID` environment variable is not configured, `self._client` is `None` and both hooks are no-ops. The agent runs statelessly with no memory reads or writes.

```python
# agent_factory.py
hooks = [MemoryHook()] if MEMORY_ID else []
```

---

### `agent.py` — entrypoints

Both `@app.entrypoint` handlers follow the same pattern:

```
1. set_atlassian_token(payload)  ← bind token to this async context
2. set_session_id(payload)       ← bind session ID (for memory isolation)
3. get_agent(with_atlassian=...) ← select/create the right cached variant
4. invoke the agent
```

#### Synchronous (non-streaming)

```python
from bedrock_agentcore.runtime import BedrockAgentCoreApp

app = BedrockAgentCoreApp()

@app.entrypoint
def invoke(payload: dict) -> dict:
    atlassian_token = _set_atlassian_token(payload)   # sets ContextVar
    set_session_id(_extract_session_id(payload))
    agent = get_agent(with_atlassian=bool(atlassian_token))
    user_message = _extract_user_message(payload)
    return {"result": _normalise_result(agent(user_message))}
```

#### Async streaming

```python
@app.entrypoint
async def invoke_stream(payload: dict, context=None):
    atlassian_token = _set_atlassian_token(payload)   # sets ContextVar
    set_session_id(_extract_session_id(payload))
    agent = get_agent(with_atlassian=bool(atlassian_token))
    user_message = _extract_user_message(payload)

    async for event in agent.stream_async(user_message, ...):
        yield event
```

> **Declare both `invoke` and `invoke_stream`** with `@app.entrypoint`. AgentCore Runtime uses the streaming path when the client requests `text/event-stream`, and the sync path otherwise.

---

## Why ContextVar, not os.environ

`os.environ` is process-global. Under concurrent async requests (which AgentCore Runtime handles), setting `os.environ["ATLASSIAN_ACCESS_TOKEN"]` in one request overwrites the value being read by another request in flight:

```
Request A ──▶ os.environ["ATLASSIAN_ACCESS_TOKEN"] = "token-A"
Request B ──▶ os.environ["ATLASSIAN_ACCESS_TOKEN"] = "token-B"   ← clobbers A
Request A ──▶ reads "token-B" ✗  (wrong user's token!)
```

This is a silent data-leak between users. **`os.environ` is therefore not used at all** — the `EnvTokenProvider` reads exclusively from the `ContextVar`.

`ContextVar` is scoped to the **async execution context** of a single coroutine chain. Each invocation gets its own isolated slot:

```
Request A ──▶ set_atlassian_token("token-A")  ← stored in context-A
Request B ──▶ set_atlassian_token("token-B")  ← stored in context-B
                │                                       │
                ▼                                       ▼
     EnvTokenProvider.get_access_token()    EnvTokenProvider.get_access_token()
        reads "token-A" ✓                     reads "token-B" ✓
```

No locks, no race conditions, no shared state.

---

## Why Two Cached Agent Variants

Strands `Agent` calls `MCPClient.list_tools()` once at construction time to build the agent's tool registry. There is no supported API to inject tools into an already-running agent instance.

Constructing a new `Agent` per request would work but is expensive — it opens a new MCP connection and re-fetches the full tool list on every invocation.

The two-variant cache gives you the best of both worlds:

- **First request** with Atlassian token → constructs `"atlassian"` agent (slow, ~1-2 s)
- **Subsequent requests** with Atlassian token → returns the cached instance (fast, <1 ms)
- **Requests without a token** → `"base"` agent is used, no MCP connection overhead

The transport factory's `ContextVar` design means the cached agent always reads the **current request's token** even though the `MCPClient` object itself is reused across requests.

---

## Request Payload Contract

The caller must POST JSON to `/invocations` in one of two shapes:

**Flat (direct agent invocation)**
```json
{
  "prompt": "List my open Jira issues",
  "atlassianToken": "<user_oauth_access_token>",
  "sessionId": "<stable_user_identifier>"
}
```

**Nested (AgentCore Runtime envelope)**
```json
{
  "input": {
    "prompt": "List my open Jira issues"
  },
  "atlassianToken": "<user_oauth_access_token>",
  "sessionId": "<stable_user_identifier>"
}
```

| Field            | Required | Description                                                      |
|------------------|----------|------------------------------------------------------------------|
| `prompt`         | Yes      | The user's message                                               |
| `atlassianToken` | No       | Atlassian OAuth access token. If absent, Atlassian tools are off |
| `sessionId`      | No       | Stable ID (e.g. Cognito `sub`) for memory history isolation. Defaults to `"default"` |

---

## Streaming vs Non-Streaming

AgentCore Runtime will route to the streaming entrypoint when the client sets `Accept: text/event-stream`. Streaming responses are newline-delimited JSON events:

```
data: {"event":{"contentBlockDelta":{"delta":{"text":"Here are your open Jira issues..."}}}}
data: {"message":{"role":"assistant","content":[{"text":"Here are your open Jira issues..."}]}}
```

Tool-use messages (MCP round-trips to Atlassian) are filtered out server-side and never sent to the client — the caller only sees the final text content.

---

## Local Development

There is no `os.environ` fallback — it was removed because it is process-global and unsafe under concurrent async requests. For local runs, pass the token in the request payload the same way the frontend does:

```bash
export MODEL_ID=eu.anthropic.claude-sonnet-4-20250514-v1:0
export MODEL_REGION=eu-west-1

# Start the runtime
python -m agentcore_strands.agent
```

Then POST with the token in the body:

```bash
curl -s -X POST http://localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -d '{
    "input": { "prompt": "List my open Jira issues" },
    "atlassianToken": "<access_token_from_your_frontend_or_oauth_flow>"
  }'
```

The `atlassianToken` value is the **`access_token`** obtained by the frontend (or any OAuth client) after completing the Atlassian OAuth 2.0 (PKCE) flow described in [ATLASSIAN_MCP_INTEGRATION_FRONTEND.md](ATLASSIAN_MCP_INTEGRATION_FRONTEND.md). The backend never fetches this token itself — it always arrives in the request payload.

---

## Dependencies

```toml
[project]
dependencies = [
    "strands-agents>=0.1.0",       # Strands Agent + MCPClient + BedrockModel
    "bedrock-agentcore>=0.1.0",    # BedrockAgentCoreApp runtime
    "mcp-proxy-for-aws>=1.1.5",    # streamable_http_client
    "httpx>=0.24.0",               # HTTP client underlying the MCP transport
]
```

---

## References

- [Atlassian Remote MCP Server](https://support.atlassian.com/atlassian-rovo-mcp-server/)
- [Atlassian Supported MCP Tools](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/)
- [Atlassian OAuth 2.0 (3LO)](https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/)
- [Model Context Protocol spec](https://modelcontextprotocol.io)
- [Strands Agents — MCP](https://strandsagents.com/latest/user-guide/concepts/tools/mcp-tools/)
- [AWS Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime.html)
