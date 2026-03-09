"""MCP transport factories for Atlassian connections."""
import logging
from contextlib import asynccontextmanager
from contextvars import ContextVar

import httpx
from mcp.client.streamable_http import streamable_http_client
from mcp.shared._httpx_utils import MCP_DEFAULT_SSE_READ_TIMEOUT, MCP_DEFAULT_TIMEOUT

logger = logging.getLogger(__name__)

# Request-scoped token — async-safe alternative to os.environ for concurrent requests.
_atlassian_token: ContextVar[str | None] = ContextVar("atlassian_token", default=None)

# Request-scoped session ID — isolates memory history per user per request.
_session_id: ContextVar[str] = ContextVar("session_id", default="default")


def set_atlassian_token(token: str) -> None:
    """Bind the Atlassian token to the current async context."""
    _atlassian_token.set(token)


def set_session_id(session_id: str) -> None:
    """Bind the session ID to the current async context."""
    _session_id.set(session_id or "default")


def get_session_id() -> str:
    """Return the session ID bound to the current async context."""
    return _session_id.get()


_ATLASSIAN_MCP_URL = "https://mcp.atlassian.com/v1/mcp"


class EnvTokenProvider:
    """Reads the Atlassian access token from the current async context.

    The token must be bound via :func:`set_atlassian_token` before the
    transport is opened. For local development, call ``set_atlassian_token()``
    explicitly at startup rather than relying on ``os.environ`` — the env var
    approach is process-global and unsafe under concurrent requests.
    """

    def get_access_token(self) -> str:
        token = _atlassian_token.get()
        if not token:
            raise RuntimeError(
                "Atlassian access token is not set. "
                "Call set_atlassian_token() before invoking the agent."
            )
        return token


def create_atlassian_transport():
    """Return an async context-manager transport for the Atlassian MCP endpoint.

    Reads the per-request Atlassian token from the async-safe ``ContextVar``
    (set via :func:`set_atlassian_token`) and passes it as a Bearer token.
    The MCP session ID is assigned by the Atlassian server on initialisation.
    """

    @asynccontextmanager
    async def _transport():
        token = EnvTokenProvider().get_access_token()
        headers = {
            "Authorization": f"Bearer {token}",
        }
        timeout = httpx.Timeout(MCP_DEFAULT_TIMEOUT, read=MCP_DEFAULT_SSE_READ_TIMEOUT)
        async with httpx.AsyncClient(
            headers=headers, timeout=timeout, follow_redirects=True
        ) as http_client:
            async with streamable_http_client(
                _ATLASSIAN_MCP_URL,
                http_client=http_client,
                terminate_on_close=True,
            ) as streams:
                yield streams

    return _transport
