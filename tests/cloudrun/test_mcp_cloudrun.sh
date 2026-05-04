#!/usr/bin/env bash
# Smoke-test the MCP server over Streamable HTTP.
# Works against a local Docker container or a deployed Cloud Run URL.
#
# Usage:
#   ./tests/cloudrun/test_mcp_cloudrun.sh http://localhost:9000
#   ./tests/cloudrun/test_mcp_cloudrun.sh https://your-domain.com
#
# The script does a full MCP initialize → tools/list → list_dialects handshake
# using the Streamable HTTP transport (MCP spec 2025-03-26).

set -euo pipefail

MCP_BASE_URL="${1:?Usage: $0 <MCP_BASE_URL>}"
# FastMCP HTTP serves at /mcp (no trailing slash — /mcp/ redirects 307)
MCP_URL="${MCP_BASE_URL%/}/mcp"

echo "Testing MCP at $MCP_URL"
echo

python3 - "$MCP_URL" <<'PY'
import json
import re
import sys
import urllib.error
import urllib.request

mcp_url = sys.argv[1]
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}


def _post(payload: dict, session_id: str | None = None) -> tuple[int, dict[str, str], bytes]:
    body = json.dumps(payload).encode("utf-8")
    req_headers = dict(headers)
    if session_id:
        req_headers["Mcp-Session-Id"] = session_id
    req = urllib.request.Request(mcp_url, data=body, headers=req_headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers or {}), exc.read() or b""


def _parse_response(body: bytes) -> dict:
    """Streamable HTTP can return JSON or SSE-framed JSON. Handle both."""
    text = body.decode("utf-8", errors="replace").strip()
    if not text:
        return {}
    # SSE frame: lines starting with "data: " contain JSON
    sse_match = re.search(r"^data:\s*(.+)$", text, flags=re.MULTILINE)
    if sse_match:
        return json.loads(sse_match.group(1))
    return json.loads(text)


# 1. initialize
status, resp_headers, body = _post(
    {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "cloudrun-smoke-test", "version": "1.0"},
        },
    }
)
if status != 200:
    print(f"  initialize FAILED: HTTP {status}")
    print(body.decode("utf-8", errors="replace"))
    sys.exit(1)

session_id = resp_headers.get("mcp-session-id") or resp_headers.get("Mcp-Session-Id")
init_data = _parse_response(body)
server_name = init_data.get("result", {}).get("serverInfo", {}).get("name", "?")
print(f"  initialize: PASS (server={server_name}, session={session_id or 'stateless'})")

# 2. notifications/initialized (required by protocol)
_post(
    {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
    session_id=session_id,
)

# 3. tools/list
status, _, body = _post(
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    session_id=session_id,
)
if status != 200:
    print(f"  tools/list FAILED: HTTP {status}")
    print(body.decode("utf-8", errors="replace"))
    sys.exit(1)
data = _parse_response(body)
tools = data.get("result", {}).get("tools", [])
assert len(tools) >= 15, f"Expected >= 15 tools, got {len(tools)}"
print(f"  tools/list: PASS ({len(tools)} tools registered)")

# 4. tools/call list_dialects (no session needed, hits the API)
status, _, body = _post(
    {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "list_dialects", "arguments": {}},
    },
    session_id=session_id,
)
if status != 200:
    print(f"  list_dialects FAILED: HTTP {status}")
    print(body.decode("utf-8", errors="replace"))
    sys.exit(1)
data = _parse_response(body)
content = data.get("result", {}).get("content", [{}])
text = content[0].get("text", "") if content else ""
assert "postgres" in text.lower(), f"Expected postgres in dialects, got: {text[:200]}"
print("  list_dialects: PASS")

print()
print("All tests passed")
PY
