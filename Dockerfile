# -------------------------------------------------------------------
# Bedrock AgentCore Runtime requires linux/arm64 containers.
# This image uses uv for fast, reproducible dependency installation.
# -------------------------------------------------------------------

FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

WORKDIR /app

# Install dependencies first (layer caching via uv.lock)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# Copy agent source code and install project
COPY src/ ./src/
RUN uv sync --frozen --no-dev

# AgentCore Runtime expects the application on port 8080
EXPOSE 8080

# Set Python to unbuffered mode for better logging
ENV PYTHONUNBUFFERED=1

# Run with the SDK app using the installed venv
CMD [".venv/bin/python", "src/agentcore_strands/agent.py"]
