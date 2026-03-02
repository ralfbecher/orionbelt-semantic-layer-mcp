# CLAUDE.md

## Project Overview

**OrionBelt Semantic Layer MCP** is a thin MCP server that delegates all business logic to the OrionBelt Semantic Layer REST API via HTTP. It contains no embedded engine — pure API pass-through.

## Architecture

```
LLM Client  ──MCP──▶  server.py  ──HTTP──▶  OrionBelt Semantic Layer API
                       (FastMCP + httpx)     (Cloud Run / localhost)
```

- **No business logic** — all tool calls delegate to the REST API
- **Auto-session management** — creates an API session on first tool call, caches the ID
- **7 tools** (no session tools exposed — session handling is internal)
- **3 prompts + 1 resource** — static text, identical to the main repo's MCP server

## Commands

```bash
# Install
uv sync                          # main deps
uv sync --all-groups             # include dev deps (pytest, respx, ruff)

# Run
uv run python server.py                       # stdio (default)
MCP_TRANSPORT=http uv run python server.py    # HTTP on :9000

# Tests
uv run pytest                    # all tests (uses respx to mock API)

# Lint
uv run ruff check server.py
uv run ruff format server.py tests/
```

## Configuration

Environment variables or `.env` file (pydantic-settings):

| Variable | Default | Description |
|----------|---------|-------------|
| `API_BASE_URL` | — (required, see `.env.example`) | OrionBelt Semantic Layer REST API URL |
| `MCP_TRANSPORT` | `stdio` | `stdio`, `http`, or `sse` |
| `MCP_SERVER_HOST` | `localhost` | Bind host for HTTP/SSE |
| `MCP_SERVER_PORT` | `9000` | Bind port for HTTP/SSE |
| `LOG_LEVEL` | `INFO` | Logging level |
| `API_TIMEOUT` | `30` | HTTP timeout in seconds |

## Entrypoint

For Prefect Horizon: `server.py:mcp`

## Tool → API Mapping

| MCP Tool | API Endpoint | Notes |
|----------|-------------|-------|
| `get_obml_reference()` | — | Returns static OBML_REFERENCE string |
| `load_model(model_yaml)` | `POST /sessions/{id}/models` | Auto-creates session |
| `validate_model(model_yaml)` | `POST /sessions/{id}/validate` | Always 200 |
| `describe_model(model_id)` | `GET /sessions/{id}/models/{mid}` | Formats nested JSON |
| `compile_query(...)` | `POST /sessions/{id}/query/sql` | Simple + full mode |
| `list_models()` | `GET /sessions/{id}/models` | Lists models in session |
| `list_dialects()` | `GET /dialects` | No session needed |

## Session Management

Sessions are fully internal — the LLM never sees session IDs:
1. On first API call, `POST /sessions` creates one
2. Session ID is cached in `_api_session_id`
3. On 404 (expired), auto-recreates and retries once
4. Best-effort cleanup on shutdown via `DELETE /sessions/{id}`
