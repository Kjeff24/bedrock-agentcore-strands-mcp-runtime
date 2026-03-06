"""MCP transport factories for Gateway and Atlassian connections."""
import hashlib
import os
import logging
from contextlib import asynccontextmanager

import httpx
from mcp.client.streamable_http import streamable_http_client
from mcp.shared._httpx_utils import MCP_DEFAULT_SSE_READ_TIMEOUT, MCP_DEFAULT_TIMEOUT
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client

from .config import GATEWAY_URL, MODEL_REGION

logger = logging.getLogger(__name__)

_ATLASSIAN_MCP_URL = "https://mcp.atlassian.com/v1/mcp"


class EnvTokenProvider:
    """Reads the Atlassian access token injected per-request into the environment.

    The frontend sends a short-lived per-user token with each request. It is
    stored in ``ATLASSIAN_ACCESS_TOKEN`` for the lifetime of that invocation so
    every component can resolve it on demand rather than threading it through
    every call site.
    """

    def get_access_token(self) -> str:
        token = os.environ.get("ATLASSIAN_ACCESS_TOKEN")
        if not token:
            raise RuntimeError("ATLASSIAN_ACCESS_TOKEN is not set")
        return token


def create_gateway_transport():
    """Return a transport callable for the AgentCore Gateway MCP endpoint.

    Returns ``None`` when ``GATEWAY_URL`` is not configured so callers can
    safely skip adding the client.
    """
    if not GATEWAY_URL:
        return None
    return lambda: aws_iam_streamablehttp_client(
        endpoint=GATEWAY_URL,
        aws_region=MODEL_REGION,
        aws_service="bedrock-agentcore",
    )


def create_atlassian_transport():
    """Return an async context-manager transport for the Atlassian MCP endpoint.

    A stable, non-identifying MCP session ID is derived by hashing the token so
    Atlassian MCP can correlate tool calls within the same logical session
    without us persisting any extra state.
    """

    @asynccontextmanager
    async def _transport():
        token = EnvTokenProvider().get_access_token()
        session_id = hashlib.sha256(token.encode("utf-8")).hexdigest()
        headers = {
            "Authorization": f"Bearer {token}",
            "Mcp-Session-Id": session_id,
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
