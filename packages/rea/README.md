# REA

REA provides a reverse engineering CLI and MCP server. This package includes
Node.js, Linux process utilities, and the matching Frida native binding.
Configure Ghidra, JADX, browsers, and other analysis providers separately for the
workflows that need them.

```console
nix run github:numtide/llm-agents.nix#rea -- --help
nix run github:numtide/llm-agents.nix#rea -- setup --client codex --dry-run
```

Install REA in a persistent Nix profile or your NixOS/Home Manager configuration
before applying setup. A one-shot `nix run` does not keep its store path alive
against garbage collection.

For a declarative MCP configuration, use `${rea}/bin/rea` as the command and
`[ "mcp" ]` as its arguments, where `rea` is this flake's package in your Nix
configuration. Rebuilding then updates the server path with the package.
Upstream `rea setup` records specific Node.js and entry-script paths; rerun setup
after upgrading a persistent installation to refresh those registrations.
Manage package upgrades through Nix rather than `rea update`.

The install checks verify the CLI version/help, load node-pty, exercise Frida's
local device and process enumeration, and initialize MCP over stdio and list its
tools. The updater tracks REA releases and refreshes the Frida pins when its
lockfile changes.
