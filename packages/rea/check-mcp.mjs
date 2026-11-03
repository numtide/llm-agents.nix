// Exercise the installed stdio server without changing agent configuration.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const server = spawn(process.argv[2], ["mcp"], {
  stdio: ["pipe", "pipe", "inherit"],
});
const lines = createInterface({ input: server.stdout });
const pending = new Map();

function fail(error) {
  for (const request of pending.values()) request.reject(error);
  pending.clear();
}

server.on("error", fail);
server.on("exit", (code, signal) => {
  fail(new Error(`MCP server exited: ${code ?? signal}`));
});
lines.on("line", (line) => {
  try {
    const message = JSON.parse(line);
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  } catch (error) {
    fail(error);
  }
});

function send(message) {
  server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", ...message })}\n`);
}

function request(id, method, params) {
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    send({ id, method, params });
  });
}

const timeout = setTimeout(() => {
  fail(new Error("MCP install check timed out"));
  server.kill("SIGKILL");
}, 60_000);

try {
  const initialized = await request(1, "initialize", {
    protocolVersion: "2025-03-26",
    capabilities: {},
    clientInfo: { name: "nix-install-check", version: "1" },
  });
  assert.ok(initialized.capabilities.tools);
  send({ method: "notifications/initialized" });
  const { tools } = await request(2, "tools/list", {});
  assert.ok(tools.length > 0);
  assert.ok(tools.every((tool) => tool.name && tool.inputSchema));
  console.log(`MCP initialization and tools/list passed (${tools.length} tools)`);
} finally {
  clearTimeout(timeout);
  lines.close();
  server.stdin.end();
  server.kill("SIGKILL");
}
