"""Text-cleaning utilities for AgentCore responses."""
import re


_INVOKE_RE = re.compile(r"<invoke[^>]*>.*?</invoke>", re.DOTALL | re.IGNORECASE)
_PARAM_RE = re.compile(r"<parameter[^>]*>.*?</parameter>", re.DOTALL | re.IGNORECASE)
_MULTI_NEWLINE_RE = re.compile(r"\n\s*\n")
_MULTI_SPACE_RE = re.compile(r"[ \t]+")


def clean_text(text: str, *, preserve_whitespace: bool = False) -> str:
    """Remove tool-invocation markup from assistant text.

    Args:
        text: Raw text that may contain ``<invoke>`` / ``<parameter>`` tags.
        preserve_whitespace: When ``True`` (streaming chunks), only markup is
            stripped and spacing is left intact so adjacent chunks don't run
            words together.  When ``False`` (final messages), light whitespace
            normalisation is also applied.
    """
    if not isinstance(text, str):
        text = str(text)

    text = _INVOKE_RE.sub("", text)
    text = _PARAM_RE.sub("", text)

    if preserve_whitespace:
        return text

    text = _MULTI_NEWLINE_RE.sub("\n", text)
    text = _MULTI_SPACE_RE.sub(" ", text)
    return text.strip()


def clean_message_payload(payload: dict | list) -> dict | list:
    """Clean tool markup from a structured assistant message payload in-place."""
    if isinstance(payload, dict):
        content = payload.get("content")
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and "text" in item:
                    item["text"] = clean_text(item["text"])
    return payload
