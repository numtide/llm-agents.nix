#!/usr/bin/env python3
"""Exercise the installed MCP stdio server without writing agent configuration."""

from __future__ import annotations

import json
import os
import selectors
import subprocess
import sys
import time
from typing import IO, Any, Self, cast

PROTOCOL_VERSION = "2025-03-26"
CLIENT_INFO = {"name": "nix-install-check", "version": "1"}
REQUEST_TIMEOUT_SECONDS = 60.0
READ_CHUNK_BYTES = 65536
TERMINATE_TIMEOUT_SECONDS = 10.0


def _pipe(stream: IO[bytes] | None) -> IO[bytes]:
    """Return a pipe that Popen was asked to create, or fail loudly."""
    if stream is None:
        msg = "MCP server pipe was not created"
        raise RuntimeError(msg)
    return stream


class McpServer:
    """A JSON-RPC client for the `rea mcp` stdio server."""

    def __init__(self, executable: str) -> None:
        """Start the server and register its stdout with a selector."""
        self._process = subprocess.Popen(
            [executable, "mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
        )
        self._selector = selectors.DefaultSelector()
        self._selector.register(_pipe(self._process.stdout), selectors.EVENT_READ)
        self._pending = bytearray()

    def __enter__(self) -> Self:
        """Return the running server."""
        return self

    def __exit__(self, *_exc_info: object) -> None:
        """Shut the server down and release the selector."""
        self._selector.close()
        _pipe(self._process.stdin).close()
        self._process.terminate()
        try:
            self._process.wait(timeout=TERMINATE_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            self._process.kill()
            self._process.wait()

    def notify(self, message: dict[str, Any]) -> None:
        """Send a request or notification without waiting for a reply."""
        stdin = _pipe(self._process.stdin)
        stdin.write(json.dumps(message).encode() + b"\n")
        stdin.flush()

    def receive(self, request_id: int) -> object:
        """Return the result of the response carrying ``request_id``."""
        deadline = time.monotonic() + REQUEST_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            newline = self._pending.find(b"\n")
            if newline < 0:
                remaining = max(0.0, deadline - time.monotonic())
                if not self._selector.select(remaining):
                    break
                chunk = os.read(_pipe(self._process.stdout).fileno(), READ_CHUNK_BYTES)
                if not chunk:
                    msg = "MCP server exited before responding"
                    raise RuntimeError(msg)
                self._pending.extend(chunk)
                continue
            line = bytes(self._pending[:newline])
            del self._pending[: newline + 1]
            message = cast("dict[str, Any]", json.loads(line))
            if message.get("id") != request_id:
                continue
            if "error" in message:
                msg = f"MCP request {request_id} failed: {message['error']}"
                raise RuntimeError(msg)
            return cast("object", message["result"])
        msg = f"MCP request {request_id} timed out"
        raise TimeoutError(msg)


def check_handshake(server: McpServer) -> None:
    """Initialize the session and list tools, asserting both replies are sane."""
    server.notify(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": CLIENT_INFO,
            },
        }
    )
    result = cast("dict[str, Any]", server.receive(1))
    if "tools" not in cast("dict[str, Any]", result.get("capabilities", {})):
        msg = f"initialize did not advertise tools: {result}"
        raise RuntimeError(msg)

    server.notify({"jsonrpc": "2.0", "method": "notifications/initialized"})
    server.notify({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    tools = cast(
        "list[dict[str, Any]]", cast("dict[str, Any]", server.receive(2))["tools"]
    )
    if not tools or not all("name" in tool and "inputSchema" in tool for tool in tools):
        msg = f"tools/list returned unusable entries: {tools}"
        raise RuntimeError(msg)
    print(f"MCP initialization and tools/list passed ({len(tools)} tools)")


def main(argv: list[str]) -> None:
    """Run the handshake against the server executable in ``argv[1]``."""
    if len(argv) != 2:  # noqa: PLR2004
        msg = "usage: check-mcp.py PATH/TO/rea"
        raise SystemExit(msg)
    with McpServer(argv[1]) as server:
        check_handshake(server)


if __name__ == "__main__":
    main(sys.argv)
