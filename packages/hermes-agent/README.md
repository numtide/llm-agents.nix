# hermes-agent

Self-improving AI agent by Nous Research. This package bundles the TUI, the web
dashboard, and the messaging gateway. It gives Hermes Python environments built
by Nix instead of letting Hermes install packages at runtime.

## Choose optional features with `extras`

Hermes keeps provider SDKs, tool backends, and gateway adapters in optional
Python extras and installs them on first use. This package sets
`HERMES_DISABLE_LAZY_INSTALLS=1`. A feature whose extra is missing logs a
warning and stays disabled.

Choose extras at build time with the `extras` argument. It takes upstream's
extra names. All of the following extras are in the default:

| Extra | Enables |
|---|---|
| `anthropic` | Anthropic provider |
| `mistral` | Mistral provider |
| `bedrock` | AWS Bedrock provider |
| `mcp` | MCP servers |
| `acp` | `hermes-acp` for ACP editors |
| `exa`, `firecrawl`, `parallel-web`, `ddgs` | Web search and extraction backends |
| `fal` | Image generation through fal.ai |
| `edge-tts` | Edge text-to-speech |
| `tts-premium` | ElevenLabs text-to-speech |
| `voice` | Voice input, with local transcription on Linux only |
| `messaging` | Telegram, Discord, and Slack gateway adapters |
| `matrix` | Matrix gateway adapter with E2EE, on Linux only |
| `modal` | Modal sandbox backend |

Upstream moved `cron`, `pty`, `web`, `vision`, `nemo-relay`, and
`doc-extract` into its core dependencies. The `extras` argument accepts these
names and adds nothing for them.

The default is the set that this package shipped before `extras` existed. If
you do not pass `extras`, `nix run` and your configuration work as before.
To change the set, pass a list that replaces the default:

```nix
# Telegram, Discord, and Slack gateway on Anthropic
hermes-agent.override {
  extras = [
    "anthropic"
    "mcp"
    "messaging"
  ];
}
```

```nix
# Upstream's core dependencies only
hermes-agent.override { extras = [ ]; }
```

`hermes-agent.defaultExtras` lists the default extras.
`hermes-agent.optional-dependencies` lists every extra that this package
provides.

Nix builds Hermes itself without extras. A change to `extras` rebuilds only the
Python environment and the wrapper scripts. The binary cache still serves Hermes.

An extra name that this package does not provide fails evaluation. If upstream
renames or drops an extra, this package follows upstream on its next update. The
old name in your list then fails evaluation, and the feature does not disappear
without notice.

## Add Python packages for plugins

Plugins run in the Python interpreter of Hermes. The Hermes package manager
installs plugin dependencies only into environments that it manages, and a Nix
install has none. Add the dependencies with `withPythonPackages`:

```nix
hermes-agent.withPythonPackages (ps: [ ps.hindsight-client ])
```

You can call `override` and `withPythonPackages` in either order. Each further
call adds to the earlier packages. The `extraPythonPackages` argument of
`override` sets extras and plugin packages in one call:

```nix
hermes-agent.override {
  extras = [
    "anthropic"
    "messaging"
  ];
  extraPythonPackages = ps: [ ps.hindsight-client ];
}
```

The packages reach every entry point, the TUI gateway, and the Python that
`hermes gateway install` writes into the service unit.

The Hermes package manager still installs and runs managed tools, such as MCP
servers started with `npx` or `uvx`.

## Patch or rebuild Hermes itself

`hermes-agent` wraps `hermes-agent.unwrapped`, which holds the Hermes build. A
call to `overrideAttrs` or `overridePythonAttrs` on `hermes-agent` fails
evaluation. Override `hermes-agent.unwrapped` and pass the result back:

```nix
hermes-agent.override {
  hermes-agent-unwrapped = hermes-agent.unwrapped.overridePythonAttrs (old: {
    patches = old.patches or [ ] ++ [ ./fix.patch ];
  });
}
```

This rebuilds Hermes. The `extras` selection stays the same. The Python
environment uses the interpreter of `hermes-agent.unwrapped`, so a different
Python version also goes through `hermes-agent.unwrapped`:

```nix
hermes-agent.override {
  hermes-agent-unwrapped = hermes-agent.unwrapped.override { python3 = python313; };
}
```

## Links

- [Hermes Agent documentation](https://hermes-agent.nousresearch.com/)
- [Hermes Agent releases](https://github.com/NousResearch/hermes-agent/releases)
