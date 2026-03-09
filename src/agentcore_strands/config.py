"""Runtime configuration loaded from environment variables."""
import os
import logging
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning, module="websockets")
warnings.filterwarnings("ignore", category=DeprecationWarning, module="uvicorn")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    stream=sys.stdout,
)

MODEL_ID: str = os.environ.get("MODEL_ID", "eu.anthropic.claude-sonnet-4-20250514-v1:0")
MODEL_REGION: str = os.environ.get("MODEL_REGION", "eu-west-1")
MEMORY_ID: str | None = os.environ.get("MEMORY_ID")

SYSTEM_PROMPT: str = (Path(__file__).parent / "system-prompt.md").read_text(encoding="utf-8")
