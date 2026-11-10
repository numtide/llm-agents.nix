# Kandev

Kandev manages its built-in agent runtimes according to each upstream
integration. On Local and Worktree executors, direct ACP CLIs prefer an
executable already on `PATH`; managed `npx` commands remain the fallback and
the container runtime default. Separate ACP adapter profiles keep using their
adapter rather than substituting the underlying CLI.

## Local runtime packages

Agent support flags add known CLIs to the local runtime `PATH`. They are opt-in
so the default package remains independent of every provider:

```nix
kandev.override {
  claudeSupport = true;
  codexSupport = true;
  geminiSupport = true;
  piSupport = true;
  ompSupport = true;
  opencodeSupport = true;
  copilotSupport = true;
  hermesSupport = true;
  ampSupport = true;
  cursorSupport = true;
  droidSupport = true;
  grokSupport = true;
  kilocodeSupport = true;
  kimiSupport = true;
  qoderSupport = true;
  qwenSupport = true;
}
```

The flags control executable availability, not Kandev's agent registry or the
profile selected for a task. Their exact role follows the built-in integration.
OpenCode, Copilot, Gemini, Droid, Kilocode, and Qwen prefer the packaged CLI for
host ACP probes, inference, command previews, and task launches. Claude, Codex,
Pi, and Amp retain their separate ACP adapters. Other CLIs serve their built-in
profile's discovery, login, passthrough, or native runtime behavior. Claude
and Codex support also point their adapters (`claude-agent-acp` via
`CLAUDE_CODE_EXECUTABLE`, `codex-acp` via `CODEX_PATH`) at the Nix-packaged
executables instead of their incompatible bundled binaries on NixOS.

For OpenCode, a packaged `opencode` on `PATH` also overrides Kandev's stored
OpenCode runtime selection: Kandev uses it as the native runtime and derives the
v1/v2 family from `opencode --version`. The managed `opencode-ai` and
`@opencode/cli` npm runtimes ship FHS-linked binaries that only run on NixOS
with `programs.nix-ld.enable`.

Pi chat and inference retain Kandev's upstream `npx pi-acp` path. This package's
passthrough patch launches the local `pi` CLI, so enable `piSupport` or otherwise
provide `pi` on `PATH` before selecting Pi passthrough.

## Custom TUI agents and tools

`extraPackages` adds arbitrary executables to the same runtime `PATH`:

```nix
kandev.override {
  extraPackages = [
    pkgs.gh
    pkgs.my-custom-agent
  ];
}
```

This supports **Settings > Agents > Add TUI Agent**, where Kandev looks up the
registered binary name on `PATH`. Register a stable bare command such as
`my-custom-agent`, not a versioned Nix store path. Adding a package does not
create or configure an agent; the Kandev UI still owns its display name,
command, static `{{model}}` substitution, and optional MCP strategy.

These packages affect Local and Worktree execution on the Kandev host. Docker
images and SSH hosts need their own executable and credential provisioning.

## Desktop runtime

Build one runtime and pass it to Kandev Desktop so its embedded backend and
Finder-launched application use identical packages and environment:

```nix
let
  kandevRuntime = pkgs.kandev.override {
    claudeSupport = true;
    ompSupport = true;
    extraPackages = [ pkgs.gh ];
  };
in
pkgs.kandev-desktop.override {
  inherit kandevRuntime;
}
```
