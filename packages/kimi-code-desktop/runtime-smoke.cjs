const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const [appDir, version, shell] = process.argv.slice(2);
assert.ok(process.versions.electron, "Use the packaged Electron for native ABI checks");

const resources = path.join(appDir, process.platform === "darwin" ? "Resources" : "resources");
const asar = path.join(resources, "app.asar");
const metadata = JSON.parse(fs.readFileSync(path.join(asar, "package.json"), "utf8"));
assert.equal(metadata.name, "kimi-code-app");
assert.equal(metadata.version, version);
assert.ok(fs.statSync(path.join(resources, "desktop-dist/index.html")).isFile());

// Search must work without downloading an executable on first launch.
assert.match(execFileSync("rg", ["--version"], { encoding: "utf8" }), /^ripgrep /);
assert.match(execFileSync("fd", ["--version"], { encoding: "utf8" }), /^fd /);

// Loading the real module checks its Electron ABI and ELF dependencies. Creating
// a terminal also exercises the PTY's native helper and shell execution.
const pty = require(path.join(asar, "node_modules/node-pty"));
const terminal = pty.spawn(shell, ["-c", "printf 'kimi-code-desktop-pty-ok\\n'"], {
  name: "xterm-256color",
  cols: 80,
  rows: 24,
  cwd: process.env.HOME,
  env: process.env,
});
let output = "";
const timeout = setTimeout(() => {
  terminal.kill();
  throw new Error("Timed out waiting for the bundled native PTY");
}, 10000);
terminal.onData((data) => {
  output += data;
});
terminal.onExit(({ exitCode }) => {
  clearTimeout(timeout);
  assert.equal(exitCode, 0, `PTY output: ${JSON.stringify(output)}`);
  assert.match(output, /kimi-code-desktop-pty-ok/);
  console.log(`Kimi Code Desktop ${version}: Electron, search tools, and native PTY work`);
});
